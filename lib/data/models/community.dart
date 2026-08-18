import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_profile.dart';

/// Who may join, and on whose say-so.
///
/// `approval` is the one that matters here. A community that anyone can walk
/// into is not somewhere people post freely, and the plan is explicit that
/// closed, moderator-approved membership is what makes a space usable for the
/// people most likely to leave first.
enum JoinPolicy { open, approval }

/// `private` hides the posts entirely; `public` shows them to anyone and gates
/// only writing.
enum CommunityPrivacy { public, private }

enum MemberRole { member, moderator, owner }

/// What a community is for. Broad on purpose — a directory of forty
/// near-identical categories is a directory nobody reads.
enum CommunityCategory {
  regional,
  everyday,
  baking,
  occasions,
  health,
  budget,
  beginners,
  other,
}

class Community {
  const Community({
    required this.id,
    required this.name,
    required this.createdBy,
    this.description,
    this.coverUrl,
    this.category = CommunityCategory.other,
    this.region,
    this.privacy = CommunityPrivacy.public,
    this.joinPolicy = JoinPolicy.open,
    this.rules = const [],
    this.moderators = const [],
    this.memberCount = 0,
    this.postCount = 0,
    this.createdAt,
  });

  final String id;
  final String name;
  final String? description;
  final String? coverUrl;
  final CommunityCategory category;

  /// Optional: "Baghdad kitchens" is a real community, "Iraqi food" is not
  /// regional at all.
  final String? region;

  final CommunityPrivacy privacy;
  final JoinPolicy joinPolicy;

  /// Shown on join rather than buried. Someone who has read the rules and
  /// broken them is a different problem from someone who never saw them.
  final List<String> rules;

  final List<String> moderators;
  final String createdBy;
  final int memberCount;
  final int postCount;
  final DateTime? createdAt;

  bool get isPrivate => privacy == CommunityPrivacy.private;
  bool get needsApproval => joinPolicy == JoinPolicy.approval;

  bool moderatedBy(String? uid) =>
      uid != null && (uid == createdBy || moderators.contains(uid));

  factory Community.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Community(
      id: doc.id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String?,
      coverUrl: data['coverUrl'] as String?,
      category: CommunityCategory.values.firstWhere(
        (c) => c.name == data['category'],
        orElse: () => CommunityCategory.other,
      ),
      region: data['region'] as String?,
      privacy: CommunityPrivacy.values.firstWhere(
        (p) => p.name == data['privacy'],
        orElse: () => CommunityPrivacy.public,
      ),
      joinPolicy: JoinPolicy.values.firstWhere(
        (j) => j.name == data['joinPolicy'],
        orElse: () => JoinPolicy.open,
      ),
      rules: (data['rules'] as List?)?.cast<String>() ?? const [],
      moderators: (data['moderators'] as List?)?.cast<String>() ?? const [],
      createdBy: data['createdBy'] as String? ?? '',
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
      postCount: (data['postCount'] as num?)?.toInt() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// `memberCount` and `postCount` are absent: Function-owned, like every
  /// other counter, and the rules reject a client that writes them.
  Map<String, dynamic> toMap() => {
    'name': name.trim(),
    if (description != null) 'description': description!.trim(),
    if (coverUrl != null) 'coverUrl': coverUrl,
    'category': category.name,
    if (region != null) 'region': region,
    'privacy': privacy.name,
    'joinPolicy': joinPolicy.name,
    'rules': rules,
    'moderators': moderators,
    'createdBy': createdBy,
    'searchName': name.trim().toLowerCase(),
  };

  Community copyWith({
    String? name,
    String? description,
    String? coverUrl,
    CommunityCategory? category,
    String? region,
    CommunityPrivacy? privacy,
    JoinPolicy? joinPolicy,
    List<String>? rules,
  }) => Community(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    coverUrl: coverUrl ?? this.coverUrl,
    category: category ?? this.category,
    region: region ?? this.region,
    privacy: privacy ?? this.privacy,
    joinPolicy: joinPolicy ?? this.joinPolicy,
    rules: rules ?? this.rules,
    moderators: moderators,
    createdBy: createdBy,
    memberCount: memberCount,
    postCount: postCount,
    createdAt: createdAt,
  );
}

/// What kind of thing a post is.
///
/// Question is separate from text because a question wants an answer and the
/// UI should say so — "no replies yet" reads differently from "no comments".
enum PostType { text, photo, recipe, question }

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.author,
    required this.type,
    required this.body,
    this.mediaUrl,
    this.recipeId,
    this.pinned = false,
    this.commentCount = 0,
    this.createdAt,
  });

  final String id;
  final AuthorStub author;
  final PostType type;
  final String body;
  final String? mediaUrl;
  final String? recipeId;
  final bool pinned;
  final int commentCount;
  final DateTime? createdAt;

  factory CommunityPost.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return CommunityPost(
      id: doc.id,
      author: AuthorStub.fromMap(
        Map<String, dynamic>.from(data['author'] as Map? ?? const {}),
      ),
      type: PostType.values.firstWhere(
        (t) => t.name == data['type'],
        orElse: () => PostType.text,
      ),
      body: data['body'] as String? ?? '',
      mediaUrl: data['mediaUrl'] as String?,
      recipeId: data['recipeId'] as String?,
      pinned: data['pinned'] as bool? ?? false,
      commentCount: (data['commentCount'] as num?)?.toInt() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'author': author.toMap(),
    'type': type.name,
    'body': body.trim(),
    if (mediaUrl != null) 'mediaUrl': mediaUrl,
    if (recipeId != null) 'recipeId': recipeId,
    'pinned': pinned,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

class CommunityMember {
  const CommunityMember({
    required this.uid,
    required this.author,
    required this.role,
    this.joinedAt,
  });

  final String uid;

  /// Denormalised so a hundred-row member list is one query rather than one
  /// query plus a hundred profile reads. It goes stale when someone renames
  /// themselves, which is the trade every author stub in this app makes.
  final AuthorStub author;

  /// A label, not an authority. Every permission check reads the community
  /// document's `createdBy` and `moderators` instead — one source of truth
  /// means a forged role here buys nothing.
  final MemberRole role;

  final DateTime? joinedAt;

  bool get isStaff => role != MemberRole.member;

  factory CommunityMember.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return CommunityMember(
      uid: doc.id,
      author: AuthorStub.fromMap(
        Map<String, dynamic>.from(data['author'] as Map? ?? const {}),
      ),
      role: MemberRole.values.firstWhere(
        (r) => r.name == data['role'],
        orElse: () => MemberRole.member,
      ),
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Someone waiting at the door of an approval-gated community.
///
/// Carries the full author stub rather than just a uid so the moderator queue
/// renders without a fan-out of profile reads — and so approving still works
/// when the requester has since made their profile undiscoverable.
class CommunityJoinRequest {
  const CommunityJoinRequest({
    required this.uid,
    required this.author,
    this.requestedAt,
  });

  final String uid;
  final AuthorStub author;
  final DateTime? requestedAt;

  factory CommunityJoinRequest.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return CommunityJoinRequest(
      uid: doc.id,
      author: AuthorStub.fromMap(
        Map<String, dynamic>.from(data['author'] as Map? ?? const {}),
      ),
      requestedAt: (data['requestedAt'] as Timestamp?)?.toDate(),
    );
  }
}
