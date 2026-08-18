import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/community.dart';
import '../models/social.dart';
import '../models/user_profile.dart';

/// Communities, their members, and what gets posted in them.
///
/// Shape: `communities/{id}` with three subcollections — `members/{uid}`,
/// `requests/{uid}` for the approval queue, and `posts/{postId}`. Membership is
/// a document rather than an array on the community because an array caps out
/// at a megabyte and, more immediately, because security rules can read one
/// member document cheaply with `exists()` but cannot search an array of ten
/// thousand uids.
///
/// The member document carries a redundant `uid` field. It duplicates the
/// document id, which is normally a smell, but `collectionGroup('members')`
/// cannot filter on document id across parents — and "which communities am I
/// in" is the first query the app makes.
class CommunityRepository {
  CommunityRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _communities =>
      _firestore.collection('communities');

  DocumentReference<Map<String, dynamic>> _doc(String id) =>
      _communities.doc(id);

  CollectionReference<Map<String, dynamic>> _members(String id) =>
      _doc(id).collection('members');

  CollectionReference<Map<String, dynamic>> _requests(String id) =>
      _doc(id).collection('requests');

  CollectionReference<Map<String, dynamic>> _posts(String id) =>
      _doc(id).collection('posts');

  // ---- reading communities ------------------------------------------------

  Stream<Community?> watchCommunity(String id) => _doc(
    id,
  ).snapshots().map((doc) => doc.exists ? Community.fromDoc(doc) : null);

  Future<Community?> getCommunity(String id) async {
    final doc = await _doc(id).get();
    return doc.exists ? Community.fromDoc(doc) : null;
  }

  /// The directory. Ordered by member count because in a directory of fifteen
  /// communities the useful signal is "where are the people", not "what is
  /// newest" — a new empty community at the top is a room nobody is in.
  ///
  /// Private communities are still listed: people need to be able to find one
  /// in order to ask to join. It is the *posts* that are hidden, not the door.
  Stream<List<Community>> watchDirectory({
    CommunityCategory? category,
    String? region,
    int limit = 40,
  }) {
    Query<Map<String, dynamic>> query = _communities;
    if (category != null) {
      query = query.where('category', isEqualTo: category.name);
    }
    if (region != null) query = query.where('region', isEqualTo: region);

    return query
        .orderBy('memberCount', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(Community.fromDoc).toList());
  }

  /// Directory search. Prefix match on a lowercased copy of the name.
  ///
  /// Deliberately not the Arabic/Kurdish normaliser used for recipes: community
  /// names are few and mostly typed by the person looking for them, and the
  /// keyword array that search needs is worth its write cost on thousands of
  /// recipes but not on dozens of communities.
  Future<List<Community>> searchCommunities(String term) async {
    final needle = term.trim().toLowerCase();
    if (needle.isEmpty) return const [];

    final snap = await _communities
        .orderBy('searchName')
        .startAt([needle])
        .endAt(['$needle\uf8ff'])
        .limit(20)
        .get();
    return snap.docs.map(Community.fromDoc).toList();
  }

  /// Communities the given user belongs to.
  ///
  /// Two round trips — member docs, then the parents — because Firestore has no
  /// join. The alternative was denormalising a community stub into each member
  /// document, which then goes stale every time a community is renamed.
  Stream<List<Community>> watchMyCommunities(String uid) {
    return _firestore
        .collectionGroup('members')
        .where('uid', isEqualTo: uid)
        .orderBy('joinedAt', descending: true)
        .limit(50)
        .snapshots()
        .asyncMap((snap) async {
          final refs = snap.docs
              .map((d) => d.reference.parent.parent)
              .whereType<DocumentReference<Map<String, dynamic>>>()
              .toList();
          if (refs.isEmpty) return <Community>[];

          final docs = await Future.wait(refs.map((r) => r.get()));
          return docs
              .where((d) => d.exists)
              .map(Community.fromDoc)
              .toList();
        });
  }

  // ---- membership ---------------------------------------------------------

  Stream<CommunityMember?> watchMembership({
    required String communityId,
    required String uid,
  }) => _members(communityId)
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists ? CommunityMember.fromDoc(doc) : null);

  Stream<List<CommunityMember>> watchMembers(String communityId) =>
      _members(communityId)
          .orderBy('joinedAt', descending: true)
          .limit(100)
          .snapshots()
          .map((snap) => snap.docs.map(CommunityMember.fromDoc).toList());

  /// Join, or ask to.
  ///
  /// Returns true when the person is now a member and false when they are in a
  /// queue, so the caller can say which happened rather than guessing from the
  /// join policy it was holding a moment ago.
  Future<bool> join({
    required Community community,
    required AuthorStub who,
  }) async {
    if (community.needsApproval) {
      await _requests(community.id).doc(who.uid).set({
        'uid': who.uid,
        'author': who.toMap(),
        'requestedAt': FieldValue.serverTimestamp(),
      });
      return false;
    }

    await _members(community.id).doc(who.uid).set({
      'uid': who.uid,
      'author': who.toMap(),
      'role': MemberRole.member.name,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Leave. The owner cannot — a community with no owner has no one who can
  /// approve, promote, or delete it, and Firestore will not undo that for us.
  Future<void> leave({required Community community, required String uid}) async {
    if (uid == community.createdBy) {
      throw StateError('owner-cannot-leave');
    }
    await _members(community.id).doc(uid).delete();
    if (community.moderators.contains(uid)) {
      await _doc(community.id).update({
        'moderators': FieldValue.arrayRemove([uid]),
      });
    }
  }

  /// Whether this person is already in the queue.
  ///
  /// Without it the join button has no way to tell "not a member" from "asked
  /// and waiting", and offers to send a second request that overwrites the
  /// first — which looks to the asker like nothing happened.
  Stream<bool> watchMyRequest({
    required String communityId,
    required String uid,
  }) => _requests(communityId).doc(uid).snapshots().map((doc) => doc.exists);

  Future<void> withdrawRequest({
    required String communityId,
    required String uid,
  }) async => _requests(communityId).doc(uid).delete();

  Stream<List<CommunityJoinRequest>> watchRequests(String communityId) =>
      _requests(communityId)
          .orderBy('requestedAt')
          .limit(100)
          .snapshots()
          .map((snap) => snap.docs.map(CommunityJoinRequest.fromDoc).toList());

  /// Approve a queued request: create the member, drop the request. A batch, so
  /// a crash between the two cannot leave someone both approved and still
  /// waiting.
  Future<void> approve({
    required String communityId,
    required CommunityJoinRequest request,
  }) async {
    final batch = _firestore.batch();
    batch.set(_members(communityId).doc(request.uid), {
      'uid': request.uid,
      'author': request.author.toMap(),
      'role': MemberRole.member.name,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.delete(_requests(communityId).doc(request.uid));
    await batch.commit();
  }

  Future<void> reject({
    required String communityId,
    required String uid,
  }) async => _requests(communityId).doc(uid).delete();

  Future<void> setModerator({
    required String communityId,
    required String uid,
    required bool value,
  }) async {
    await _doc(communityId).update({
      'moderators': value
          ? FieldValue.arrayUnion([uid])
          : FieldValue.arrayRemove([uid]),
    });
    await _members(communityId).doc(uid).update({
      'role': value ? MemberRole.moderator.name : MemberRole.member.name,
    });
  }

  /// Remove someone. Their posts stay: deleting a member's history on the way
  /// out turns a moderation action into a hole in every thread they were part
  /// of. Moderators can delete individual posts if that is what they meant.
  Future<void> removeMember({
    required String communityId,
    required String uid,
  }) async {
    await _members(communityId).doc(uid).delete();
    await _doc(communityId).update({
      'moderators': FieldValue.arrayRemove([uid]),
    });
  }

  // ---- writing communities ------------------------------------------------

  /// Creates the community and its owner membership together.
  ///
  /// The owner row is not optional bookkeeping: every posting rule keys off
  /// `members/{uid}` existing, so a creator without one would be locked out of
  /// the community they just made.
  Future<String> create({
    required Community community,
    required AuthorStub owner,
  }) async {
    final ref = _communities.doc();
    final batch = _firestore.batch();

    batch.set(ref, {
      ...community.toMap(),
      'createdBy': owner.uid,
      'moderators': const <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection('members').doc(owner.uid), {
      'uid': owner.uid,
      'author': owner.toMap(),
      'role': MemberRole.owner.name,
      'joinedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return ref.id;
  }

  /// Deletes the community document.
  ///
  /// Subcollections are not touched here — Firestore does not cascade, and a
  /// client loop over members and posts would be a few hundred writes made
  /// under someone's mobile data. `onCommunityDeleted` sweeps them server-side
  /// instead. Until it runs the community is already gone from every screen,
  /// because every rule and query keys off the document that just vanished.
  Future<void> deleteCommunity(String id) async => _doc(id).delete();

  Future<void> update(Community community) async {
    await _doc(community.id).set(community.toMap(), SetOptions(merge: true));
  }

  // ---- posts --------------------------------------------------------------

  /// The feed inside a community.
  ///
  /// Pinned posts are fetched separately rather than through an
  /// `orderBy('pinned').orderBy('createdAt')` composite: a pinned flag that
  /// participates in the sort means every unpinned page still carries the
  /// pinned ones, and the pinned set is almost always zero or one document.
  Stream<List<CommunityPost>> watchPosts(String communityId, {int limit = 30}) =>
      _posts(communityId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(CommunityPost.fromDoc).toList());

  Stream<List<CommunityPost>> watchPinned(String communityId) => _posts(
    communityId,
  ).where('pinned', isEqualTo: true).limit(3).snapshots().map(
    (snap) => snap.docs.map(CommunityPost.fromDoc).toList(),
  );

  Future<String> addPost({
    required String communityId,
    required CommunityPost post,
  }) async {
    final ref = await _posts(communityId).add(post.toMap());
    return ref.id;
  }

  Future<void> deletePost({
    required String communityId,
    required String postId,
  }) async => _posts(communityId).doc(postId).delete();

  Future<void> setPinned({
    required String communityId,
    required String postId,
    required bool pinned,
  }) async => _posts(communityId).doc(postId).update({'pinned': pinned});

  // ---- post comments ------------------------------------------------------

  Stream<List<Comment>> watchPostComments({
    required String communityId,
    required String postId,
  }) => _posts(communityId)
      .doc(postId)
      .collection('comments')
      .orderBy('createdAt')
      .limit(200)
      .snapshots()
      .map((snap) => snap.docs.map(Comment.fromDoc).toList());

  Future<void> addPostComment({
    required String communityId,
    required String postId,
    required Comment comment,
  }) async {
    await _posts(
      communityId,
    ).doc(postId).collection('comments').add(comment.toMap());
  }

  Future<void> deletePostComment({
    required String communityId,
    required String postId,
    required String commentId,
  }) async {
    await _posts(
      communityId,
    ).doc(postId).collection('comments').doc(commentId).delete();
  }
}
