import 'package:cloud_firestore/cloud_firestore.dart';

/// Why something was reported. Deliberately short.
///
/// A long list makes people pick the closest wrong one and makes the queue
/// harder to triage. Free text carries the nuance.
enum ReportReason { harassment, spam, wrongOrStolen, inappropriate, other }

/// What is being reported.
///
/// `communityPost` files a report like any other but is not covered by the
/// auto-hide threshold in moderation.ts — that works on top-level collections,
/// and a community post already has a moderator standing next to it who can
/// remove it faster than a counter can.
enum ReportTarget { recipe, plan, comment, profile, communityPost }

/// Reporting and blocking.
///
/// The plan treats these as product requirements rather than settings, because
/// a community app in Iraq without them becomes unusable within months —
/// harassment in DMs and fights under a recipe drive people off, and the ones
/// who leave first are the ones the app most needs.
class SafetyRepository {
  SafetyRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// One report per person per target. The id is deterministic so a second
  /// tap edits the first rather than inflating the count — the auto-hide
  /// threshold is about distinct people, and this is what keeps it honest.
  Future<void> report({
    required String reporterId,
    required ReportTarget targetType,
    required String targetId,
    required ReportReason reason,
    String? note,
    String? targetOwner,
  }) {
    return _firestore.doc('reports/${targetId}_$reporterId').set({
      'targetType': targetType.name,
      'targetId': targetId,
      if (targetOwner != null) 'targetOwner': targetOwner,
      'reporterId': reporterId,
      'reason': reason.name,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Blocking is total: their content disappears from your feeds, and the
  /// rules stop them reading your profile.
  Future<void> setBlocked({
    required String uid,
    required String targetUid,
    required bool blocked,
  }) async {
    final doc = _firestore.doc('users/$uid/blocked/$targetUid');
    if (!blocked) {
      await doc.delete();
      return;
    }

    await doc.set({'at': FieldValue.serverTimestamp()});
    // Blocking someone you follow and staying subscribed to them would be a
    // strange half-measure, so the follow goes too.
    await _firestore
        .doc('users/$uid/following/$targetUid')
        .delete()
        .catchError((_) {});
  }

  Stream<List<String>> watchBlockedIds(String uid) => _firestore
      .collection('users/$uid/blocked')
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toList());

  Stream<bool> watchIsBlocked({required String uid, required String targetUid}) =>
      _firestore
          .doc('users/$uid/blocked/$targetUid')
          .snapshots()
          .map((d) => d.exists);
}
