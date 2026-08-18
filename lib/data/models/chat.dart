import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_profile.dart';

enum ChatKind { dm, group, community }

enum MessageKind { text, image, voice, recipe, system }

/// A conversation.
///
/// Ids are deterministic wherever they can be. A DM is `{uidA}_{uidB}` with the
/// two sorted, and a community room is `community_{id}` — which makes "open the
/// chat with this person" a document read rather than a query, and makes two
/// people tapping each other at the same moment land in one conversation
/// instead of two. The same trick the weekly plan uses for the same reason.
///
/// Only groups get a random id, because there is nothing to derive one from.
class Chat {
  const Chat({
    required this.id,
    required this.kind,
    required this.memberIds,
    required this.members,
    required this.createdBy,
    this.acceptedBy = const [],
    this.admins = const [],
    this.title,
    this.photoUrl,
    this.communityId,
    this.lastMessage,
    this.unread = const {},
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final ChatKind kind;

  /// The array the inbox query filters on. Duplicated by [members] keys, but
  /// Firestore cannot `array-contains` over a map's keys.
  final List<String> memberIds;

  /// Author stubs by uid, so a chat list renders names and avatars without a
  /// profile read per row.
  final Map<String, AuthorStub> members;

  /// Who has accepted this conversation. The request gate: a DM starts with
  /// only its initiator here, and stays in the recipient's Requests tab until
  /// they reply. Groups and community rooms accept on join.
  final List<String> acceptedBy;

  final List<String> admins;
  final String? title;
  final String? photoUrl;

  /// Set on a community room, so leaving the community can close it.
  final String? communityId;

  final String createdBy;
  final LastMessage? lastMessage;

  /// Unread counts by uid. Written by a Function on every incoming message;
  /// the only part a client may touch is zeroing its own key, which is what
  /// opening the conversation does.
  final Map<String, int> unread;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool isMember(String? uid) => uid != null && memberIds.contains(uid);

  bool hasAccepted(String? uid) => uid != null && acceptedBy.contains(uid);

  /// Admin powers exist for groups and community rooms, and nowhere else.
  ///
  /// A DM has a `createdBy` too, and counting that as admin gave whoever sent
  /// the first message the right to accept the conversation on the other
  /// person's behalf and delete their replies — the request gate inverted. The
  /// security rules were fixed to match; this keeps the two from drifting.
  bool isAdmin(String? uid) =>
      uid != null &&
      kind != ChatKind.dm &&
      (uid == createdBy || admins.contains(uid));

  int unreadFor(String? uid) => uid == null ? 0 : unread[uid] ?? 0;

  /// The other person in a DM. Null for anything else, and null for a DM whose
  /// other side is missing — which happens when an account is deleted.
  AuthorStub? otherParty(String? myUid) {
    if (kind != ChatKind.dm || myUid == null) return null;
    final otherUid = memberIds.where((uid) => uid != myUid).firstOrNull;
    return otherUid == null ? null : members[otherUid];
  }

  /// What to show in the list. A DM borrows the other person's name; a group
  /// carries its own.
  String displayTitle(String? myUid) =>
      title ?? otherParty(myUid)?.name ?? '';

  String? displayPhoto(String? myUid) =>
      photoUrl ?? otherParty(myUid)?.photoUrl;

  /// The deterministic id for a conversation between two people.
  ///
  /// Sorted, so both sides compute the same string no matter who starts.
  static String dmId(String a, String b) =>
      (a.compareTo(b) < 0) ? '${a}_$b' : '${b}_$a';

  static String communityRoomId(String communityId) =>
      'community_$communityId';

  factory Chat.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final rawMembers = Map<String, dynamic>.from(
      data['members'] as Map? ?? const {},
    );

    return Chat(
      id: doc.id,
      kind: ChatKind.values.firstWhere(
        (k) => k.name == data['kind'],
        orElse: () => ChatKind.dm,
      ),
      memberIds: (data['memberIds'] as List?)?.cast<String>() ?? const [],
      members: {
        for (final entry in rawMembers.entries)
          entry.key: AuthorStub.fromMap(
            Map<String, dynamic>.from(entry.value as Map? ?? const {}),
          ),
      },
      acceptedBy: (data['acceptedBy'] as List?)?.cast<String>() ?? const [],
      admins: (data['admins'] as List?)?.cast<String>() ?? const [],
      title: data['title'] as String?,
      photoUrl: data['photoUrl'] as String?,
      communityId: data['communityId'] as String?,
      createdBy: data['createdBy'] as String? ?? '',
      lastMessage: data['lastMessage'] == null
          ? null
          : LastMessage.fromMap(
              Map<String, dynamic>.from(data['lastMessage'] as Map),
            ),
      unread: {
        for (final entry
            in Map<String, dynamic>.from(
              data['unread'] as Map? ?? const {},
            ).entries)
          entry.key: (entry.value as num?)?.toInt() ?? 0,
      },
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// What a client is allowed to write when creating a conversation.
  ///
  /// `unread`, `lastMessage`, and `updatedAt` are absent: all three are
  /// Function-owned, and the rules reject a create that carries any of them.
  Map<String, dynamic> toCreateMap() => {
    'kind': kind.name,
    'memberIds': memberIds,
    'members': {
      for (final entry in members.entries) entry.key: entry.value.toMap(),
    },
    'acceptedBy': acceptedBy,
    'admins': admins,
    if (title != null) 'title': title!.trim(),
    if (photoUrl != null) 'photoUrl': photoUrl,
    if (communityId != null) 'communityId': communityId,
    'createdBy': createdBy,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

/// The one-line preview on the inbox row.
///
/// Denormalised onto the chat by a Function rather than read from the messages
/// subcollection: an inbox of thirty conversations would otherwise be thirty
/// extra queries every time the list rebuilt.
class LastMessage {
  const LastMessage({
    required this.text,
    required this.senderUid,
    this.senderName,
    this.kind = MessageKind.text,
    this.at,
  });

  final String text;
  final String senderUid;
  final String? senderName;
  final MessageKind kind;
  final DateTime? at;

  factory LastMessage.fromMap(Map<String, dynamic> map) => LastMessage(
    text: map['text'] as String? ?? '',
    senderUid: map['senderUid'] as String? ?? '',
    senderName: map['senderName'] as String?,
    kind: MessageKind.values.firstWhere(
      (k) => k.name == map['kind'],
      orElse: () => MessageKind.text,
    ),
    at: (map['at'] as Timestamp?)?.toDate(),
  );
}

class Message {
  const Message({
    required this.id,
    required this.author,
    required this.kind,
    this.text = '',
    this.mediaUrl,
    this.durationMs,
    this.recipeId,
    this.replyToId,
    this.replyToText,
    this.at,
  });

  final String id;
  final AuthorStub author;
  final MessageKind kind;
  final String text;
  final String? mediaUrl;

  /// Voice note length, so the bubble can size its waveform before the audio
  /// has been fetched.
  final int? durationMs;

  final String? recipeId;

  final String? replyToId;

  /// A snippet of what is being replied to, copied at send time. Reading the
  /// original instead would mean a fetch per bubble, and would break when the
  /// original is deleted — which is exactly when the reply needs context most.
  final String? replyToText;

  final DateTime? at;

  factory Message.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Message(
      id: doc.id,
      author: AuthorStub.fromMap(
        Map<String, dynamic>.from(data['author'] as Map? ?? const {}),
      ),
      kind: MessageKind.values.firstWhere(
        (k) => k.name == data['kind'],
        orElse: () => MessageKind.text,
      ),
      text: data['text'] as String? ?? '',
      mediaUrl: data['mediaUrl'] as String?,
      durationMs: (data['durationMs'] as num?)?.toInt(),
      recipeId: data['recipeId'] as String?,
      replyToId: data['replyToId'] as String?,
      replyToText: data['replyToText'] as String?,
      at: (data['at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'author': author.toMap(),
    'kind': kind.name,
    'text': text.trim(),
    if (mediaUrl != null) 'mediaUrl': mediaUrl,
    if (durationMs != null) 'durationMs': durationMs,
    if (recipeId != null) 'recipeId': recipeId,
    if (replyToId != null) 'replyToId': replyToId,
    if (replyToText != null) 'replyToText': replyToText,
    'at': FieldValue.serverTimestamp(),
  };

  /// What the inbox row shows for this message. A photo has no words, and
  /// "📷" in a list of names reads worse than the word.
  String previewText(String Function(MessageKind) label) =>
      kind == MessageKind.text ? text : label(kind);
}
