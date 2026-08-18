import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';

/// What a signed-in person is allowed to moderate.
///
/// Read from the Auth token rather than the user document, because the token is
/// what security rules and the callables actually trust. A user document field
/// could be stale or, in principle, wrong.
class AdminClaims {
  const AdminClaims({
    this.admin = false,
    this.moderator = false,
    this.verified = false,
  });

  final bool admin;
  final bool moderator;

  /// The verified tick *as this device's token sees it*.
  ///
  /// Deliberately not read from the profile document. The two disagree for as
  /// long as it takes an ID token to be reissued after the claim changes, and
  /// during that window the rules trust the token — so anything the client
  /// stamps from the document gets rejected.
  final bool verified;

  /// Moderators run the queues; admins can also promote other moderators.
  bool get canModerate => admin || moderator;

  static const none = AdminClaims();
}

class VerificationRequest {
  const VerificationRequest({
    required this.uid,
    required this.note,
    required this.status,
    this.requestedAt,
    this.profile,
  });

  final String uid;
  final String note;
  final String status;
  final DateTime? requestedAt;
  final UserProfile? profile;

  bool get isPending => status == 'pending';
}

class ModerationReport {
  const ModerationReport({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.status,
    this.reporterId,
    this.createdAt,
  });

  final String id;
  final String targetType;
  final String targetId;
  final String reason;
  final String status;
  final String? reporterId;
  final DateTime? createdAt;

  factory ModerationReport.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return ModerationReport(
      id: doc.id,
      targetType: data['targetType'] as String? ?? '',
      targetId: data['targetId'] as String? ?? '',
      reason: data['reason'] as String? ?? '',
      status: data['status'] as String? ?? 'open',
      reporterId: data['reporterId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class AdminRepository {
  AdminRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       // Callables are region-pinned: calling the default region would 404
       // against functions deployed next to Firestore.
       _functions = functions ?? FirebaseFunctions.instanceFor(region: 'me-central1');

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  /// [refresh] forces a token round trip. Needed right after a claim changes,
  /// since claims only reach the client when the ID token is reissued.
  Future<AdminClaims> claims({bool refresh = false}) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return AdminClaims.none;

    final token = await user.getIdTokenResult(refresh);
    return AdminClaims(
      admin: token.claims?['admin'] == true,
      moderator: token.claims?['moderator'] == true,
      verified: token.claims?['verified'] == true,
    );
  }

  // --- verification queue --------------------------------------------------

  Stream<List<VerificationRequest>> watchVerificationRequests() {
    return _firestore
        .collection('verificationRequests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .asyncMap((snapshot) async {
          // The request document holds only the applicant's own words; the
          // profile is what a reviewer actually judges, so fetch both.
          final profiles = await Future.wait(
            snapshot.docs.map((doc) => _firestore.doc('users/${doc.id}').get()),
          );

          return [
            for (var i = 0; i < snapshot.docs.length; i++)
              VerificationRequest(
                uid: snapshot.docs[i].id,
                note: snapshot.docs[i].data()['note'] as String? ?? '',
                status: snapshot.docs[i].data()['status'] as String? ?? 'pending',
                requestedAt:
                    (snapshot.docs[i].data()['at'] as Timestamp?)?.toDate(),
                profile: profiles[i].exists
                    ? UserProfile.fromDoc(profiles[i])
                    : null,
              ),
          ];
        });
  }

  /// Grants or revokes the mark.
  ///
  /// Goes through the callable rather than writing Firestore directly: the
  /// custom claim, the user field, and every denormalised `author.verified`
  /// copy have to move together, and only the server can touch the claim.
  Future<void> setVerified({required String uid, required bool verified}) async {
    await _functions.httpsCallable('setVerified').call({
      'uid': uid,
      'verified': verified,
    });
    await _firestore.doc('verificationRequests/$uid').set({
      'status': verified ? 'approved' : 'rejected',
      'decidedAt': FieldValue.serverTimestamp(),
      'reviewedBy': _auth.currentUser?.uid,
    }, SetOptions(merge: true));
  }

  Future<void> declineVerification(String uid) {
    return _firestore.doc('verificationRequests/$uid').set({
      'status': 'rejected',
      'decidedAt': FieldValue.serverTimestamp(),
      'reviewedBy': _auth.currentUser?.uid,
    }, SetOptions(merge: true));
  }

  Future<void> setModerator({required String uid, required bool moderator}) {
    return _functions.httpsCallable('setModerator').call({
      'uid': uid,
      'moderator': moderator,
    });
  }

  // --- reports -------------------------------------------------------------

  Stream<List<ModerationReport>> watchOpenReports() {
    return _firestore
        .collection('reports')
        .where('status', isEqualTo: 'open')
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map(ModerationReport.fromDoc).toList());
  }

  Future<void> resolveReport({
    required String reportId,
    required String outcome,
  }) {
    return _firestore.doc('reports/$reportId').set({
      'status': outcome,
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': _auth.currentUser?.uid,
    }, SetOptions(merge: true));
  }

  /// Hides content without deleting it. Removal is the author's to make, or a
  /// deliberate second decision — hiding is reversible and buys time.
  Future<void> hideContent({
    required String targetType,
    required String targetId,
  }) {
    final collection = targetType == 'plan' ? 'plans' : 'recipes';
    return _firestore.doc('$collection/$targetId').set({
      'status': 'hidden',
    }, SetOptions(merge: true));
  }

  // --- user lookup ---------------------------------------------------------

  Future<UserProfile?> findByHandle(String handle) async {
    final normalized = handle.trim().toLowerCase().replaceAll('@', '');
    final doc = await _firestore.doc('handles/$normalized').get();
    final uid = doc.data()?['uid'] as String?;
    if (uid == null) return null;

    final profile = await _firestore.doc('users/$uid').get();
    return profile.exists ? UserProfile.fromDoc(profile) : null;
  }
}
