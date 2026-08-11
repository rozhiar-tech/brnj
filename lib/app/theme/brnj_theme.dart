import 'package:flutter/material.dart';

import 'brnj_colors.dart';

/// The one font family the app uses. Arabic, Sorani, and Badini all render
/// from this face, so Kurdish letters (ڵ ڕ ۆ ێ گ چ پ ژ) are drawn properly
/// rather than falling back to a face that doesn't have them.
///
/// Declared in pubspec.yaml at weights 400/500/600/700 — the four the type
/// scale uses. Unused weights are not bundled, since every declared face ships
/// in the binary whether anything references it or not.
const String kAppFontFamily = 'PlexArabic';

abstract final class BrnjTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;

    final ground = isLight ? BrnjColors.slip : BrnjColors.nightGround;
    final raised = isLight ? BrnjColors.slipRaised : BrnjColors.nightRaised;
    final onGround = isLight ? BrnjColors.ink : BrnjColors.nightInk;
    final muted = isLight ? BrnjColors.inkMuted : BrnjColors.nightInkMuted;
    final hairline = isLight ? BrnjColors.hairline : BrnjColors.nightHairline;
    final accent = isLight ? BrnjColors.glaze : BrnjColors.glazeLight;
    final brass = isLight ? BrnjColors.brass : BrnjColors.brassLight;
    final danger = isLight ? BrnjColors.pomegranate : BrnjColors.pomegranateLight;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: isLight ? Colors.white : BrnjColors.nightGround,
      primaryContainer: isLight ? const Color(0xFFDCEBE9) : const Color(0xFF16302E),
      onPrimaryContainer: isLight ? const Color(0xFF06322F) : BrnjColors.glazeLight,
      secondary: brass,
      onSecondary: isLight ? Colors.white : BrnjColors.nightGround,
      secondaryContainer: isLight ? const Color(0xFFF6EDD8) : const Color(0xFF35290F),
      onSecondaryContainer: isLight ? const Color(0xFF4A340A) : BrnjColors.brassLight,
      error: danger,
      onError: isLight ? Colors.white : BrnjColors.nightGround,
      surface: ground,
      onSurface: onGround,
      surfaceContainerLowest: isLight ? BrnjColors.slipRaised : BrnjColors.nightSunken,
      surfaceContainer: raised,
      surfaceContainerHighest: isLight ? BrnjColors.slipSunken : const Color(0xFF262119),
      onSurfaceVariant: muted,
      outline: hairline,
      outlineVariant: hairline,
    );

    final baseText = (isLight ? Typography.blackMountainView : Typography.whiteMountainView)
        .apply(fontFamily: kAppFontFamily);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: ground,
      fontFamily: kAppFontFamily,
      textTheme: baseText.copyWith(
        headlineSmall: baseText.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          height: 1.25,
        ),
        titleMedium: baseText.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        // Arabic and Kurdish scripts need more line height than Latin or the
        // descenders collide with the line below.
        bodyLarge: baseText.bodyLarge?.copyWith(height: 1.55),
        bodyMedium: baseText.bodyMedium?.copyWith(height: 1.55),
        labelLarge: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: ground,
        surfaceTintColor: Colors.transparent,
        foregroundColor: onGround,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: baseText.titleLarge?.copyWith(
          color: onGround,
          fontWeight: FontWeight.w600,
          fontFamily: kAppFontFamily,
        ),
      ),
      cardTheme: CardThemeData(
        color: raised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: hairline),
        ),
      ),
      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        side: BorderSide(color: hairline),
        labelStyle: baseText.labelMedium?.copyWith(color: muted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      // Height is themed; width is the layout's business.
      //
      // `Size.fromHeight(52)` looks like it only sets height, but it is
      // `Size(double.infinity, 52)` — an infinite *minimum width*. That is
      // harmless wherever the parent bounds the width (a Column, a ListView),
      // and it throws the moment a button lands somewhere width is unbounded,
      // such as a Row. Callers that want a full-width button say so with a
      // stretched cross axis or a SizedBox.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          side: BorderSide(color: hairline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? BrnjColors.slipRaised : BrnjColors.nightSunken,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          baseText.labelSmall?.copyWith(fontFamily: kAppFontFamily),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      // Page transitions are left at the Material defaults: since Flutter 3.44
      // those are predictive-back on Android and Cupertino on iOS, which is
      // exactly what an override would have specified.
    );
  }
}

/// Spacing scale. Stay on it.
abstract final class Gap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}
