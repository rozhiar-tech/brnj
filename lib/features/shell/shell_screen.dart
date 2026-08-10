import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import 'create_sheet.dart';

/// The five-destination shell. Create sits in the middle as a raised button —
/// the one place to be conventional, because everyone already knows how it
/// works.
///
/// [StatefulNavigationShell] keeps a separate navigation stack per tab, so
/// switching tabs doesn't lose your place.
class ShellScreen extends StatelessWidget {
  const ShellScreen({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const _createIndex = 2;

  void _onDestinationSelected(BuildContext context, int index) {
    if (index == _createIndex) {
      showCreateSheet(context);
      return;
    }
    navigationShell.goBranch(
      index,
      // Tapping the tab you're already on pops to its root.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  /// The shell has 4 branches but 5 destinations; Create opens a sheet instead
  /// of navigating, so indices past it shift by one.
  int get _selectedDestination => navigationShell.currentIndex < _createIndex
      ? navigationShell.currentIndex
      : navigationShell.currentIndex + 1;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedDestination,
        onDestinationSelected: (i) => _onDestinationSelected(context, i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.groups_outlined),
            selectedIcon: const Icon(Icons.groups),
            label: l10n.navCommunities,
          ),
          NavigationDestination(
            icon: Container(
              width: 40,
              height: 32,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.add, color: theme.colorScheme.onPrimary, size: 22),
            ),
            label: l10n.navCreate,
          ),
          NavigationDestination(
            icon: const Icon(Icons.forum_outlined),
            selectedIcon: const Icon(Icons.forum),
            label: l10n.navChats,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.navMe,
          ),
        ],
      ),
    );
  }
}
