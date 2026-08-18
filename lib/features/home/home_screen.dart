import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/bootstrap.dart';
import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../core/iraqi_week.dart';
import '../../core/numerals.dart';
import '../../data/models/weekly_plan.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/error_view.dart';
import '../../shared/recipe_card.dart';
import '../../shared/verified_tick.dart';

enum _Feed { following, discover }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Discover is ranked; Following is strictly chronological. People need one
  /// feed they can trust to be complete, so the verified boost never touches
  /// Following.
  _Feed _feed = _Feed.discover;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numerals = ref.watch(numeralStyleProvider);
    final firebase = ref.watch(firebaseStatusProvider);

    return Scaffold(
      body: RefreshIndicator(
        // A feed with no way to refresh means the only fix for stale content
        // is killing the app, which is what people will actually do.
        onRefresh: () async {
          ref.invalidate(discoverFeedProvider);
          ref.invalidate(followingFeedProvider);
          ref.invalidate(publicWeekPlansProvider);
          await ref.read(discoverFeedProvider.future);
        },
        child: CustomScrollView(
          // Always scrollable, or the gesture does nothing on a short feed —
          // which is exactly when someone reaches for it.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              title: Text(l10n.appName),
              actions: [
                const _NotificationBell(),
                IconButton(
                  onPressed: () => context.push('/search'),
                  icon: const Icon(Icons.search),
                  tooltip: MaterialLocalizations.of(context).searchFieldLabel,
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
                  child: SegmentedButton<_Feed>(
                    segments: [
                      ButtonSegment(
                        value: _Feed.following,
                        label: Text(l10n.feedFollowing),
                      ),
                      ButtonSegment(
                        value: _Feed.discover,
                        label: Text(l10n.feedDiscover),
                      ),
                    ],
                    selected: {_feed},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _feed = s.first),
                  ),
                ),
              ),
            ),

            if (firebase != FirebaseStatus.ready)
              SliverToBoxAdapter(child: _SetupBanner(status: firebase)),

            SliverToBoxAdapter(child: _ThisWeekRail(numerals: numerals)),

            _FeedSliver(numerals: numerals, feed: _feed),
          ],
        ),
      ),
    );
  }
}

/// Shown until `flutterfire configure` has been run. Better than a blank feed
/// and a silent failure.
class _SetupBanner extends StatelessWidget {
  const _SetupBanner({required this.status});

  final FirebaseStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.build_outlined,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              status == FirebaseStatus.notConfigured
                  ? 'Firebase not connected yet — run `flutterfire configure`. '
                        'Showing sample content.'
                  : 'Firebase connection failed. Showing sample content.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "This week in Iraqi kitchens" — the entry point to browsing other people's
/// weeks, and during Ramadan the front page of the app.
class _ThisWeekRail extends StatelessWidget {
  const _ThisWeekRail({required this.numerals});

  final NumeralStyle numerals;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final week = IraqiWeek.current();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.thisWeekInKitchens,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                week.id.toNumeralStyle(numerals),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 132, child: _PlanRail(numerals: numerals)),
        const SizedBox(height: Gap.lg),
      ],
    );
  }
}

/// The public weeks for the selected week, straight from Firestore.
///
/// An empty rail is a real state and it says so, rather than showing a
/// spinner forever or pretending there is content — before launch there
/// genuinely are no published weeks, and the honest empty state is what tells
/// you the seeding still has to happen.
class _PlanRail extends ConsumerWidget {
  const _PlanRail({required this.numerals});

  final NumeralStyle numerals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(publicWeekPlansProvider);
    final theme = Theme.of(context);

    return plansAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(error: error),
      data: (plans) {
        if (plans.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                AppLocalizations.of(context).planRailEmpty,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          );
        }

        return ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.only(start: Gap.lg, end: Gap.lg),
          itemCount: plans.length,
          separatorBuilder: (_, _) => const SizedBox(width: Gap.md),
          itemBuilder: (context, i) =>
              _PlanCard(plan: plans[i], numerals: numerals),
        );
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.numerals});

  final WeeklyPlan plan;
  final NumeralStyle numerals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 200,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go('/plan/${plan.id}'),
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      child: Text(
                        plan.owner.name.characters.first,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Flexible(
                      child: Text(
                        plan.owner.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    if (plan.owner.verified) ...[
                      const SizedBox(width: Gap.xs),
                      const VerifiedTick(size: 14),
                    ],
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  plan.title ?? AppLocalizations.of(context).myWeek,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  '${formatCount(plan.dishCount, style: numerals)} · '
                  '${formatCount(plan.stats.copies, style: numerals)} ↺',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Discover feed.
///
/// Real recipes now — the sample cards that used to sit here were the last
/// piece of fiction on the main screen, and an honest empty state is more use
/// than a fake full one.
class _FeedSliver extends ConsumerWidget {
  const _FeedSliver({required this.numerals, required this.feed});

  final NumeralStyle numerals;
  final _Feed feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Following is strictly chronological and Discover is ranked. Keeping them
    // as separate providers is what stops the boost leaking into the one feed
    // that has to be trustworthy.
    final feedAsync = feed == _Feed.following
        ? ref.watch(followingFeedProvider)
        : ref.watch(discoverFeedProvider);

    return feedAsync.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(Gap.xxl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => SliverToBoxAdapter(
        child: SizedBox(
          height: 260,
          child: ErrorView(
            error: error,
            onRetry: () => ref.invalidate(
              feed == _Feed.following
                  ? followingFeedProvider
                  : discoverFeedProvider,
            ),
          ),
        ),
      ),
      data: (recipes) {
        if (recipes.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(Gap.xxl),
              child: Column(
                children: [
                  Icon(
                    Icons.restaurant_menu,
                    size: 40,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: Gap.md),
                  Text(
                    feed == _Feed.following
                        ? l10n.feedFollowingEmpty
                        : l10n.feedEmpty,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
          sliver: SliverList.separated(
            itemCount: recipes.length,
            separatorBuilder: (_, _) => const SizedBox(height: Gap.lg),
            itemBuilder: (context, i) =>
                RecipeCard(recipe: recipes[i], numerals: numerals),
          ),
        );
      },
    );
  }
}

/// Unread notifications, as a dot rather than a number.
///
/// A count invites the reflex of clearing it; a dot just says "something
/// happened", which is all this needs to say.
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unread = ref.watch(unreadNotificationsProvider).value ?? 0;

    return IconButton(
      onPressed: () => context.push('/notifications'),
      tooltip: l10n.notificationsTitle,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none),
          if (unread > 0)
            PositionedDirectional(
              end: -1,
              top: -1,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
