import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Push registration.
///
/// A client cannot send FCM — that needs a private key, and a private key in a
/// Flutter app is a public key. So the client's only job is to keep its token
/// on the user document where a Function can find it.
///
/// Tokens are stored one per document rather than in an array: they rotate, an
/// account can be on several devices, and a stale token has to be removable
/// individually when the send fails.
class MessagingRepository {
  MessagingRepository({FirebaseMessaging? messaging, FirebaseFirestore? firestore})
    : _messaging = messaging ?? FirebaseMessaging.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  /// Asks for permission and stores the token.
  ///
  /// Deliberately not called at launch. A permission prompt before anyone has
  /// seen the app is the fastest way to a permanent "no" — this runs after the
  /// person does something that would produce a notification worth having.
  Future<void> register(String uid) async {
    try {
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // On iOS the FCM token is only available once APNs has issued one, and
      // the simulator never does. Nothing to store there, and nothing broken.
      final token = await _messaging.getToken();
      if (token == null) return;

      await _store(uid, token);
      _messaging.onTokenRefresh.listen((fresh) => _store(uid, fresh));
    } catch (error) {
      debugPrint('Push registration skipped: $error');
    }
  }

  Future<void> _store(String uid, String token) {
    return _firestore.doc('users/$uid/tokens/$token').set({
      'platform': defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Called on sign-out so the next person on this device doesn't inherit
  /// someone else's notifications.
  Future<void> unregister(String uid) async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      await _firestore.doc('users/$uid/tokens/$token').delete();
      await _messaging.deleteToken();
    } catch (_) {
      // Nothing useful to do; the Function prunes tokens that fail to send.
    }
  }
}
