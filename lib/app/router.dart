import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/chat/chat_room_screen.dart';
import '../features/chat/chats_screen.dart';
import '../features/chat/new_chat_screen.dart';
import '../features/community/communities_screen.dart';
import '../features/community/community_form_screen.dart';
import '../features/community/community_members_screen.dart';
import '../features/community/community_screen.dart';
import '../features/community/post_screen.dart';
import '../features/home/home_screen.dart';
import '../features/plan/my_week_screen.dart';
import '../features/plan/plan_detail_screen.dart';
import '../features/plan/shopping_list_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/profile/follow_list_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/public_profile_screen.dart';
import '../features/profile/settings_screen.dart';
import '../features/admin/admin_screen.dart';
import '../features/profile/verification_screen.dart';
import '../features/recipe/composer/recipe_composer_screen.dart';
import '../features/recipe/cook_mode_screen.dart';
import '../features/recipe/my_recipes_screen.dart';
import '../features/recipe/saved_recipes_screen.dart';
import '../features/recipe/recipe_detail_screen.dart';
import '../features/search/search_screen.dart';
import '../features/shell/route_not_found_screen.dart';
import '../features/shell/shell_screen.dart';

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
  static String communityFor(String id) => '/communities/$id';
  static String chatFor(String id) => '/chats/$id';
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
      routes: [
        GoRoute(
          path: 'followers',
          builder: (context, state) => FollowListScreen(
            uid: state.pathParameters['uid']!,
            initial: FollowListKind.followers,
          ),
        ),
        GoRoute(
          path: 'following',
          builder: (context, state) => FollowListScreen(
            uid: state.pathParameters['uid']!,
            initial: FollowListKind.following,
          ),
        ),
      ],
    ),
    // Recipes and weeks are opened from everywhere — the feed, search, saved,
    // a profile, a notification — so they sit at the top level rather than
    // inside the Home branch.
    //
    // Nesting them under the shell meant pushing one from a screen that is
    // itself outside the shell put a second copy of the shell on the root
    // navigator. go_router keys the shell page off the route object, so both
    // copies carried the same key and Navigator asserted on the duplicate.
    // Communities open from the tab, from a notification, and from a post's
    // author line — so they sit at the top level for exactly the reason
    // recipes do. `/communities/new` is declared before `/communities/:id` or
    // it would be matched as a community whose id is "new".
    GoRoute(
      path: '/communities/new',
      builder: (context, state) => const CommunityFormScreen(),
    ),
    GoRoute(
      path: '/communities/:id',
      builder: (context, state) =>
          CommunityScreen(communityId: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'settings',
          builder: (context, state) =>
              CommunityFormScreen(communityId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'members',
          builder: (context, state) => CommunityMembersScreen(
            communityId: state.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: 'post/:postId',
          builder: (context, state) => CommunityPostScreen(
            communityId: state.pathParameters['id']!,
            postId: state.pathParameters['postId']!,
          ),
        ),
      ],
    ),
    // Conversations sit outside the shell: a chat room is a full-screen task
    // with a keyboard up, and the bottom bar has nothing to offer while you
    // are in one. `/chats/new` before `/chats/:id`, or "new" is read as a
    // conversation id.
    GoRoute(
      path: '/chats/new',
      builder: (context, state) => const NewChatScreen(),
    ),
    GoRoute(
      path: '/chats/:id',
      builder: (context, state) =>
          ChatRoomScreen(chatId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/recipe/:id',
      builder: (context, state) =>
          RecipeDetailScreen(recipeId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/plan/:id',
      builder: (context, state) =>
          PlanDetailScreen(planId: state.pathParameters['id']!),
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
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.communities,
              builder: (context, state) => const CommunitiesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.chats,
              builder: (context, state) => const ChatsScreen(),
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
                GoRoute(
                  path: 'saved',
                  builder: (context, state) => const SavedRecipesScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
