import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bootstrap.dart';
import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../core/iraqi_week.dart';
import '../../core/numerals.dart';
import '../../l10n/gen/app_localizations.dart';
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
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);
    final firebase = ref.watch(firebaseStatusProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: Text(l10n.appName),
            actions: [
              IconButton(
                onPressed: () {},
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
                    ButtonSegment(value: _Feed.following, label: Text(l10n.feedFollowing)),
                    ButtonSegment(value: _Feed.discover, label: Text(l10n.feedDiscover)),
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

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
            sliver: SliverList.separated(
              itemCount: _sampleFeed.length,
              separatorBuilder: (_, _) => const SizedBox(height: Gap.lg),
              itemBuilder: (context, i) => _RecipeCard(
                sample: _sampleFeed[i],
                numerals: numerals,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: theme.platform == TargetPlatform.iOS ? null : null,
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
          Icon(Icons.build_outlined, color: theme.colorScheme.onSecondaryContainer),
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
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.only(start: Gap.lg, end: Gap.lg),
            itemCount: _samplePlans.length,
            separatorBuilder: (_, _) => const SizedBox(width: Gap.md),
            itemBuilder: (context, i) =>
                _PlanCard(sample: _samplePlans[i], numerals: numerals),
          ),
        ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.sample, required this.numerals});

  final _SamplePlan sample;
  final NumeralStyle numerals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 200,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    child: Text(
                      sample.author.characters.first,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Flexible(
                    child: Text(
                      sample.author,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  if (sample.verified) ...[
                    const SizedBox(width: Gap.xs),
                    const VerifiedTick(size: 14),
                  ],
                ],
              ),
              const SizedBox(height: Gap.sm),
              Text(
                sample.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              const Spacer(),
              Text(
                '${formatCount(sample.dishes, style: numerals)} · '
                '${formatCount(sample.copies, style: numerals)} ↺',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.sample, required this.numerals});

  final _SampleRecipe sample;
  final NumeralStyle numerals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 4:3 is the shape food photography wants. Real cards load the 400px
          // thumbnail variant here, never the full-size image.
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Center(
                child: Icon(
                  Icons.restaurant,
                  size: 32,
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sample.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: Gap.xs),
                Row(
                  children: [
                    Text(
                      sample.author,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (sample.verified) ...[
                      const SizedBox(width: Gap.xs),
                      const VerifiedTick(size: 14),
                    ],
                    const Spacer(),
                    Text(
                      '${formatCount(sample.minutes, style: numerals)} min',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Wrap(
                  spacing: Gap.sm,
                  children: [
                    for (final tag in sample.tags) Chip(label: Text(tag)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Sample content -------------------------------------------------------
// Placeholder until the repositories are wired. Real strings, so the layout is
// tested against the scripts it actually has to render.

class _SamplePlan {
  const _SamplePlan(this.author, this.title, this.dishes, this.copies, this.verified);
  final String author;
  final String title;
  final int dishes;
  final int copies;
  final bool verified;
}

const _samplePlans = [
  _SamplePlan('أم علي', 'أسبوع اقتصادي', 9, 214, true),
  _SamplePlan('ژیان', 'هەفتەی خێرا', 7, 88, false),
  _SamplePlan('أم حسن', 'أسبوع رمضان', 14, 1203, true),
];

class _SampleRecipe {
  const _SampleRecipe(this.title, this.author, this.minutes, this.tags, this.verified);
  final String title;
  final String author;
  final int minutes;
  final List<String> tags;
  final bool verified;
}

const _sampleFeed = [
  _SampleRecipe('دولمة بغدادية', 'أم علي', 95, ['بغدادي', 'غداء'], true),
  _SampleRecipe('کوفتەی شۆربا', 'ژیان', 60, ['کوردی', 'شۆربا'], false),
  _SampleRecipe('تشريب باقلاء', 'أبو مصطفى', 45, ['بصراوي', 'فطور'], false),
];
