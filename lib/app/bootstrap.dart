import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase_options.dart';

enum FirebaseStatus {
  /// Connected. Everything works.
  ready,

  /// No `firebase_options.dart` / `google-services.json` yet. The app still
  /// runs so UI work isn't blocked on someone having project access.
  notConfigured,

  /// Configured but the connection failed.
  failed,
}

/// Set during [initializeFirebase] and read by the providers below.
FirebaseStatus firebaseStatus = FirebaseStatus.notConfigured;

Future<FirebaseStatus> initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await _activateAppCheck();

    // Offline persistence is the difference between "saved recipes work on the
    // bus" and "the app is useless on 3G". On by default for mobile, but set
    // an explicit cache ceiling so a heavy user doesn't fill their storage.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 100 * 1024 * 1024, // 100 MB
    );

    firebaseStatus = FirebaseStatus.ready;
  } on UnsupportedError {
    // No platform options — flutterfire configure hasn't been run.
    firebaseStatus = FirebaseStatus.notConfigured;
  } catch (error, stack) {
    debugPrint('Firebase init failed: $error\n$stack');
    firebaseStatus = FirebaseStatus.failed;
  }

  if (kDebugMode) {
    debugPrint('Firebase: ${firebaseStatus.name}');
  }
  return firebaseStatus;
}

/// App Check attests that a request came from *your* app, not from a script
/// with your API key. It is what stops someone scraping the recipe corpus or
/// burning your SMS budget — phone-auth pumping fraud specifically targets
/// Middle East number ranges, and every verification you pay for is real money.
///
/// Failures here are deliberately not fatal. A missing fingerprint or an
/// unregistered debug token should degrade to "unattested requests" during
/// development, not brick the app on launch.
Future<void> _activateAppCheck() async {
  // Web needs a reCAPTCHA Enterprise site key, which doesn't exist for this
  // project yet. Activating without one throws, so skip until the key exists —
  // there's no public web build to protect in the meantime.
  if (kIsWeb) return;

  try {
    await FirebaseAppCheck.instance.activate(
      // Debug builds use the debug provider: Play Integrity would reject a
      // locally-signed APK, and App Attest needs a real provisioning profile.
      // The token printed to the console on first run has to be pasted into
      // Firebase Console → App Check → Manage debug tokens.
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          // App Attest is stronger but needs iOS 14+; this falls back to
          // DeviceCheck on anything older rather than failing shut.
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  } catch (error) {
    debugPrint('App Check activation failed (continuing unattested): $error');
  }
}

final firebaseStatusProvider = Provider<FirebaseStatus>((ref) => firebaseStatus);

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);
