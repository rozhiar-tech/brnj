import 'package:brnj/app/theme/brnj_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The button themes must not force an infinite minimum width.
///
/// `Size.fromHeight(h)` reads like "height only" but is `Size(infinity, h)`.
/// A parent that bounds the width hides it; a Row does not, and the button
/// throws "BoxConstraints forces an infinite width" during layout. It shipped
/// once, in the plan editor's publish bar.
void main() {
  Future<void> pumpInRow(WidgetTester tester, Widget button) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BrnjTheme.light(),
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(child: Text('label')),
              button,
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('FilledButton lays out where width is unbounded', (tester) async {
    await pumpInRow(tester, FilledButton(onPressed: () {}, child: const Text('Go')));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(FilledButton)).width, lessThan(400));
  });

  testWidgets('OutlinedButton lays out where width is unbounded', (tester) async {
    await pumpInRow(tester, OutlinedButton(onPressed: () {}, child: const Text('Go')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('buttons still fill a stretched cross axis', (tester) async {
    // Full width has to remain achievable — it is the default treatment for a
    // primary action — it just has to come from the layout rather than from an
    // infinite minimum baked into the theme.
    await tester.pumpWidget(
      MaterialApp(
        theme: BrnjTheme.light(),
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [FilledButton(onPressed: () {}, child: const Text('Go'))],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(FilledButton)).width,
      tester.getSize(find.byType(Scaffold)).width,
    );
  });

  testWidgets('the themed height is still enforced', (tester) async {
    await pumpInRow(tester, FilledButton(onPressed: () {}, child: const Text('Go')));
    expect(tester.getSize(find.byType(FilledButton)).height, 52);
  });
}
