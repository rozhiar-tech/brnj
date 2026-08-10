import 'package:cloud_firestore/cloud_firestore.dart';

/// What a user is allowed to do. Guests are real Firebase users (anonymous
/// auth) so security rules always have a uid to work with — they just can't
/// write anything social.
enum UserTier { guest, registered, verified }

/// Who may start a conversation with this user. Default is [following]: a
/// message from a stranger lands in the Requests inbox instead of the chat
/// list, with photos hidden until accepted.
enum DmMode { everyone, following, none }

class UserPrivacy {
  const UserPrivacy({
    this.dmMode = DmMode.following,
    this.discoverable = true,
    this.showRealName = false,
    this.incognito = false,
  });

  final DmMode dmMode;
  final bool discoverable;
  final bool showRealName;

  /// Opt out of appearing in anyone's viewer list. Counts still increment.
  final bool incognito;

  factory UserPrivacy.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const UserPrivacy();
    return UserPrivacy(
      dmMode: DmMode.values.firstWhere(
        (m) => m.name == map['dmMode'],
        orElse: () => DmMode.following,
      ),
      discoverable: map['discoverable'] as bool? ?? true,
      showRealName: map['showRealName'] as bool? ?? false,
      incognito: map['incognito'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'dmMode': dmMode.name,
    'discoverable': discoverable,
    'showRealName': showRealName,
    'incognito': incognito,
  };
}

class UserCounts {
  const UserCounts({
    this.recipes = 0,
    this.plans = 0,
    this.followers = 0,
    this.following = 0,
  });

  final int recipes;
  final int plans;
  final int followers;
  final int following;

  factory UserCounts.fromMap(Map<String, dynamic>? map) => UserCounts(
    recipes: (map?['recipes'] as num?)?.toInt() ?? 0,
    plans: (map?['plans'] as num?)?.toInt() ?? 0,
    followers: (map?['followers'] as num?)?.toInt() ?? 0,
    following: (map?['following'] as num?)?.toInt() ?? 0,
  );
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    this.handle,
    this.photoUrl,
    this.bio,
    this.city,
    this.contentLanguages = const ['ar'],
    this.verified = false,
    this.tier = UserTier.registered,
    this.privacy = const UserPrivacy(),
    this.counts = const UserCounts(),
    this.createdAt,
    this.lastActiveAt,
  });

  final String uid;
  final String displayName;
  final String? handle;
  final String? photoUrl;
  final String? bio;
  final String? city;
  final List<String> contentLanguages;

  /// Mirrors the `verified` custom claim on the Auth token. This copy exists so
  /// clients can render the tick and rank on it without reading the token;
  /// the claim is what security rules actually trust. Both are written only by
  /// an admin Function — never from a client.
  final bool verified;

  final UserTier tier;
  final UserPrivacy privacy;
  final UserCounts counts;
  final DateTime? createdAt;
  final DateTime? lastActiveAt;

  bool get isGuest => tier == UserTier.guest;

  /// The subset denormalised onto every recipe, post, and plan so a feed card
  /// costs zero extra reads. Backfilled by a Function when a user's name,
  /// photo, or verified status changes.
  Map<String, dynamic> get authorStub => {
    'uid': uid,
    'name': displayName,
    if (photoUrl != null) 'photoUrl': photoUrl,
    'verified': verified,
  };

  factory UserProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return UserProfile(
      uid: doc.id,
      displayName: data['displayName'] as String? ?? '',
      handle: data['handle'] as String?,
      photoUrl: data['photoUrl'] as String?,
      bio: data['bio'] as String?,
      city: data['city'] as String?,
      contentLanguages:
          (data['contentLanguages'] as List?)?.cast<String>() ?? const ['ar'],
      verified: data['verified'] as bool? ?? false,
      tier: UserTier.values.firstWhere(
        (t) => t.name == data['tier'],
        orElse: () => UserTier.registered,
      ),
      privacy: UserPrivacy.fromMap(data['privacy'] as Map<String, dynamic>?),
      counts: UserCounts.fromMap(data['counts'] as Map<String, dynamic>?),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      lastActiveAt: (data['lastActiveAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Note what is absent: `verified`, `tier`, and `counts` are never written
  /// from the client. Security rules reject a write that touches them.
  Map<String, dynamic> toCreateMap() => {
    'displayName': displayName,
    if (handle != null) 'handle': handle,
    if (photoUrl != null) 'photoUrl': photoUrl,
    if (bio != null) 'bio': bio,
    if (city != null) 'city': city,
    'contentLanguages': contentLanguages,
    'privacy': privacy.toMap(),
    'createdAt': FieldValue.serverTimestamp(),
    'lastActiveAt': FieldValue.serverTimestamp(),
  };

  UserProfile copyWith({
    String? displayName,
    String? handle,
    String? photoUrl,
    String? bio,
    String? city,
    List<String>? contentLanguages,
    UserPrivacy? privacy,
  }) => UserProfile(
    uid: uid,
    displayName: displayName ?? this.displayName,
    handle: handle ?? this.handle,
    photoUrl: photoUrl ?? this.photoUrl,
    bio: bio ?? this.bio,
    city: city ?? this.city,
    contentLanguages: contentLanguages ?? this.contentLanguages,
    verified: verified,
    tier: tier,
    privacy: privacy ?? this.privacy,
    counts: counts,
    createdAt: createdAt,
    lastActiveAt: lastActiveAt,
  );
}

/// The denormalised author copy carried by recipes, plans, and posts.
class AuthorStub {
  const AuthorStub({
    required this.uid,
    required this.name,
    this.photoUrl,
    this.verified = false,
  });

  final String uid;
  final String name;
  final String? photoUrl;
  final bool verified;

  factory AuthorStub.fromMap(Map<String, dynamic> map) => AuthorStub(
    uid: map['uid'] as String? ?? '',
    name: map['name'] as String? ?? '',
    photoUrl: map['photoUrl'] as String?,
    verified: map['verified'] as bool? ?? false,
  );

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'name': name,
    if (photoUrl != null) 'photoUrl': photoUrl,
    'verified': verified,
  };
}
