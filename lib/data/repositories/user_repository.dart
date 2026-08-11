import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../models/user_profile.dart';

enum HandleStatus { available, taken, invalid, unchanged }

class UserRepository {
  UserRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  /// Reserved handles, one document per handle, id = the lowercased handle.
  /// Uniqueness comes from the document id rather than from a query, so two
  /// people claiming the same name at the same moment can't both win.
  CollectionReference<Map<String, dynamic>> get _handles =>
      _firestore.collection('handles');

  Stream<UserProfile?> watchProfile(String uid) => _users
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists ? UserProfile.fromDoc(doc) : null);

  Future<UserProfile?> getProfile(String uid) async {
    final doc = await _users.doc(uid).get();
    return doc.exists ? UserProfile.fromDoc(doc) : null;
  }

  // --- editing -------------------------------------------------------------

  /// Writes only the fields a person can actually edit.
  ///
  /// `verified`, `tier`, and `counts` are absent deliberately — they are
  /// Function-owned and the security rules reject a client that touches them.
  Future<void> updateProfile({
    required String uid,
    String? displayName,
    String? bio,
    String? city,
    List<String>? contentLanguages,
    UserPrivacy? privacy,
  }) {
    return _users.doc(uid).set({
      if (displayName != null) 'displayName': displayName.trim(),
      // Empty strings clear the field rather than storing "".
      if (bio != null) 'bio': bio.trim().isEmpty ? FieldValue.delete() : bio.trim(),
      if (city != null)
        'city': city.trim().isEmpty ? FieldValue.delete() : city.trim(),
      if (contentLanguages != null) 'contentLanguages': contentLanguages,
      if (privacy != null) 'privacy': privacy.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // --- handles -------------------------------------------------------------

  static final _handlePattern = RegExp(r'^[a-z0-9_]{3,20}$');

  /// Latin-only, lowercase. Deliberately not Arabic or Kurdish script: a handle
  /// goes in a URL and gets typed by other people, and mixed-script handles are
  /// a well-known impersonation vector — the display name is where someone's
  /// real name in their own script belongs.
  static String normalizeHandle(String input) =>
      input.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');

  Future<HandleStatus> checkHandle(String handle, {String? currentHandle}) async {
    final normalized = normalizeHandle(handle);
    if (normalized == currentHandle) return HandleStatus.unchanged;
    if (!_handlePattern.hasMatch(normalized)) return HandleStatus.invalid;

    final doc = await _handles.doc(normalized).get();
    return doc.exists ? HandleStatus.taken : HandleStatus.available;
  }

  /// Claims [handle] for [uid] and releases whatever they held before.
  ///
  /// The reservation document is created inside a transaction so that a
  /// simultaneous claim by someone else fails rather than silently overwriting.
  Future<HandleStatus> claimHandle({
    required String uid,
    required String handle,
    String? currentHandle,
  }) async {
    final normalized = normalizeHandle(handle);
    if (normalized == currentHandle) return HandleStatus.unchanged;
    if (!_handlePattern.hasMatch(normalized)) return HandleStatus.invalid;

    try {
      await _firestore.runTransaction((tx) async {
        final ref = _handles.doc(normalized);
        final snapshot = await tx.get(ref);
        if (snapshot.exists) throw const _HandleTaken();

        tx.set(ref, {'uid': uid, 'at': FieldValue.serverTimestamp()});
        tx.set(_users.doc(uid), {'handle': normalized}, SetOptions(merge: true));

        if (currentHandle != null && currentHandle.isNotEmpty) {
          tx.delete(_handles.doc(currentHandle));
        }
      });
      return HandleStatus.available;
    } on _HandleTaken {
      return HandleStatus.taken;
    }
  }

  // --- avatar --------------------------------------------------------------

  /// Compresses on the device before uploading. A camera photo is several
  /// megabytes; an avatar is never displayed above 96pt, so anything past
  /// 512px is bandwidth nobody sees — and bandwidth is the cost centre.
  Future<String> uploadAvatar({required String uid, required String filePath}) async {
    final compressed = await FlutterImageCompress.compressWithFile(
      filePath,
      minWidth: 512,
      minHeight: 512,
      quality: 85,
      format: CompressFormat.jpeg,
    );
    if (compressed == null) {
      throw StateError('Could not read the selected image');
    }

    final ref = _storage.ref('users/$uid/avatar/avatar.jpg');
    await ref.putData(
      Uint8List.fromList(compressed),
      SettableMetadata(
        contentType: 'image/jpeg',
        // Avatars are overwritten in place at a fixed path, so a long cache
        // life would serve the old face. An hour is long enough to help and
        // short enough to correct.
        cacheControl: 'public, max-age=3600',
      ),
    );

    final url = await ref.getDownloadURL();
    await _users.doc(uid).set({'photoUrl': url}, SetOptions(merge: true));
    return url;
  }

  Future<void> removeAvatar(String uid) async {
    await _users.doc(uid).set({
      'photoUrl': FieldValue.delete(),
    }, SetOptions(merge: true));
    try {
      await _storage.ref('users/$uid/avatar/avatar.jpg').delete();
    } on FirebaseException {
      // Already gone, or never uploaded. The profile field is what matters.
    }
  }

  // --- verification --------------------------------------------------------

  /// Applications are reviewed by a human. Nothing here grants anything —
  /// `verified` is set by an admin Function and the rules reject any client
  /// that writes it.
  Future<void> requestVerification({required String uid, required String note}) {
    return _firestore.collection('verificationRequests').doc(uid).set({
      'note': note.trim(),
      'status': 'pending',
      'at': FieldValue.serverTimestamp(),
    });
  }

  Stream<String?> watchVerificationStatus(String uid) => _firestore
      .collection('verificationRequests')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.data()?['status'] as String?);
}

class _HandleTaken implements Exception {
  const _HandleTaken();
}
