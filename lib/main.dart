import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load preferences before the first frame so the app never renders in the
  // wrong language and then flips.
  final prefs = await SharedPreferences.getInstance();

  await initializeFirebase();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const BrnjApp(),
    ),
  );
}
