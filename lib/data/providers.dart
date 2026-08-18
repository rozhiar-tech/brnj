import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/bootstrap.dart';
import '../app/settings.dart';
import '../core/iraqi_week.dart';
import 'models/chat.dart';
import 'models/community.dart';
import 'models/recipe.dart';
import 'models/social.dart';
import 'models/user_profile.dart';
import 'models/weekly_plan.dart';
import 'repositories/admin_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/chat_repository.dart';
import 'repositories/community_repository.dart';
import 'repositories/media_repository.dart';
import 'repositories/notification_repository.dart';
import 'repositories/messaging_repository.dart';
import 'repositories/plan_repository.dart';
import 'repositories/recipe_repository.dart';
import 'repositories/safety_repository.dart';
import 'repositories/user_repository.dart';
import 'repositories/view_tracker.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());
final recipeRepositoryProvider = Provider<RecipeRepository>(
  (ref) => RecipeRepository(),
);
final planRepositoryProvider = Provider<PlanRepository>((ref) => PlanRepository());
final communityRepositoryProvider = Provider<CommunityRepository>(
  (ref) => CommunityRepository(),
);
final chatRepositoryProvider = Provider<ChatRepository>((ref) => ChatRepository());
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
final safetyRepositoryProvider = Provider<SafetyRepository>(
  (ref) => SafetyRepository(),
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
/// `verified` comes from the *token*, not the profile document, because the
/// rules check the token. Taking it from the document meant a freshly verified
/// account stamped verified:true while its token still said false, and every
/// write it made was refused until it signed out.
///
/// The token lags by up to an hour, so a new tick shows up late on your own
/// posts. That is the harmless direction: you lose a badge for a while rather
/// than losing the ability to post.
final myAuthorStubProvider = Provider<AuthorStub?>((ref) {
  final profile = ref.watch(myProfileProvider).value;
  if (profile == null) return null;

  final verifiedByToken = ref.watch(adminClaimsProvider).value?.verified ?? false;

  return AuthorStub(
    uid: profile.uid,
    name: profile.displayName,
    photoUrl: profile.photoUrl,
    verified: verifiedByToken,
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

/// The author stub, awaited.
///
/// [myAuthorStubProvider] is synchronous, so reading it from a callback on a
/// screen that never watched it returns null: Riverpod builds the chain cold,
/// the profile stream has not emitted yet, and there is no value. Callers then
/// gave up silently — which is exactly what "I can't comment" looked like.
///
/// Anything writing on behalf of the signed-in person should await this.
final myAuthorStubFuture = FutureProvider<AuthorStub?>((ref) async {
  if (ref.watch(isGuestProvider)) return null;

  final profile = await ref.watch(myProfileProvider.future);
  if (profile == null) return null;

  // The token, not the document — the rules check the token, and the two
  // disagree for as long as it takes an ID token to be reissued.
  final claims = await ref.watch(adminClaimsProvider.future);

  return AuthorStub(
    uid: profile.uid,
    name: profile.displayName,
    photoUrl: profile.photoUrl,
    verified: claims.verified,
  );
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

  // Every watch happens before the await. Reading ref after an await is
  // unsafe in Riverpod — the provider may already have been disposed or
  // rebuilt — and it silently cost the whole feed.
  final repository = ref.watch(recipeRepositoryProvider);
  final blocked = ref.watch(blockedIdsProvider).value ?? const <String>[];

  final recipes = await repository.discoverPage();
  return _withoutBlocked(blocked, recipes);
});

/// Firestore cannot express "author not in this list", so blocking is applied
/// after the query. The list is small by nature — and a block that still shows
/// you their recipes is not a block.
List<Recipe> _withoutBlocked(List<String> blocked, List<Recipe> recipes) {
  if (blocked.isEmpty) return recipes;
  return recipes.where((r) => !blocked.contains(r.author.uid)).toList();
}

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
  (ref, recipeId) {
    final blocked = ref.watch(blockedIdsProvider).value ?? const [];
    return ref
        .watch(recipeRepositoryProvider)
        .watchComments(recipeId)
        .map((comments) => blocked.isEmpty
            ? comments
            : comments
                  .where((c) => !blocked.contains(c.author.uid))
                  .toList());
  },
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

  final repository = ref.watch(recipeRepositoryProvider);
  final blocked = ref.watch(blockedIdsProvider).value ?? const <String>[];

  final recipes = await repository.followingPage(authorIds: ids);
  return _withoutBlocked(blocked, recipes);
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


/// Everyone the signed-in person has blocked.
///
/// Filtering happens on the client because Firestore cannot express "not in
/// this list" in a query. The list is small by nature, and the rules already
/// stop a blocked person reading the blocker's profile — this is the other
/// half, keeping their content out of feeds.
final blockedIdsProvider = StreamProvider<List<String>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || ref.watch(isGuestProvider)) return Stream.value(const []);
  return ref.watch(safetyRepositoryProvider).watchBlockedIds(uid);
});

final isBlockedProvider = StreamProvider.family<bool, String>((ref, targetUid) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || ref.watch(isGuestProvider)) return Stream.value(false);
  return ref
      .watch(safetyRepositoryProvider)
      .watchIsBlocked(uid: uid, targetUid: targetUid);
});


/// People search. Family-keyed on the query so each search is its own future
/// and a stale one cannot overwrite a newer result.
final peopleSearchProvider = FutureProvider.family<List<UserProfile>, String>(
  (ref, query) => ref.watch(userRepositoryProvider).searchPeople(query),
);


/// Comments under a published week.
final planCommentsProvider = StreamProvider.family<List<Comment>, String>(
  (ref, planId) {
    final blocked = ref.watch(blockedIdsProvider).value ?? const [];
    return ref
        .watch(planRepositoryProvider)
        .watchComments(planId)
        .map(
          (comments) => blocked.isEmpty
              ? comments
              : comments
                    .where((c) => !blocked.contains(c.author.uid))
                    .toList(),
        );
  },
);

/// Someone's published weeks, for the archive on their profile.
final userPlansProvider = StreamProvider.family<List<WeeklyPlan>, String>(
  (ref, uid) => ref.watch(planRepositoryProvider).watchUserPlans(uid),
);


/// Who follows [uid], and who [uid] follows, as profiles rather than ids.
final followersProvider = FutureProvider.family<List<UserProfile>, String>(
  (ref, uid) async {
    final repository = ref.watch(userRepositoryProvider);
    final ids = await repository.watchFollowerIds(uid).first;
    return repository.profilesByIds(ids);
  },
);

final followingProvider = FutureProvider.family<List<UserProfile>, String>(
  (ref, uid) async {
    final repository = ref.watch(userRepositoryProvider);
    final ids = await repository.watchFollowingIds(uid).first;
    return repository.profilesByIds(ids);
  },
);

// ---- communities ----------------------------------------------------------

/// Filters for the community directory. A record rather than a class so the
/// family key compares by value for free — two identical filters are one
/// provider, not two subscriptions.
typedef CommunityFilter = ({CommunityCategory? category, String? region});

const noCommunityFilter = (category: null, region: null);

final communityDirectoryProvider =
    StreamProvider.family<List<Community>, CommunityFilter>(
      (ref, filter) => ref
          .watch(communityRepositoryProvider)
          .watchDirectory(category: filter.category, region: filter.region),
    );

/// Communities the signed-in person belongs to. Empty for guests, who have no
/// membership documents to find.
final myCommunitiesProvider = StreamProvider<List<Community>>((ref) {
  final repository = ref.watch(communityRepositoryProvider);
  final uid = ref.watch(currentUidProvider);
  final guest = ref.watch(isGuestProvider);
  if (uid == null || guest) return Stream.value(const <Community>[]);
  return repository.watchMyCommunities(uid);
});

final communityProvider = StreamProvider.family<Community?, String>(
  (ref, id) => ref.watch(communityRepositoryProvider).watchCommunity(id),
);

/// The signed-in person's membership row, or null if they are not in.
final myMembershipProvider =
    StreamProvider.family<CommunityMember?, String>((ref, communityId) {
      final repository = ref.watch(communityRepositoryProvider);
      final uid = ref.watch(currentUidProvider);
      if (uid == null) return Stream.value(null);
      return repository.watchMembership(communityId: communityId, uid: uid);
    });

final communityMembersProvider =
    StreamProvider.family<List<CommunityMember>, String>(
      (ref, id) => ref.watch(communityRepositoryProvider).watchMembers(id),
    );

/// The approval queue. Only a moderator can read it — for anyone else this
/// provider errors, which is why nothing watches it outside the moderator tab.
final communityRequestsProvider =
    StreamProvider.family<List<CommunityJoinRequest>, String>(
      (ref, id) => ref.watch(communityRepositoryProvider).watchRequests(id),
    );

/// Posts in a community, with blocked authors dropped.
///
/// Same after-the-fact filtering as recipe comments: Firestore cannot express
/// "author not in this list", and a block that still shows you their posts is
/// not a block.
final communityPostsProvider =
    StreamProvider.family<List<CommunityPost>, String>((ref, id) {
      final repository = ref.watch(communityRepositoryProvider);
      final blockedAsync = ref.watch(blockedIdsProvider);
      final blocked = blockedAsync.value ?? const <String>[];

      return repository
          .watchPosts(id)
          .map(
            (posts) => blocked.isEmpty
                ? posts
                : posts
                      .where((p) => !blocked.contains(p.author.uid))
                      .toList(),
          );
    });

final pinnedPostsProvider = StreamProvider.family<List<CommunityPost>, String>(
  (ref, id) => ref.watch(communityRepositoryProvider).watchPinned(id),
);

/// Key for anything addressed by community *and* post.
typedef PostKey = ({String communityId, String postId});

final communityPostCommentsProvider =
    StreamProvider.family<List<Comment>, PostKey>((ref, key) {
      final repository = ref.watch(communityRepositoryProvider);
      final blockedAsync = ref.watch(blockedIdsProvider);
      final blocked = blockedAsync.value ?? const <String>[];

      return repository
          .watchPostComments(
            communityId: key.communityId,
            postId: key.postId,
          )
          .map(
            (comments) => blocked.isEmpty
                ? comments
                : comments
                      .where((c) => !blocked.contains(c.author.uid))
                      .toList(),
          );
    });

/// Whether the signed-in person is waiting on approval for [communityId].
final myJoinRequestProvider = StreamProvider.family<bool, String>((
  ref,
  communityId,
) {
  final repository = ref.watch(communityRepositoryProvider);
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(false);
  return repository.watchMyRequest(communityId: communityId, uid: uid);
});

// ---- chats ----------------------------------------------------------------

/// Every conversation, accepted or not. One query; the split happens below.
///
/// Empty for guests, who have no conversations and whose anonymous uid would
/// otherwise attach a listener that can never return anything.
final allChatsProvider = StreamProvider<List<Chat>>((ref) {
  final repository = ref.watch(chatRepositoryProvider);
  final uid = ref.watch(currentUidProvider);
  final guest = ref.watch(isGuestProvider);
  if (uid == null || guest) return Stream.value(const <Chat>[]);
  return repository.watchChats(uid);
});

/// Conversations this person has accepted, with blocked senders dropped.
///
/// Blocking is applied here rather than in the query for the same reason it is
/// everywhere else: Firestore cannot express "not in this list". A blocked
/// person's conversation staying in the inbox is not a block.
final inboxProvider = Provider<AsyncValue<List<Chat>>>((ref) {
  final uid = ref.watch(currentUidProvider);
  final blocked = ref.watch(blockedIdsProvider).value ?? const <String>[];

  return ref
      .watch(allChatsProvider)
      .whenData(
        (chats) => chats
            .where(
              (chat) =>
                  chat.hasAccepted(uid) &&
                  !chat.memberIds.any(
                    (member) => member != uid && blocked.contains(member),
                  ),
            )
            .toList(),
      );
});

/// Conversations waiting on this person's answer.
final chatRequestsProvider = Provider<AsyncValue<List<Chat>>>((ref) {
  final uid = ref.watch(currentUidProvider);
  final blocked = ref.watch(blockedIdsProvider).value ?? const <String>[];

  return ref
      .watch(allChatsProvider)
      .whenData(
        (chats) => chats
            .where(
              (chat) =>
                  !chat.hasAccepted(uid) &&
                  !chat.memberIds.any(
                    (member) => member != uid && blocked.contains(member),
                  ),
            )
            .toList(),
      );
});

/// The number on the Chats tab.
///
/// Counts only accepted conversations: a request is something to look at, not
/// something to be chased about, and badging them makes the gate feel like
/// nagging rather than protection.
final unreadChatCountProvider = Provider<int>((ref) {
  final uid = ref.watch(currentUidProvider);
  final chats = ref.watch(inboxProvider).value ?? const <Chat>[];
  return chats.fold(0, (total, chat) => total + chat.unreadFor(uid));
});

final chatProvider = StreamProvider.family<Chat?, String>(
  (ref, id) => ref.watch(chatRepositoryProvider).watchChat(id),
);

final messagesProvider = StreamProvider.family<List<Message>, String>((
  ref,
  chatId,
) {
  final repository = ref.watch(chatRepositoryProvider);
  final blocked = ref.watch(blockedIdsProvider).value ?? const <String>[];

  return repository
      .watchMessages(chatId)
      .map(
        (messages) => blocked.isEmpty
            ? messages
            : messages
                  .where((m) => !blocked.contains(m.author.uid))
                  .toList(),
      );
});

/// Whether [uid] follows the signed-in person.
///
/// The opposite direction from [isFollowingProvider], and the one the DM gate
/// turns on: `following` mode means they have shown interest in you, which is
/// something you cannot grant yourself by following them.
final followsMeProvider = StreamProvider.family<bool, String>((ref, uid) {
  final me = ref.watch(currentUidProvider);
  if (me == null || ref.watch(isGuestProvider)) return Stream.value(false);
  return ref.watch(userRepositoryProvider).watchIsFollowing(
    uid: uid,
    targetUid: me,
  );
});
