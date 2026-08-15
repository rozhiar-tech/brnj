import 'package:flutter/material.dart';

/// One choice in an [showOptionSheet].
class SheetOption<T> {
  const SheetOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// A single-choice bottom sheet that cannot overflow.
///
/// The obvious way to build one of these — a `Column` with `mainAxisSize.min`
/// inside `showModalBottomSheet` — works right up until the list is longer than
/// the sheet's default 40%-of-screen ceiling, and then it throws instead of
/// scrolling. That is not an edge case: the composer's timer picker has
/// thirteen options and overflowed by 318 pixels the first time anyone opened
/// it.
///
/// So the list always scrolls, and the sheet is capped rather than left to size
/// itself. Short lists still hug their content because the list shrink-wraps.
Future<T?> showOptionSheet<T>(
  BuildContext context, {
  required List<SheetOption<T>> options,
  T? selected,
  String? title,
  double maxHeightFraction = 0.7,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    // Required for the sheet to grow past its default ceiling; without it the
    // constraint below can never be honoured.
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * maxHeightFraction,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, i) {
                    final option = options[i];
                    final isSelected = option.value == selected;
                    return ListTile(
                      leading: option.icon == null ? null : Icon(option.icon),
                      title: Text(option.label),
                      trailing: isSelected
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
                          : null,
                      selected: isSelected,
                      onTap: () => Navigator.pop(context, option.value),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
