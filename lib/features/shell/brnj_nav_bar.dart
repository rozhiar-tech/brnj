import 'package:flutter/material.dart';

/// One slot in the bottom bar.
///
/// [BrnjNavItem.action] is the middle button: it opens the create sheet rather
/// than navigating, so it is never "selected" and never carries a selection
/// indicator.
class BrnjNavItem {
  const BrnjNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.action = false,
  });

  const BrnjNavItem.action({required this.icon, required this.label})
    : selectedIcon = icon,
      action = true;

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool action;
}

/// The bottom bar.
///
/// Written by hand rather than with [NavigationBar] because the middle slot is
/// an action, not a destination. Faking it as a destination means Material
/// draws its selection pill behind the raised button, gives it a selected
/// state it can never hold, and forces every index to be shifted around it.
///
/// Every slot here shares the same geometry — a fixed-height icon row above a
/// label on a common baseline — so the raised button changes the *fill* of its
/// slot without changing the rhythm of the bar.
class BrnjNavBar extends StatelessWidget {
  const BrnjNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<BrnjNavItem> items;

  /// Index into [items]. The action slot is never selected.
  final int selectedIndex;

  final ValueChanged<int> onSelected;

  static const _iconSlotHeight = 30.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            // A plain Row is already direction-aware, so the bar mirrors in
            // Arabic and Kurdish without any of this knowing about it.
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _Slot(
                    item: items[i],
                    selected: !items[i].action && i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final BrnjNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: item.action,
      selected: item.action ? null : selected,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: BrnjNavBar._iconSlotHeight,
              child: Center(
                child: item.action
                    ? const _CreateButton()
                    : Icon(
                        selected ? item.selectedIcon : item.icon,
                        size: 24,
                        color: color,
                      ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: item.action ? theme.colorScheme.primary : color,
                fontWeight: selected || item.action
                    ? FontWeight.w600
                    : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The raised create affordance. Sized to fill the icon slot exactly, so it
/// reads as raised without pushing the bar's baseline around.
class _CreateButton extends StatelessWidget {
  const _CreateButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 44,
      height: BrnjNavBar._iconSlotHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.add, size: 20, color: theme.colorScheme.onPrimary),
    );
  }
}
