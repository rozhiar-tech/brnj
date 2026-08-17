import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_profile.dart';

/// Someone's own attempt at a recipe.
///
/// The strongest signal in the app: a save is intent, cooking it is proof. The
/// author stub is denormalised because the gallery renders a name and face per
/// entry, and a lookup per entry would make the cheapest contribution in the
/// app the most expensive thing to display.
class CookedPost {
  const CookedPost({
    required this.uid,
    required this.author,
    this.photoUrl,
    this.note,
    this.at,
  });

  final String uid;
  final AuthorStub author;
  final String? photoUrl;
  final String? note;
  final DateTime? at;

  bool get hasPhoto => photoUrl != null;

  factory CookedPost.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return CookedPost(
      uid: doc.id,
      author: AuthorStub.fromMap(
        Map<String, dynamic>.from(data['author'] as Map? ?? const {}),
      ),
      photoUrl: data['photoUrl'] as String?,
      note: data['note'] as String?,
      at: (data['at'] as Timestamp?)?.toDate(),
    );
  }
}

class Comment {
  const Comment({
    required this.id,
    required this.author,
    required this.text,
    this.at,
    this.replyToUid,
  });

  final String id;
  final AuthorStub author;
  final String text;
  final DateTime? at;

  /// Set when this is a reply. Kept flat rather than nested: threads under a
  /// recipe are short, and a nesting level nobody needs costs a lot of layout.
  final String? replyToUid;

  factory Comment.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Comment(
      id: doc.id,
      author: AuthorStub.fromMap(
        Map<String, dynamic>.from(data['author'] as Map? ?? const {}),
      ),
      text: data['text'] as String? ?? '',
      at: (data['createdAt'] as Timestamp?)?.toDate(),
      replyToUid: data['replyToUid'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'author': author.toMap(),
    'text': text.trim(),
    if (replyToUid != null) 'replyToUid': replyToUid,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

enum NotificationType { like, cooked, comment, follow, planCopied, unknown }

/// Written by Cloud Functions, never by a client.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.actorUid,
    required this.read,
    this.actorName,
    this.targetId,
    this.body,
    this.at,
  });

  final String id;
  final NotificationType type;
  final String actorUid;
  final String? actorName;
  final String? targetId;
  final String? body;
  final bool read;
  final DateTime? at;

  factory AppNotification.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return AppNotification(
      id: doc.id,
      type: NotificationType.values.firstWhere(
        (t) => t.name == data['type'],
        orElse: () => NotificationType.unknown,
      ),
      actorUid: data['actorUid'] as String? ?? '',
      actorName: data['actorName'] as String?,
      targetId: data['targetId'] as String?,
      body: data['body'] as String?,
      read: data['read'] as bool? ?? false,
      at: (data['at'] as Timestamp?)?.toDate(),
    );
  }

  /// Where tapping it should land. A notification that opens nothing is worse
  /// than no notification.
  String? get route => switch (type) {
    NotificationType.like ||
    NotificationType.cooked ||
    NotificationType.comment => targetId == null ? null : '/recipe/$targetId',
    NotificationType.planCopied => targetId == null ? null : '/plan/$targetId',
    NotificationType.follow => targetId == null ? null : '/user/$targetId',
    NotificationType.unknown => null,
  };
}
