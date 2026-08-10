import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// The four locales Brnj ships in. Three of the four are right-to-left, so the
/// UI is built RTL-first and LTR is the special case.
enum AppLocale {
  arabic(Locale('ar'), 'العربية', TextDirection.rtl),
  sorani(Locale('ckb'), 'کوردی (سۆرانی)', TextDirection.rtl),
  badini(Locale('kmr'), 'کوردی (بادینی)', TextDirection.rtl),
  english(Locale('en'), 'English', TextDirection.ltr);

  const AppLocale(this.locale, this.nativeName, this.textDirection);

  final Locale locale;
  final String nativeName;
  final TextDirection textDirection;

  static const fallback = AppLocale.arabic;

  static List<Locale> get supported => [for (final l in values) l.locale];

  static AppLocale fromCode(String? code) => switch (code) {
    'ar' => arabic,
    'ckb' => sorani,
    'kmr' => badini,
    'en' => english,
    _ => fallback,
  };

  /// Which numeral system to render digits in by default. Iraqi Arabic readers
  /// expect ١٢٣; Kurdish readers generally expect 123. Overridable in settings.
  bool get prefersArabicNumeralsByDefault => this == arabic;
}

/// Flutter ships Material/Cupertino/Widgets translations for `ar` but not for
/// `ckb` or `kmr`, so the built-in delegates reject those locales and the app
/// throws at runtime. These delegates claim the Kurdish locales and serve the
/// Arabic bundles — same script, same direction, and every string they cover
/// (Cancel, OK, month names) is close enough to be right.
///
/// They must come *before* the Global* delegates in `localizationsDelegates`.
const _kurdishCodes = {'ckb', 'kmr', 'ku'};

class _KurdishMaterialDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _KurdishMaterialDelegate();
  @override
  bool isSupported(Locale locale) => _kurdishCodes.contains(locale.languageCode);
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('ar'));
  @override
  bool shouldReload(_) => false;
}

class _KurdishCupertinoDelegate extends LocalizationsDelegate<CupertinoLocalizations> {
  const _KurdishCupertinoDelegate();
  @override
  bool isSupported(Locale locale) => _kurdishCodes.contains(locale.languageCode);
  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('ar'));
  @override
  bool shouldReload(_) => false;
}

class _KurdishWidgetsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const _KurdishWidgetsDelegate();
  @override
  bool isSupported(Locale locale) => _kurdishCodes.contains(locale.languageCode);
  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(const Locale('ar'));
  @override
  bool shouldReload(_) => false;
}

const kurdishFallbackDelegates = <LocalizationsDelegate<Object>>[
  _KurdishMaterialDelegate(),
  _KurdishCupertinoDelegate(),
  _KurdishWidgetsDelegate(),
];

/// Resolves the device locale to one we actually ship, rather than letting
/// Flutter fall through to the first supported locale.
Locale? resolveLocale(List<Locale>? deviceLocales, Iterable<Locale> supported) {
  for (final device in deviceLocales ?? const <Locale>[]) {
    for (final candidate in supported) {
      if (candidate.languageCode == device.languageCode) return candidate;
    }
    // An Iraqi device set to any Kurdish variant should land on Sorani.
    if (_kurdishCodes.contains(device.languageCode)) return const Locale('ckb');
  }
  return AppLocale.fallback.locale;
}
