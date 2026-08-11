import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/plan/my_week_screen.dart';
import '../features/shell/placeholder_screen.dart';
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
  static const plan = '/plan/:id';
  static const profile = '/user/:handle';

  static String recipeFor(String id) => '/recipe/$id';
  static String planFor(String id) => '/plan/$id';
  static String profileFor(String handle) => '/user/$handle';
}

final _rootKey = GlobalKey<NavigatorState>();

GoRouter createRouter() => GoRouter(
  navigatorKey: _rootKey,
  initialLocation: Routes.home,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => ShellScreen(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.home,
              builder: (context, state) => const HomeScreen(),
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
              // Until the profile screen exists, the Me tab opens straight
              // onto the week — it's the part of the profile people actually
              // maintain, and shipping it behind a placeholder helps nobody.
              builder: (context, state) => const MyWeekScreen(),
              routes: [
                GoRoute(
                  path: 'week',
                  builder: (context, state) => const MyWeekScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
