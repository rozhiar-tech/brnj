import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/numerals.dart';
import 'localization.dart';

/// Device-local preferences. Deliberately not in Firestore: these must work
/// before sign-in, offline, and for guests.
class AppSettings {
  const AppSettings({
    this.locale,
    this.numeralStyleOverride,
    this.dataSaver = false,
  });

  /// Null means "follow the device", resolved by [resolveLocale].
  final AppLocale? locale;

  /// Null means "follow the locale" — ١٢٣ for Arabic, 123 for Kurdish and
  /// English. Users who want the other one can say so.
  final NumeralStyle? numeralStyleOverride;

  /// Pins feeds to the 400px image variant and stops anything autoplaying.
  /// Assume mobile data on a limited bundle.
  final bool dataSaver;

  NumeralStyle numeralStyleFor(AppLocale active) =>
      numeralStyleOverride ??
      (active.prefersArabicNumeralsByDefault
          ? NumeralStyle.arabicIndic
          : NumeralStyle.latin);

  AppSettings copyWith({
    AppLocale? locale,
    NumeralStyle? numeralStyleOverride,
    bool? dataSaver,
    bool clearLocale = false,
    bool clearNumerals = false,
  }) => AppSettings(
    locale: clearLocale ? null : (locale ?? this.locale),
    numeralStyleOverride:
        clearNumerals ? null : (numeralStyleOverride ?? this.numeralStyleOverride),
    dataSaver: dataSaver ?? this.dataSaver,
  );
}

const _kLocale = 'settings.locale';
const _kNumerals = 'settings.numerals';
const _kDataSaver = 'settings.dataSaver';

/// Overridden in main() with the instance loaded before the first frame, so
/// the app never renders in the wrong language and then flips.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override in main()'),
);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final localeCode = prefs.getString(_kLocale);
    final numerals = prefs.getString(_kNumerals);

    return AppSettings(
      locale: localeCode == null ? null : AppLocale.fromCode(localeCode),
      numeralStyleOverride: numerals == null
          ? null
          : NumeralStyle.values.firstWhere(
              (n) => n.name == numerals,
              orElse: () => NumeralStyle.latin,
            ),
      dataSaver: prefs.getBool(_kDataSaver) ?? false,
    );
  }

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  Future<void> setLocale(AppLocale? locale) async {
    state = state.copyWith(locale: locale, clearLocale: locale == null);
    if (locale == null) {
      await _prefs.remove(_kLocale);
    } else {
      await _prefs.setString(_kLocale, locale.locale.languageCode);
    }
  }

  Future<void> setNumeralStyle(NumeralStyle? style) async {
    state = state.copyWith(numeralStyleOverride: style, clearNumerals: style == null);
    if (style == null) {
      await _prefs.remove(_kNumerals);
    } else {
      await _prefs.setString(_kNumerals, style.name);
    }
  }

  Future<void> setDataSaver(bool enabled) async {
    state = state.copyWith(dataSaver: enabled);
    await _prefs.setBool(_kDataSaver, enabled);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// The locale actually in effect, after falling back to the device.
final activeLocaleProvider = Provider<AppLocale>((ref) {
  final chosen = ref.watch(settingsProvider).locale;
  if (chosen != null) return chosen;

  final device = WidgetsBinding.instance.platformDispatcher.locales;
  return AppLocale.fromCode(
    resolveLocale(device, AppLocale.supported)?.languageCode,
  );
});

/// Which digits to draw. Read this rather than reaching for the locale.
final numeralStyleProvider = Provider<NumeralStyle>((ref) {
  final settings = ref.watch(settingsProvider);
  return settings.numeralStyleFor(ref.watch(activeLocaleProvider));
});
