import 'package:brnj/app/theme/brnj_theme.dart';
import 'package:brnj/shared/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The initial has to stay inside its circle at every size the app uses it at.
///
/// It did not: the type was a fixed headline regardless of radius, so at the
/// 12pt radius the comment list uses, the glyph was wider than the circle and
/// sat visibly low — an Arabic ط made it obvious.
void main() {
  Future<void> pump(WidgetTester tester, {required double radius, required String name}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: BrnjTheme.light(),
        home: Scaffold(
          body: Center(
            child: ProfileAvatar(photoUrl: null, name: name, radius: radius),
          ),
        ),
      ),
    );
  }

  // Every radius the app actually passes.
  for (final radius in [12.0, 14.0, 18.0, 20.0, 44.0]) {
    testWidgets('the initial fits a $radius circle', (tester) async {
      await pump(tester, radius: radius, name: 'rozhyar');
      expect(tester.takeException(), isNull);

      final circle = tester.getSize(find.byType(ProfileAvatar));
      expect(circle.width, radius * 2);
      expect(circle.height, radius * 2);

      // The type has to scale with the circle. A fixed size — which is what
      // shipped — is smaller than the circle at radius 44 and larger than it
      // at radius 12, and only the small end looks broken.
      final style = tester.widget<Text>(find.byType(Text)).style!;
      expect(style.fontSize, fontSizeFor(radius));
      expect(
        style.fontSize!,
        lessThan(circle.height),
        reason: 'the glyph would be taller than the circle holding it',
      );
    });
  }

  testWidgets('a tall Arabic glyph also fits', (tester) async {
    // ط is taller than a Latin letter at the same point size, which is what
    // exposed the original bug.
    await pump(tester, radius: 12, name: 'طباخ BOXo');
    expect(tester.takeException(), isNull);

    final circle = tester.getSize(find.byType(ProfileAvatar));
    final glyph = tester.getSize(find.byType(Text));
    expect(glyph.height, lessThanOrEqualTo(circle.height));
    expect(glyph.width, lessThanOrEqualTo(circle.width));
    expect(find.text('ط'), findsOneWidget);
  });

  testWidgets('the glyph is centred in the circle', (tester) async {
    await pump(tester, radius: 20, name: 'rozhyar');
    final circle = tester.getCenter(find.byType(ProfileAvatar));
    final glyph = tester.getCenter(find.byType(Text));
    expect((glyph.dx - circle.dx).abs(), lessThan(1));
    expect((glyph.dy - circle.dy).abs(), lessThan(1));
  });

  testWidgets('an empty name still renders something', (tester) async {
    await pump(tester, radius: 20, name: '   ');
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('Latin initials are capitalised, Arabic is left alone',
      (tester) async {
    await pump(tester, radius: 20, name: 'rozhyar');
    expect(find.text('R'), findsOneWidget);

    await pump(tester, radius: 20, name: 'دولمة');
    expect(find.text('د'), findsOneWidget);
  });
}
