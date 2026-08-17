import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/social.dart';

/// The in-app notification list.
///
/// Cloud Functions write these documents; nothing here creates one, and the
/// security rules reject a client that tries. Push is a courtesy on top —
/// this list is the durable record, and it is what a person opens when they
/// missed or dismissed the notification.
class NotificationRepository {
  NotificationRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _for(String uid) =>
      _firestore.collection('users/$uid/notifications');

  Stream<List<AppNotification>> watch(String uid, {int limit = 50}) => _for(uid)
      .orderBy('at', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(AppNotification.fromDoc).toList());

  /// Drives the dot on the bell. Counted rather than fetched so an unread
  /// badge doesn't cost fifty document reads on every app open.
  Stream<int> watchUnreadCount(String uid) => _for(uid)
      .where('read', isEqualTo: false)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.length);

  Future<void> markRead(String uid, String id) =>
      _for(uid).doc(id).set({'read': true}, SetOptions(merge: true));

  /// Marking everything read is one batch, not fifty writes — opening the
  /// screen should not cost more than reading it.
  Future<void> markAllRead(String uid) async {
    final unread = await _for(uid).where('read', isEqualTo: false).limit(400).get();
    if (unread.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in unread.docs) {
      batch.set(doc.reference, {'read': true}, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> delete(String uid, String id) => _for(uid).doc(id).delete();
}
