import 'package:brnj/features/shell/brnj_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const items = [
    BrnjNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
    BrnjNavItem(
      icon: Icons.groups_outlined,
      selectedIcon: Icons.groups,
      label: 'Communities',
    ),
    BrnjNavItem.action(icon: Icons.add, label: 'Create'),
    BrnjNavItem(
      icon: Icons.forum_outlined,
      selectedIcon: Icons.forum,
      label: 'Chats',
    ),
    BrnjNavItem(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: 'Me',
    ),
  ];

  Future<List<int>> pumpAndTap(
    WidgetTester tester, {
    required int selectedIndex,
    required String tapLabel,
    TextDirection direction = TextDirection.rtl,
  }) async {
    final taps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            bottomNavigationBar: BrnjNavBar(
              items: items,
              selectedIndex: selectedIndex,
              onSelected: taps.add,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(tapLabel));
    await tester.pump();
    return taps;
  }

  testWidgets('renders every slot with its label', (tester) async {
    await pumpAndTap(tester, selectedIndex: 0, tapLabel: 'Home');
    for (final item in items) {
      expect(find.text(item.label), findsOneWidget);
    }
  });

  testWidgets('reports the slot index that was tapped', (tester) async {
    // The action sits at slot 2, so slots after it must still report their own
    // index — translating to a branch is the shell's job, not the bar's.
    expect(await pumpAndTap(tester, selectedIndex: 0, tapLabel: 'Chats'), [3]);
    expect(await pumpAndTap(tester, selectedIndex: 0, tapLabel: 'Me'), [4]);
    expect(await pumpAndTap(tester, selectedIndex: 0, tapLabel: 'Create'), [2]);
  });

  testWidgets('the action slot is never marked selected', (tester) async {
    // Even when told slot 2 is selected — which the shell will never do — the
    // create button must not render as a selected destination.
    await pumpAndTap(tester, selectedIndex: 2, tapLabel: 'Create');

    final wrappers = tester
        .widgetList<Semantics>(
          find.ancestor(of: find.text('Create'), matching: find.byType(Semantics)),
        )
        .toList();

    expect(
      wrappers.any((s) => s.properties.button ?? false),
      isTrue,
      reason: 'create slot should announce itself as a button',
    );
    expect(
      wrappers.any((s) => s.properties.selected ?? false),
      isFalse,
      reason: 'create is an action, so it can never be a selected destination',
    );
  });

  testWidgets('selected destination swaps to its filled icon', (tester) async {
    await pumpAndTap(tester, selectedIndex: 0, tapLabel: 'Home');
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsNothing);
    // Unselected destinations keep their outline icons.
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });

  testWidgets('mirrors in RTL without changing slot indices', (tester) async {
    // A plain Row is direction-aware, so Home stays slot 0 in both directions
    // while physically moving to the other side of the bar.
    final rtl = await pumpAndTap(
      tester,
      selectedIndex: 0,
      tapLabel: 'Home',
      direction: TextDirection.rtl,
    );
    final ltr = await pumpAndTap(
      tester,
      selectedIndex: 0,
      tapLabel: 'Home',
      direction: TextDirection.ltr,
    );
    expect(rtl, ltr);
    expect(rtl, [0]);
  });
}
