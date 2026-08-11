import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_profile.dart';

/// Why sign-in failed, in terms the UI can show a person.
enum AuthFailure {
  cancelled,
  invalidCode,
  codeExpired,
  tooManyRequests,
  network,
  accountExists,
  unknown,
}

class AuthException implements Exception {
  const AuthException(this.failure, [this.raw]);
  final AuthFailure failure;
  final Object? raw;

  @override
  String toString() => 'AuthException($failure): $raw';
}

/// Authentication, built around one rule: **nobody ever sees a login wall.**
///
/// Every visitor is signed in anonymously on first launch, which means:
///   • security rules always have a `request.auth.uid` to work with
///   • App Check protects reads made by people who haven't registered
///   • when someone finally registers, [linkWithCredential] upgrades the
///     *same* uid, so their saves, settings, and half-finished plan survive
///
/// That last point is the whole reason for this design. Creating a fresh
/// account at sign-up instead would wipe everything the person did, at exactly
/// the moment you're asking them to commit.
class AuthRepository {
  AuthRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  bool _googleInitialised = false;

  User? get currentUser => _auth.currentUser;

  String? get uid => _auth.currentUser?.uid;

  bool get isGuest => _auth.currentUser?.isAnonymous ?? true;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Called once at startup. Signs in anonymously if there's no session at all.
  ///
  /// Failure is not fatal: a person with no connection should still get the
  /// cached feed rather than a broken app.
  Future<User?> ensureSignedIn() async {
    if (_auth.currentUser != null) return _auth.currentUser;
    try {
      final credential = await _auth.signInAnonymously();
      return credential.user;
    } on FirebaseAuthException catch (error) {
      debugPrint('Anonymous sign-in failed: ${error.code}');
      return null;
    }
  }

  // --- phone ---------------------------------------------------------------

  /// Starts phone verification and returns the verification id to pair with
  /// the code the user types.
  ///
  /// Android may verify instantly without a code (Play Services recognises the
  /// SIM); [onAutoVerified] fires in that case and no code screen is needed.
  Future<String> startPhoneVerification({
    required String phoneNumber,
    required void Function(UserCredential credential) onAutoVerified,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final completer = Completer<String>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: timeout,
      verificationCompleted: (credential) async {
        try {
          onAutoVerified(await _signInOrLink(credential));
        } catch (error) {
          debugPrint('Auto-verification failed: $error');
        }
      },
      verificationFailed: (error) {
        if (!completer.isCompleted) {
          completer.completeError(AuthException(_mapCode(error.code), error));
        }
      },
      codeSent: (verificationId, _) {
        if (!completer.isCompleted) completer.complete(verificationId);
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (!completer.isCompleted) completer.complete(verificationId);
      },
    );

    return completer.future;
  }

  Future<UserCredential> confirmPhoneCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return _signInOrLink(credential);
  }

  // --- google --------------------------------------------------------------

  Future<UserCredential> signInWithGoogle() async {
    // The web build uses Firebase's own popup: google_sign_in on web is a
    // render-a-button flow, not a call you can await from a tap handler.
    if (kIsWeb) {
      try {
        return await _auth.signInWithPopup(GoogleAuthProvider());
      } on FirebaseAuthException catch (error) {
        throw AuthException(_mapCode(error.code), error);
      }
    }

    if (!_googleInitialised) {
      // Client ids come from google-services.json and GoogleService-Info.plist,
      // so there is nothing to pass here.
      await GoogleSignIn.instance.initialize();
      _googleInitialised = true;
    }

    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AuthException(AuthFailure.unknown, 'No ID token from Google');
      }
      return _signInOrLink(GoogleAuthProvider.credential(idToken: idToken));
    } on GoogleSignInException catch (error) {
      throw AuthException(
        error.code == GoogleSignInExceptionCode.canceled
            ? AuthFailure.cancelled
            : AuthFailure.unknown,
        error,
      );
    }
  }

  // --- the important bit ---------------------------------------------------

  /// Upgrades the anonymous account in place where possible, so the person
  /// keeps their uid and everything attached to it.
  ///
  /// If the credential already belongs to a different account — they signed up
  /// on another device — linking fails and we sign into that existing account
  /// instead. The anonymous uid is abandoned in that case, which is the
  /// unavoidable cost of them already having a real account.
  Future<UserCredential> _signInOrLink(AuthCredential credential) async {
    final user = _auth.currentUser;

    if (user != null && user.isAnonymous) {
      try {
        final result = await user.linkWithCredential(credential);
        await _ensureProfile(result.user!);
        return result;
      } on FirebaseAuthException catch (error) {
        const alreadyRegistered = {
          'credential-already-in-use',
          'email-already-in-use',
          'provider-already-linked',
        };
        if (!alreadyRegistered.contains(error.code)) {
          throw AuthException(_mapCode(error.code), error);
        }
        // Fall through to a plain sign-in against the existing account.
      }
    }

    try {
      final result = await _auth.signInWithCredential(credential);
      await _ensureProfile(result.user!);
      return result;
    } on FirebaseAuthException catch (error) {
      throw AuthException(_mapCode(error.code), error);
    }
  }

  /// Creates the profile document on first registration. Never overwrites an
  /// existing one — a returning user keeps the name and photo they chose.
  ///
  /// Note what isn't written: `verified`, `tier`, and `counts` are all
  /// Function-owned, and the security rules reject a client that touches them.
  Future<void> _ensureProfile(User user) async {
    final doc = _firestore.collection('users').doc(user.uid);
    final snapshot = await doc.get();
    if (snapshot.exists) return;

    final profile = UserProfile(
      uid: user.uid,
      displayName: user.displayName?.trim().isNotEmpty ?? false
          ? user.displayName!.trim()
          : _defaultName(user),
      photoUrl: user.photoURL,
    );

    await doc.set(profile.toCreateMap());
  }

  /// Pseudonyms are normal here, not a fallback — a large share of users will
  /// not post under a real name, and the default shouldn't push them to.
  String _defaultName(User user) {
    final phone = user.phoneNumber;
    if (phone != null && phone.length >= 4) {
      return 'طباخ ${phone.substring(phone.length - 4)}';
    }
    return 'طباخ ${user.uid.substring(0, 4)}';
  }

  Future<void> signOut() async {
    if (!kIsWeb && _googleInitialised) {
      await GoogleSignIn.instance.signOut();
    }
    await _auth.signOut();
    // Straight back to a guest session rather than a signed-out dead end.
    await ensureSignedIn();
  }

  /// Store policy requires in-app account deletion. The Auth `onDelete`
  /// Function purges the user's content, plans, and viewer records.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.delete();
    } on FirebaseAuthException catch (error) {
      throw AuthException(_mapCode(error.code), error);
    }
    await ensureSignedIn();
  }

  AuthFailure _mapCode(String code) => switch (code) {
    'invalid-verification-code' || 'invalid-code' => AuthFailure.invalidCode,
    'session-expired' || 'code-expired' => AuthFailure.codeExpired,
    'too-many-requests' || 'quota-exceeded' => AuthFailure.tooManyRequests,
    'network-request-failed' => AuthFailure.network,
    'credential-already-in-use' ||
    'account-exists-with-different-credential' => AuthFailure.accountExists,
    'web-context-cancelled' || 'user-cancelled' => AuthFailure.cancelled,
    _ => AuthFailure.unknown,
  };
}
