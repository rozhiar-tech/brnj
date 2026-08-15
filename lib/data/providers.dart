import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/bootstrap.dart';
import '../app/settings.dart';
import '../core/iraqi_week.dart';
import 'models/recipe.dart';
import 'models/user_profile.dart';
import 'models/weekly_plan.dart';
import 'repositories/auth_repository.dart';
import 'repositories/media_repository.dart';
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
