import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../core/iraqi_week.dart';
import '../../core/numerals.dart';

/// Week stepper: which Saturday-to-Friday window the screen is showing.
///
/// The arrows are [IconButton]s with `Directionality`-aware icons rather than
/// hardcoded chevrons, because in Arabic and Kurdish "next" points left.
class WeekHeader extends ConsumerWidget {
  const WeekHeader({
    required this.week,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  final IraqiWeek week;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
            tooltip: MaterialLocalizations.of(context).previousMonthTooltip,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _range(numerals),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
                if (week.isCurrent)
                  Text(
                    MaterialLocalizations.of(context).currentDateLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: MaterialLocalizations.of(context).nextMonthTooltip,
          ),
        ],
      ),
    );
  }

  /// `15/8 – 21/8`. Deliberately not [DateFormat]: a full localised date is too
  /// long for this row in Arabic, and the numerals still have to follow the
  /// user's setting.
  String _range(NumeralStyle numerals) {
    String short(DateTime d) => '${d.day}/${d.month}';
    return '${short(week.start)} – ${short(week.end)}'.toNumeralStyle(numerals);
  }
}
