import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../core/iraqi_week.dart';
import '../../core/numerals.dart';
import '../../data/models/weekly_plan.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/sign_in_sheet.dart';
import 'add_dish_sheet.dart';
import 'week_header.dart';

/// The seven-day plan editor.
///
/// Everything here is arranged around one number: how long it takes to add a
/// dish. Tap a day, type or pick, done. If that ever exceeds about five
/// seconds, people stop keeping their week up to date and the whole feature
/// stops working.
class MyWeekScreen extends ConsumerWidget {
  const MyWeekScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final week = ref.watch(selectedWeekProvider);
    final planAsync = ref.watch(myWeekProvider);
    final isGuest = ref.watch(isGuestProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.myWeek)),
      body: Column(
        children: [
          WeekHeader(
            week: week,
            onPrevious: () => ref.read(selectedWeekProvider.notifier).previous(),
            onNext: () => ref.read(selectedWeekProvider.notifier).next(),
          ),
          const Divider(),
          Expanded(
            child: isGuest
                ? _GuestPrompt(week: week)
                : planAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _ErrorState(
                      error: error,
                      onRetry: () => ref.invalidate(myWeekProvider),
                    ),
                    data: (plan) => plan == null
                        ? const Center(child: CircularProgressIndicator())
                        : _WeekList(plan: plan),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: planAsync.value == null || isGuest
          ? null
          : _PublishBar(plan: planAsync.value!),
    );
  }
}

/// Guests see the week, they just can't own one. The prompt sells the feature
/// rather than blocking on a login wall.
class _GuestPrompt extends ConsumerWidget {
  const _GuestPrompt({required this.week});

  final IraqiWeek week;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: Gap.lg),
            Text(l10n.planGuestTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: Gap.sm),
            Text(
              l10n.planGuestBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Gap.xl),
            FilledButton(
              onPressed: () => requireAccount(context, ref),
              child: Text(l10n.signInWithPhone),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekList extends ConsumerWidget {
  const _WeekList({required this.plan});

  final WeeklyPlan plan;

  Future<void> _addDish(BuildContext context, WidgetRef ref, int dayIndex) async {
    final entry = await showAddDishSheet(context, ref);
    if (entry == null) return;

    final updated = plan.withDayEntries(dayIndex, [
      ...plan.days[dayIndex].entries,
      entry,
    ]);
    await ref.read(planRepositoryProvider).save(updated);
  }

  Future<void> _removeDish(WidgetRef ref, int dayIndex, int entryIndex) async {
    final entries = [...plan.days[dayIndex].entries]..removeAt(entryIndex);
    await ref.read(planRepositoryProvider).save(
      plan.withDayEntries(dayIndex, entries),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: Gap.xxl),
      itemCount: 7,
      itemBuilder: (context, index) {
        final day = plan.days[index];
        return _DayRow(
          day: day,
          labelKey: iraqiWeekdayKeys[index],
          isToday: _isSameDate(day.date, today),
          onAdd: () => _addDish(context, ref, index),
          onRemove: (entryIndex) => _removeDish(ref, index, entryIndex),
        );
      },
    );
  }

  static bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayRow extends ConsumerWidget {
  const _DayRow({
    required this.day,
    required this.labelKey,
    required this.isToday,
    required this.onAdd,
    required this.onRemove,
  });

  final PlanDay day;
  final String labelKey;
  final bool isToday;
  final VoidCallback onAdd;
  final void Function(int entryIndex) onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);

    // Friday is the big family meal, so it carries more weight than the rest
    // of the week. Tinting it is the layout admitting that.
    final tinted = day.isFamilyDay;

    return Container(
      decoration: BoxDecoration(
        color: tinted ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.35) : null,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _weekdayLabel(l10n, labelKey),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: isToday ? theme.colorScheme.primary : null,
                    fontWeight: tinted || isToday ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                Text(
                  '${day.date.day}'.toNumeralStyle(numerals),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (day.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                    child: Text(
                      l10n.planEmptyDay,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < day.entries.length; i++)
                    _EntryChip(
                      entry: day.entries[i],
                      onRemove: () => onRemove(i),
                    ),
              ],
            ),
          ),
          IconButton(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            tooltip: l10n.planAddDish,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// The generated localisations expose one getter per key, so the day labels
  /// are looked up rather than reflected over.
  String _weekdayLabel(AppLocalizations l10n, String key) => switch (key) {
    'weekdaySaturday' => l10n.weekdaySaturday,
    'weekdaySunday' => l10n.weekdaySunday,
    'weekdayMonday' => l10n.weekdayMonday,
    'weekdayTuesday' => l10n.weekdayTuesday,
    'weekdayWednesday' => l10n.weekdayWednesday,
    'weekdayThursday' => l10n.weekdayThursday,
    _ => l10n.weekdayFriday,
  };
}

class _EntryChip extends StatelessWidget {
  const _EntryChip({required this.entry, required this.onRemove});

  final PlanEntry entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: Row(
        children: [
          // A linked recipe opens; a typed name doesn't. Marking which is which
          // matters, because free text is a first-class entry here — most
          // people won't have written the recipe up.
          Icon(
            entry.isLinked ? Icons.menu_book_outlined : Icons.edit_note,
            size: 16,
            color: entry.isLinked
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(entry.title, style: theme.textTheme.bodyMedium),
          ),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(Gap.xs),
              child: Icon(
                Icons.close,
                size: 16,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublishBar extends ConsumerWidget {
  const _PublishBar({required this.plan});

  final WeeklyPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Row(
          children: [
            Expanded(
              child: Text(
                plan.isPublished
                    ? _visibilityLabel(l10n, plan.visibility)
                    : l10n.planVisibilityPrivate,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: Gap.md),
            FilledButton(
              // Nothing to publish is a real state, not an error — an empty
              // week just isn't worth anyone's time to open.
              onPressed: plan.isEmpty
                  ? null
                  : () => _publish(context, ref),
              child: Text(l10n.planPublish),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _publish(BuildContext context, WidgetRef ref) async {
    final visibility = await showModalBottomSheet<PlanVisibility>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in PlanVisibility.values)
                ListTile(
                  leading: Icon(_visibilityIcon(option)),
                  title: Text(_visibilityLabel(l10n, option)),
                  selected: option == plan.visibility,
                  onTap: () => Navigator.pop(context, option),
                ),
            ],
          ),
        );
      },
    );
    if (visibility == null) return;

    await ref.read(planRepositoryProvider).publish(plan, visibility: visibility);
  }

  static IconData _visibilityIcon(PlanVisibility v) => switch (v) {
    PlanVisibility.public => Icons.public,
    PlanVisibility.followers => Icons.group_outlined,
    PlanVisibility.private => Icons.lock_outline,
  };

  static String _visibilityLabel(AppLocalizations l10n, PlanVisibility v) =>
      switch (v) {
        PlanVisibility.public => l10n.planVisibilityPublic,
        PlanVisibility.followers => l10n.planVisibilityFollowers,
        PlanVisibility.private => l10n.planVisibilityPrivate,
      };
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry, this.error});

  final VoidCallback onRetry;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (kDebugMode && error != null) {
      debugPrint('My week failed to load: $error');
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.errorGeneric, textAlign: TextAlign.center),
            const SizedBox(height: Gap.md),
            OutlinedButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
            // A bare "Retry" tells nobody anything when the real cause is a
            // rejected read. Debug builds surface it rather than hiding it.
            if (kDebugMode && error != null) ...[
              const SizedBox(height: Gap.xl),
              SelectableText(
                '$error',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
