import 'package:brnj/app/app.dart';
import 'package:brnj/app/settings.dart';
import 'package:brnj/features/shell/route_not_found_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// go_router falls back to a "Page Not Found" screen for any location it can't
/// match, and because the shell builds every branch up front, one bad branch
/// path shows up as a layout overflow on launch rather than as a routing error.
/// These tests assert the fallback never renders.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const BrnjApp(),
      ),
    );
    await tester.pump();
  }

  testWidgets('every shell branch resolves on launch', (tester) async {
    await pumpApp(tester);
    expect(
      // skipOffstage: false matters — the shell keeps unselected branches in
      // the tree but offstage, so a broken branch is invisible to the default
      // finder while still throwing layout errors on launch.
      find.text('Page Not Found', skipOffstage: false),
      findsNothing,
      reason: 'a branch location does not match any route',
    );
  });

  testWidgets('an unmatched location renders the app error screen, not go_router\'s',
      (tester) async {
    // iPhone 17 logical size — the overflow this replaces only appeared at
    // phone height, which is why an 800x600 test surface missed it.
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester);
    final context = tester.element(find.byType(Navigator).first);
    GoRouter.of(context).go('/definitely-not-a-route');
    await tester.pumpAndSettle();

    expect(find.byType(RouteNotFoundScreen), findsOneWidget);
    expect(find.text('Page Not Found', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull, reason: 'the screen must not overflow');
  });

  testWidgets('every named sub-route resolves', (tester) async {
    await pumpApp(tester);
    final context = tester.element(find.byType(Navigator).first);

    // These are reachable only by tapping through the profile, so a typo in a
    // path would otherwise surface as a "Page Not Found" in someone's hands.
    for (final location in [
      '/me',
      '/me/week',
      '/me/edit',
      '/me/settings',
      '/me/verification',
      '/plan/some_2026-08-15',
      '/me/recipes',
      '/me/saved',
      '/shopping/some_2026-08-15',
      '/create/recipe',
      '/create/recipe/abc123',
      '/recipe/abc123',
      '/admin',
      '/search',
      '/cook/abc123',
      '/notifications',
      '/user/someuid',
    ]) {
      GoRouter.of(context).go(location);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(RouteNotFoundScreen),
        findsNothing,
        reason: '$location did not resolve',
      );
    }
  });

  testWidgets('a Firebase Auth callback URL is swallowed, not routed', (tester) async {
    // Completing a phone sign-in returns through the app's reversed-client-id
    // scheme. Flutter forwards it to the router, which has no route for it —
    // so the person landed on "This page isn't here" on top of a sign-in that
    // had actually worked.
    await pumpApp(tester);
    final context = tester.element(find.byType(Navigator).first);

    GoRouter.of(context).go(
      'com.googleusercontent.apps.24550424690-abc://firebaseauth/link'
      '?deep_link_id=https%3A%2F%2Fbrnj.firebaseapp.com',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(RouteNotFoundScreen), findsNothing);
  });

  testWidgets('each destination navigates without falling through', (tester) async {
    await pumpApp(tester);

    for (final label in ['Communities', 'Chats', 'Me', 'Home']) {
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        // skipOffstage: false matters — the shell keeps unselected branches in
      // the tree but offstage, so a broken branch is invisible to the default
      // finder while still throwing layout errors on launch.
      find.text('Page Not Found', skipOffstage: false),
        findsNothing,
        reason: 'tapping $label fell through to the error screen',
      );
    }
  });
}
