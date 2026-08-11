import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/settings.dart';
import 'data/repositories/auth_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load preferences before the first frame so the app never renders in the
  // wrong language and then flips.
  final prefs = await SharedPreferences.getInstance();

  final status = await initializeFirebase();

  // Sign every visitor in anonymously before the first frame. Nobody sees a
  // login wall; security rules always have a uid; and when someone eventually
  // registers, linkWithCredential upgrades this same uid so their saves,
  // settings, and half-finished plan survive the transition.
  if (status == FirebaseStatus.ready) {
    await AuthRepository().ensureSignedIn();
  }

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const BrnjApp(),
    ),
  );
}
