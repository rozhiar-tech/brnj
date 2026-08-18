import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat.dart';
import '../models/user_profile.dart';

/// Thrown when the person you are trying to message does not take messages
/// from you.
///
/// A distinct type rather than a bare exception because the UI has to say
/// which of the three reasons applies, and parsing a Firestore
/// `permission-denied` string to find out is not something to build on.
class DmNotAllowed implements Exception {
  const DmNotAllowed(this.reason);

  final DmBlockReason reason;
}

enum DmBlockReason { closed, followersOnly, blocked }

/// Conversations and the messages in them.
///
/// Shape: `chats/{chatId}` with `chats/{chatId}/messages/{messageId}` under it.
/// The inbox is one query — `memberIds array-contains me`, ordered by
/// `updatedAt` — which is why the last message and the unread counts are
/// denormalised onto the chat document rather than derived from the
/// subcollection. Thirty conversations would otherwise be thirty queries every
/// time the list rebuilt.
class ChatRepository {
  ChatRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _chats =>
      _firestore.collection('chats');

  DocumentReference<Map<String, dynamic>> _doc(String id) => _chats.doc(id);

  CollectionReference<Map<String, dynamic>> _messages(String chatId) =>
      _doc(chatId).collection('messages');

  // ---- the inbox ----------------------------------------------------------

  /// Every conversation this person is in, newest activity first.
  ///
  /// Accepted and pending come back together and are split on the client. Two
  /// server-side queries would need two `array-contains` clauses in one query,
  /// which Firestore does not allow — and an inbox is tens of rows, not
  /// thousands, so the split costs nothing.
  Stream<List<Chat>> watchChats(String uid) => _chats
      .where('memberIds', arrayContains: uid)
      .orderBy('updatedAt', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) => snap.docs.map(Chat.fromDoc).toList());

  Stream<Chat?> watchChat(String chatId) => _doc(
    chatId,
  ).snapshots().map((doc) => doc.exists ? Chat.fromDoc(doc) : null);

  Future<Chat?> getChat(String chatId) async {
    final doc = await _doc(chatId).get();
    return doc.exists ? Chat.fromDoc(doc) : null;
  }

  // ---- starting a conversation --------------------------------------------

  /// Opens the DM with [other], creating it if this is the first message.
  ///
  /// Returns the chat id. Idempotent by construction: the id is derived from
  /// the two uids, so both people tapping "message" at the same moment land in
  /// one conversation rather than two.
  ///
  /// The permission check happens here as well as in the rules. Not because
  /// the rules cannot be trusted — they are what actually enforces it — but
  /// because a rejected write surfaces as `permission-denied` with no way to
  /// tell "they don't take messages" from "you are blocked", and those need
  /// different words on screen.
  Future<String> openDm({
    required AuthorStub me,
    required AuthorStub other,
    UserPrivacy? theirPrivacy,
    bool theyFollowMe = false,
    bool theyBlockedMe = false,
  }) async {
    if (theyBlockedMe) throw const DmNotAllowed(DmBlockReason.blocked);

    final mode = theirPrivacy?.dmMode ?? DmMode.following;
    if (mode == DmMode.none) throw const DmNotAllowed(DmBlockReason.closed);
    if (mode == DmMode.following && !theyFollowMe) {
      throw const DmNotAllowed(DmBlockReason.followersOnly);
    }

    final id = Chat.dmId(me.uid, other.uid);
    final existing = await _doc(id).get();
    if (existing.exists) return id;

    await _doc(id).set(
      Chat(
        id: id,
        kind: ChatKind.dm,
        memberIds: [me.uid, other.uid]..sort(),
        members: {me.uid: me, other.uid: other},
        // Only the initiator. The other side stays in Requests until they
        // reply, which is the whole point of the gate.
        acceptedBy: [me.uid],
        createdBy: me.uid,
      ).toCreateMap(),
    );
    return id;
  }

  Future<String> createGroup({
    required AuthorStub me,
    required List<AuthorStub> others,
    required String title,
  }) async {
    final ref = _chats.doc();
    final members = {me.uid: me, for (final other in others) other.uid: other};

    await ref.set(
      Chat(
        id: ref.id,
        kind: ChatKind.group,
        memberIds: members.keys.toList(),
        members: members,
        // Being added to a group is not a request — somebody you may not know
        // adding you to a room of forty is, but that is what leaving is for,
        // and a group sitting unanswered in Requests helps nobody.
        acceptedBy: members.keys.toList(),
        admins: [me.uid],
        title: title,
        createdBy: me.uid,
      ).toCreateMap(),
    );
    return ref.id;
  }

  /// The room attached to a community.
  ///
  /// Deterministic id, and members are added as they open it rather than all at
  /// once when the community is created — a community of two thousand would
  /// otherwise need a two-thousand-entry map on one document, which is both a
  /// size limit and a write hotspot.
  Future<String> openCommunityRoom({
    required String communityId,
    required String communityName,
    required AuthorStub me,
  }) async {
    final id = Chat.communityRoomId(communityId);
    final existing = await _doc(id).get();

    if (!existing.exists) {
      await _doc(id).set(
        Chat(
          id: id,
          kind: ChatKind.community,
          memberIds: [me.uid],
          members: {me.uid: me},
          acceptedBy: [me.uid],
          admins: const [],
          title: communityName,
          communityId: communityId,
          createdBy: me.uid,
        ).toCreateMap(),
      );
      return id;
    }

    final chat = Chat.fromDoc(existing);
    if (!chat.isMember(me.uid)) await join(chatId: id, who: me);
    return id;
  }

  /// Adds someone to a conversation they are entitled to be in.
  Future<void> join({required String chatId, required AuthorStub who}) async {
    await _doc(chatId).update({
      'memberIds': FieldValue.arrayUnion([who.uid]),
      'acceptedBy': FieldValue.arrayUnion([who.uid]),
      'members.${who.uid}': who.toMap(),
    });
  }

  /// Accepting a request. Replying does this too — the composer calls it
  /// before the first send, so nobody has to find a button.
  Future<void> accept({required String chatId, required String uid}) async {
    await _doc(chatId).update({
      'acceptedBy': FieldValue.arrayUnion([uid]),
    });
  }

  Future<void> leave({required String chatId, required String uid}) async {
    await _doc(chatId).update({
      'memberIds': FieldValue.arrayRemove([uid]),
      'acceptedBy': FieldValue.arrayRemove([uid]),
      'admins': FieldValue.arrayRemove([uid]),
      'members.$uid': FieldValue.delete(),
    });
  }

  /// Declining a request deletes the conversation outright.
  ///
  /// Not "leave": a one-sided DM nobody accepted is not a conversation, and
  /// leaving it would strand the message in the sender's list looking
  /// delivered forever.
  Future<void> declineRequest(String chatId) async => _doc(chatId).delete();

  // ---- messages -----------------------------------------------------------

  /// Newest first, because that is the order a reversed list wants — the view
  /// renders bottom-up so the newest is on screen without a scroll jump.
  Stream<List<Message>> watchMessages(String chatId, {int limit = 60}) =>
      _messages(chatId)
          .orderBy('at', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(Message.fromDoc).toList());

  Future<void> send({
    required String chatId,
    required Message message,
  }) async => _messages(chatId).add(message.toMap()).then((_) {});

  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) async => _messages(chatId).doc(messageId).delete();

  /// Clears this person's badge.
  ///
  /// The only part of `unread` a client may write, and only to zero — the
  /// rules check both. Incrementing is the Function's job, which is what stops
  /// a client from deciding how many messages it was sent.
  Future<void> markRead({
    required String chatId,
    required String uid,
  }) async => _doc(chatId).update({'unread.$uid': 0});
}
