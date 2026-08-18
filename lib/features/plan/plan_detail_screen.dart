import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../core/iraqi_week.dart';
import '../../core/numerals.dart';
import '../../data/models/weekly_plan.dart';
import '../../data/providers.dart';
import '../../data/repositories/view_tracker.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/error_view.dart';
import '../../shared/verified_tick.dart';
import '../recipe/recipe_social.dart';
import '../auth/sign_in_sheet.dart';

final _planProvider = StreamProvider.family<WeeklyPlan?, String>(
  (ref, planId) => ref.watch(planRepositoryProvider).watchPlan(planId),
);

/// Someone else's week, read-only.
///
/// The three actions at the bottom are the point of the screen, and
/// "copy this week to mine" is the one that matters — it's what turns
/// browsing into cooking, and its count is the honest measure of whether a
/// plan was any good.
class PlanDetailScreen extends ConsumerStatefulWidget {
  const PlanDetailScreen({required this.planId, super.key});

  final String planId;

  @override
  ConsumerState<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends ConsumerState<PlanDetailScreen> {
  void Function()? _endView;

  @override
  void initState() {
    super.initState();
    // Counts only if the screen outlives the dwell threshold, deduplicated per
    // person per day, and batched — see ViewTracker for why all three matter.
    final uid = ref.read(currentUidProvider);
    if (uid != null) {
      _endView = ref
          .read(viewTrackerProvider)
          .trackScreen(
            type: ViewTargetType.plan,
            targetId: widget.planId,
            viewerUid: uid,
            isGuest: ref.read(isGuestProvider),
          );
    }
  }

  @override
  void dispose() {
    _endView?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final planAsync = ref.watch(_planProvider(widget.planId));

    return Scaffold(
      appBar: AppBar(),
      body: planAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(error: error),
        data: (plan) => plan == null
            ? Center(child: Text(l10n.errorGeneric))
            : _PlanBody(plan: plan),
      ),
      bottomNavigationBar: planAsync.value == null
          ? null
          : _ActionBar(plan: planAsync.value!),
    );
  }
}

class _PlanBody extends ConsumerWidget {
  const _PlanBody({required this.plan});

  final WeeklyPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: Gap.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    child: Text(
                      plan.owner.name.characters.first,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            plan.owner.name,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (plan.owner.verified) ...[
                          const SizedBox(width: Gap.xs),
                          const VerifiedTick(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (plan.title != null) ...[
                const SizedBox(height: Gap.md),
                Text(plan.title!, style: theme.textTheme.headlineSmall),
              ],
              if (plan.note != null) ...[
                const SizedBox(height: Gap.xs),
                Text(
                  plan.note!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: Gap.md),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [for (final tag in plan.tags) Chip(label: Text(tag))],
              ),
              const SizedBox(height: Gap.md),
              // Counts are public; names are not. The viewer list is readable
              // only by the plan's owner, and anyone can opt out of appearing
              // in it entirely.
              Text(
                '${l10n.statViews(plan.stats.views)}  ·  '
                '${l10n.planCopiedCount(plan.stats.copies)}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        for (var i = 0; i < 7; i++)
          _ReadOnlyDay(
            day: plan.days[i],
            labelKey: iraqiWeekdayKeys[i],
            numerals: numerals,
          ),
        Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: CommentThread(
            recipeId: plan.id,
            recipeAuthorUid: plan.owner.uid,
            isPlan: true,
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyDay extends StatelessWidget {
  const _ReadOnlyDay({
    required this.day,
    required this.labelKey,
    required this.numerals,
  });

  final PlanDay day;
  final String labelKey;
  final NumeralStyle numerals;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: day.isFamilyDay
            ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.35)
            : null,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              _label(l10n, labelKey),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: day.isFamilyDay ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: day.isEmpty
                ? Text(
                    l10n.planEmptyDay,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in day.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Gap.xs),
                          child: Text(
                            entry.title,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _label(AppLocalizations l10n, String key) => switch (key) {
    'weekdaySaturday' => l10n.weekdaySaturday,
    'weekdaySunday' => l10n.weekdaySunday,
    'weekdayMonday' => l10n.weekdayMonday,
    'weekdayTuesday' => l10n.weekdayTuesday,
    'weekdayWednesday' => l10n.weekdayWednesday,
    'weekdayThursday' => l10n.weekdayThursday,
    _ => l10n.weekdayFriday,
  };
}

class _ActionBar extends ConsumerStatefulWidget {
  const _ActionBar({required this.plan});

  final WeeklyPlan plan;

  @override
  ConsumerState<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends ConsumerState<_ActionBar> {
  bool _copying = false;

  Future<void> _copy() async {
    if (!await requireAccount(context, ref)) return;

    setState(() => _copying = true);
    final owner = await ref.read(myAuthorStubFuture.future);
    if (owner == null) {
      if (mounted) setState(() => _copying = false);
      return;
    }

    try {
      // Copies land in the *coming* week, not the current one — cloning
      // someone's Monday when it's already Thursday helps nobody.
      final target = IraqiWeek.current().next;
      await ref
          .read(planRepositoryProvider)
          .copyWeek(source: widget.plan, newOwner: owner, target: target);

      if (!mounted) return;
      // Move the editor to the week the copy landed in, so "go look at it"
      // needs no further navigation.
      ref.read(selectedWeekProvider.notifier).set(target);

      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.planCopiedConfirmation)));
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isMine = ref.watch(currentUidProvider) == widget.plan.owner.uid;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        // Full width is a deliberate choice here, not an accident of the
        // theme: copying a week is the one action this screen exists for.
        child: Row(
          children: [
            IconButton.outlined(
              onPressed: widget.plan.linkedRecipeIds.isEmpty
                  ? null
                  : () => context.push('/shopping/${widget.plan.id}'),
              icon: const Icon(Icons.shopping_basket_outlined),
              tooltip: l10n.planShoppingList,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: FilledButton.icon(
                onPressed: _copying || isMine ? null : _copy,
                icon: _copying
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.copy_all_outlined),
                label: Text(l10n.planCopyToMine),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
