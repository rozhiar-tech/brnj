import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/plan/my_week_screen.dart';
import '../features/plan/plan_detail_screen.dart';
import '../features/plan/shopping_list_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/public_profile_screen.dart';
import '../features/profile/settings_screen.dart';
import '../features/admin/admin_screen.dart';
import '../features/profile/verification_screen.dart';
import '../features/recipe/composer/recipe_composer_screen.dart';
import '../features/recipe/cook_mode_screen.dart';
import '../features/recipe/my_recipes_screen.dart';
import '../features/recipe/recipe_detail_screen.dart';
import '../features/search/search_screen.dart';
import '../features/shell/placeholder_screen.dart';
import '../features/shell/route_not_found_screen.dart';
import '../features/shell/shell_screen.dart';
import '../l10n/gen/app_localizations.dart';

/// Named paths, in one place, so deep links and share cards stay consistent.
/// Recipe and plan routes are the two that get shared outward — mostly over
/// WhatsApp, which is the distribution channel that matters here.
abstract final class Routes {
  static const home = '/';
  static const communities = '/communities';
  static const chats = '/chats';
  static const me = '/me';

  static const recipe = '/recipe/:id';
  static const profile = '/user/:uid';

  static String recipeFor(String id) => '/recipe/$id';
  static String planFor(String id) => '/plan/$id';
  static String profileFor(String handle) => '/user/$handle';
}

final _rootKey = GlobalKey<NavigatorState>();

/// Swallows URLs that were never meant for the router.
///
/// Firebase Auth returns from reCAPTCHA and Google sign-in through the app's
/// own `com.googleusercontent.apps.…://firebaseauth/link?…` scheme. Firebase
/// consumes those itself; the router seeing them at all is an accident of
/// Flutter forwarding every incoming URL. Routing one produced a "This page
/// isn't here" screen on top of a sign-in that had actually succeeded.
///
/// The platform-side fix is `FlutterDeepLinkingEnabled=false` in Info.plist.
/// This is the belt to that pair of braces, and it also covers Android, where
/// the same callbacks arrive by a different path.
///
/// In-app navigation always produces a scheme-less URI, so anything carrying a
/// non-web scheme is by definition not ours.
String? _ignoreForeignSchemes(BuildContext context, GoRouterState state) {
  final scheme = state.uri.scheme;
  if (scheme.isEmpty || scheme == 'http' || scheme == 'https') return null;
  return Routes.home;
}

GoRouter createRouter() => GoRouter(
  navigatorKey: _rootKey,
  initialLocation: Routes.home,
  // go_router's default fallback is untranslated and overflows on a phone, so
  // a routing miss reports itself as a layout error instead of as a miss.
  errorBuilder: (context, state) =>
      RouteNotFoundScreen(uri: state.uri, error: state.error),

  redirect: _ignoreForeignSchemes,
  routes: [
    // The composer sits outside the shell: it is a full-screen task, and the
    // bottom bar has nothing to offer while you are writing a recipe. Pushed
    // rather than gone to, so back returns to wherever it was opened from.
    // Moderation, cook mode and search are all full-screen tasks with nothing
    // to gain from the bottom bar, so they sit outside the shell.
    GoRoute(
      path: '/admin',
      builder: (context, state) => const AdminScreen(),
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) => const SearchScreen(),
    ),
    GoRoute(
      path: '/shopping/:planId',
      builder: (context, state) =>
          ShoppingListScreen(planId: state.pathParameters['planId']!),
    ),
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationsScreen(),
    ),
    // Keyed by uid rather than handle: not everyone has a handle, and a
    // notification or a comment tap only ever knows the uid.
    GoRoute(
      path: '/user/:uid',
      builder: (context, state) =>
          PublicProfileScreen(uid: state.pathParameters['uid']!),
    ),
    GoRoute(
      path: '/cook/:id',
      builder: (context, state) =>
          CookModeScreen(recipeId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/create/recipe',
      builder: (context, state) => const RecipeComposerScreen(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) =>
              RecipeComposerScreen(draftId: state.pathParameters['id']),
        ),
      ],
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => ShellScreen(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.home,
              builder: (context, state) => const HomeScreen(),
              routes: [
                // Nested so a plan opens over the Home tab and keeps its back
                // stack. Also the deep-link target for shared weeks, which
                // mostly arrive over WhatsApp.
                GoRoute(
                  path: 'plan/:id',
                  builder: (context, state) =>
                      PlanDetailScreen(planId: state.pathParameters['id']!),
                ),
                GoRoute(
                  path: 'recipe/:id',
                  builder: (context, state) =>
                      RecipeDetailScreen(recipeId: state.pathParameters['id']!),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.communities,
              builder: (context, state) => PlaceholderScreen(
                title: AppLocalizations.of(context).navCommunities,
                icon: Icons.groups_outlined,
                note: 'Phase 4. Communities open after there is enough content '
                    'for them to feel alive — an empty community is worse '
                    'than none.',
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.chats,
              builder: (context, state) => PlaceholderScreen(
                title: AppLocalizations.of(context).navChats,
                icon: Icons.forum_outlined,
                note: 'Phase 5. DMs, group chats, and community rooms — with '
                    'the request gate on by default.',
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.me,
              builder: (context, state) => const ProfileScreen(),
              routes: [
                GoRoute(
                  path: 'week',
                  builder: (context, state) => const MyWeekScreen(),
                ),
                GoRoute(
                  path: 'edit',
                  builder: (context, state) => const EditProfileScreen(),
                ),
                GoRoute(
                  path: 'settings',
                  builder: (context, state) => const SettingsScreen(),
                ),
                GoRoute(
                  path: 'verification',
                  builder: (context, state) => const VerificationScreen(),
                ),
                GoRoute(
                  path: 'recipes',
                  builder: (context, state) => const MyRecipesScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
