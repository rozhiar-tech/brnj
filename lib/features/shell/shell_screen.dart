import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import 'brnj_nav_bar.dart';
import 'create_sheet.dart';

/// The app shell: four destinations with the create action in the middle.
///
/// [StatefulNavigationShell] keeps a separate navigation stack per destination,
/// so switching tabs doesn't lose your place in the one you left.
class ShellScreen extends StatelessWidget {
  const ShellScreen({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// Slot 2 of 5 is the create action. Slots map to branches by skipping it,
  /// which is the only index arithmetic in the file.
  static const _actionSlot = 2;

  int _slotToBranch(int slot) => slot < _actionSlot ? slot : slot - 1;

  int get _branchToSlot => navigationShell.currentIndex < _actionSlot
      ? navigationShell.currentIndex
      : navigationShell.currentIndex + 1;

  void _onSlotSelected(BuildContext context, int slot) {
    if (slot == _actionSlot) {
      showCreateSheet(context);
      return;
    }

    final branch = _slotToBranch(slot);
    navigationShell.goBranch(
      branch,
      // Tapping the destination you're already on pops it back to its root.
      initialLocation: branch == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BrnjNavBar(
        selectedIndex: _branchToSlot,
        onSelected: (slot) => _onSlotSelected(context, slot),
        items: [
          BrnjNavItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            label: l10n.navHome,
          ),
          BrnjNavItem(
            icon: Icons.groups_outlined,
            selectedIcon: Icons.groups,
            label: l10n.navCommunities,
          ),
          BrnjNavItem.action(icon: Icons.add, label: l10n.navCreate),
          BrnjNavItem(
            icon: Icons.forum_outlined,
            selectedIcon: Icons.forum,
            label: l10n.navChats,
          ),
          BrnjNavItem(
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
            label: l10n.navMe,
          ),
        ],
      ),
    );
  }
}
