import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/bootstrap.dart';
import '../app/settings.dart';
import '../core/iraqi_week.dart';
import 'models/recipe.dart';
import 'models/social.dart';
import 'models/user_profile.dart';
import 'models/weekly_plan.dart';
import 'repositories/admin_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/media_repository.dart';
import 'repositories/notification_repository.dart';
import 'repositories/messaging_repository.dart';
import 'repositories/plan_repository.dart';
import 'repositories/recipe_repository.dart';
import 'repositories/user_repository.dart';
import 'repositories/view_tracker.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());
final recipeRepositoryProvider = Provider<RecipeRepository>(
  (ref) => RecipeRepository(),
);
final planRepositoryProvider = Provider<PlanRepository>((ref) => PlanRepository());
final userRepositoryProvider = Provider<UserRepository>((ref) => UserRepository());
final mediaRepositoryProvider = Provider<MediaRepository>(
  (ref) => MediaRepository(),
);
final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(),
);
final messagingRepositoryProvider = Provider<MessagingRepository>(
  (ref) => MessagingRepository(),
);
final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(),
);

/// Moderation powers, read from the Auth token.
///
/// Recomputed whenever the signed-in user changes. Claims only reach the client
/// when the ID token is reissued, so a freshly granted moderator has to sign
/// out and back in — or the granting screen forces a refresh.
final adminClaimsProvider = FutureProvider<AdminClaims>((ref) async {
  ref.watch(authStateProvider);
  return ref.watch(adminRepositoryProvider).claims();
});

/// True once the token says so. Defaults to false while loading, so no
/// moderation affordance is ever shown speculatively.
final isModeratorProvider = Provider<bool>(
  (ref) => ref.watch(adminClaimsProvider).value?.canModerate ?? false,
);

final viewTrackerProvider = Provider<ViewTracker>((ref) {
  final tracker = ViewTracker(prefs: ref.watch(sharedPreferencesProvider));
  ref.onDispose(tracker.dispose);
  return tracker;
});

/// The Firebase user, which is never null in normal operation — everyone is
/// signed in, guests anonymously.
final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

final currentUidProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider).value?.uid,
);

/// True when the person has no real account yet. Drives every gate in the UI.
///
/// Defaults to true while auth is still loading: briefly hiding a button is
/// recoverable, briefly showing a write action that will be rejected is not.
final isGuestProvider = Provider<bool>((ref) {
  final user = ref.watch(authStateProvider).value;
  return user == null || user.isAnonymous;
});

/// The signed-in user's profile document. Null for guests, who have none.
final myProfileProvider = StreamProvider<UserProfile?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || ref.watch(isGuestProvider)) return Stream.value(null);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.exists ? UserProfile.fromDoc(doc) : null);
});

/// The author stub stamped onto everything this person writes.
///
/// `verified` is copied from the profile, and the security rules check that
/// copy against the Auth token — so a client that lies about it has the write
/// rejected rather than getting a free ranking boost.
final myAuthorStubProvider = Provider<AuthorStub?>((ref) {
  final profile = ref.watch(myProfileProvider).value;
  if (profile == null) return null;
  return AuthorStub(
    uid: profile.uid,
    name: profile.displayName,
    photoUrl: profile.photoUrl,
    verified: profile.verified,
  );
});

/// The language new content defaults to.
///
/// Separate from the interface language on purpose: plenty of people want a
/// Kurdish interface and write their recipes in Arabic, or the reverse. Falls
/// back to the UI language until the person has stated a preference.
final activeContentLanguageProvider = Provider<String>((ref) {
  final profile = ref.watch(myProfileProvider).value;
  final preferred = profile?.contentLanguages.firstOrNull;
  return preferred ?? ref.watch(activeLocaleProvider).locale.languageCode;
});

/// Which week the plan screens are showing. Saturday-based, defaults to now.
class SelectedWeek extends Notifier<IraqiWeek> {
  @override
  IraqiWeek build() => IraqiWeek.current();

  void next() => state = state.next;
  void previous() => state = state.previous;
  void reset() => state = IraqiWeek.current();
  void set(IraqiWeek week) => state = week;
}

final selectedWeekProvider = NotifierProvider<SelectedWeek, IraqiWeek>(
  SelectedWeek.new,
);

/// The current user's plan for [selectedWeekProvider]. Emits an unsaved empty
/// week when none exists, so the editor always has something to render — the
/// first write happens when a dish is added, not when the screen opens.
final myWeekProvider = StreamProvider<WeeklyPlan?>((ref) {
  final owner = ref.watch(myAuthorStubProvider);
  if (owner == null) return Stream.value(null);

  return ref
      .watch(planRepositoryProvider)
      .watchMyWeek(owner: owner, week: ref.watch(selectedWeekProvider));
});

/// "This week in Iraqi kitchens" — public plans for the selected week.
final publicWeekPlansProvider = StreamProvider<List<WeeklyPlan>>((ref) {
  if (ref.watch(firebaseStatusProvider) != FirebaseStatus.ready) {
    return Stream.value(const []);
  }
  return ref
      .watch(planRepositoryProvider)
      .watchPublicWeek(week: ref.watch(selectedWeekProvider));
});

/// The Discover feed: published recipes, ranked.
///
/// Ranking lives in the `score` field, recomputed by a scheduled Function, so
/// this is a single indexed query. Until that Function exists every score is
/// zero and this is effectively arbitrary order — which is fine while the
/// corpus is small, and wrong the moment it isn't.
final discoverFeedProvider = FutureProvider<List<Recipe>>((ref) async {
  if (ref.watch(firebaseStatusProvider) != FirebaseStatus.ready) return const [];
  return ref.watch(recipeRepositoryProvider).discoverPage();
});

/// Recipes written by the signed-in user, drafts included.
final myRecipesProvider = StreamProvider<List<Recipe>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || ref.watch(isGuestProvider)) return Stream.value(const []);
  return ref
      .watch(recipeRepositoryProvider)
      .watchUserRecipes(uid, includeDrafts: true);
});

/// Ids of everything the current user has saved, for the save toggle in feeds.
final savedRecipeIdsProvider = StreamProvider<List<String>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(recipeRepositoryProvider).watchSavedIds(uid);
});


// --- social surfaces -------------------------------------------------------

/// The "I cooked this" gallery for one recipe.
final cookedPostsProvider = StreamProvider.family<List<CookedPost>, String>(
  (ref, recipeId) =>
      ref.watch(recipeRepositoryProvider).watchCooked(recipeId),
);

/// Whether the signed-in person has already posted a "cooked this" here.
final hasCookedProvider = StreamProvider.family<bool, String>((ref, recipeId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || ref.watch(isGuestProvider)) return Stream.value(false);
  return ref
      .watch(recipeRepositoryProvider)
      .watchHasCooked(recipeId: recipeId, uid: uid);
});

final commentsProvider = StreamProvider.family<List<Comment>, String>(
  (ref, recipeId) =>
      ref.watch(recipeRepositoryProvider).watchComments(recipeId),
);

final likedProvider = StreamProvider.family<bool, String>((ref, recipeId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || ref.watch(isGuestProvider)) return Stream.value(false);
  return ref
      .watch(recipeRepositoryProvider)
      .watchLiked(recipeId: recipeId, uid: uid);
});

/// Someone else's profile, by uid.
final userProfileProvider = StreamProvider.family<UserProfile?, String>(
  (ref, uid) => ref.watch(userRepositoryProvider).watchProfile(uid),
);

final userRecipesProvider = StreamProvider.family<List<Recipe>, String>(
  (ref, uid) => ref.watch(recipeRepositoryProvider).watchUserRecipes(uid),
);

final isFollowingProvider = StreamProvider.family<bool, String>((ref, targetUid) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || ref.watch(isGuestProvider)) return Stream.value(false);
  return ref
      .watch(userRepositoryProvider)
      .watchIsFollowing(uid: uid, targetUid: targetUid);
});

final followingIdsProvider = StreamProvider<List<String>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || ref.watch(isGuestProvider)) return Stream.value(const []);
  return ref.watch(userRepositoryProvider).watchFollowingIds(uid);
});

/// The Following feed: strictly chronological, no ranking and no verified
/// boost. One feed has to be trustworthy or following means nothing.
final followingFeedProvider = FutureProvider<List<Recipe>>((ref) async {
  final ids = ref.watch(followingIdsProvider).value ?? const [];
  if (ids.isEmpty) return const [];
  return ref.watch(recipeRepositoryProvider).followingPage(authorIds: ids);
});

final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || ref.watch(isGuestProvider)) return Stream.value(const []);
  return ref.watch(notificationRepositoryProvider).watch(uid);
});

final unreadNotificationsProvider = StreamProvider<int>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || ref.watch(isGuestProvider)) return Stream.value(0);
  return ref.watch(notificationRepositoryProvider).watchUnreadCount(uid);
});
