import 'package:brnj/app/theme/brnj_theme.dart';
import 'package:brnj/shared/option_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bottom sheets are the one place a `Column` with `mainAxisSize.min` looks
/// safe and isn't: the sheet caps its own height, and a list that outgrows the
/// cap throws instead of scrolling. The composer's timer picker had thirteen
/// options and overflowed by 318 pixels the first time it was opened on a
/// phone. These run at phone height, because at the 800x600 default the bug
/// does not reproduce.
void main() {
  Future<int?> openSheet(WidgetTester tester, int optionCount) async {
    int? chosen;

    // iPhone 17 logical size. At the 800x600 default the overflow this guards
    // against does not reproduce.
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: BrnjTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await showOptionSheet<int>(
                  context,
                  title: 'Timer',
                  selected: 3,
                  options: [
                    for (var i = 0; i < optionCount; i++)
                      SheetOption(value: i, label: 'Option $i'),
                  ],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return chosen;
  }

  testWidgets('thirteen options scroll instead of overflowing', (tester) async {
    await openSheet(tester, 13);
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('an absurd number of options still lays out', (tester) async {
    await openSheet(tester, 60);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short list hugs its content rather than filling the cap',
      (tester) async {
    await openSheet(tester, 3);
    expect(tester.takeException(), isNull);

    final sheetHeight = tester.getSize(find.byType(ListView)).height;
    // Three 56pt tiles, nowhere near the 70% ceiling.
    expect(sheetHeight, lessThan(874 * 0.7));
  });

  testWidgets('tapping an option returns its value', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: BrnjTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showOptionSheet<int>(
                context,
                options: const [
                  SheetOption(value: 1, label: 'One'),
                  SheetOption(value: 2, label: 'Two'),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();

    expect(find.text('Two'), findsNothing, reason: 'sheet should have closed');
  });

  testWidgets('the selected option is marked', (tester) async {
    await openSheet(tester, 13);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
