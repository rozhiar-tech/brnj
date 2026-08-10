/// Digit rendering.
///
/// Iraqi Arabic readers generally expect Arabic-Indic digits (١٢٣); Kurdish
/// readers generally expect Latin (123). This follows the locale by default
/// with a manual override in settings.
///
/// Numeric *keyboards* stay Latin regardless — people type 123 even when they
/// read ١٢٣, and an Arabic-Indic keypad is a reliable source of complaints.
library;

enum NumeralStyle { latin, arabicIndic }

const _arabicIndicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

extension NumeralFormatting on String {
  /// Converts Latin digits in this string to [style]. Leaves everything else
  /// alone, so it is safe to run over a whole formatted string.
  String toNumeralStyle(NumeralStyle style) {
    if (style == NumeralStyle.latin) return _toLatinDigits();
    return splitMapJoin(
      RegExp(r'[0-9]'),
      onMatch: (m) => _arabicIndicDigits[int.parse(m[0]!)],
      onNonMatch: (s) => s,
    );
  }

  String _toLatinDigits() {
    var out = this;
    for (var i = 0; i < 10; i++) {
      out = out.replaceAll(_arabicIndicDigits[i], '$i');
    }
    return out;
  }
}

/// Formats a quantity for an ingredient row: drops a trailing `.0`, keeps at
/// most two decimals, and renders common fractions as fractions because that
/// is how recipes are written — "نص كوب", not "0.5 كوب".
String formatQuantity(double value, {NumeralStyle style = NumeralStyle.latin}) {
  const fractions = <(double, String)>[
    (0.25, '¼'),
    (0.33, '⅓'),
    (0.5, '½'),
    (0.67, '⅔'),
    (0.75, '¾'),
  ];

  final whole = value.truncate();
  final remainder = (value - whole).abs();

  String text;
  final fraction = fractions
      .where((f) => (remainder - f.$1).abs() < 0.02)
      .firstOrNull;

  if (fraction != null) {
    text = whole == 0 ? fraction.$2 : '$whole${fraction.$2}';
  } else if (remainder < 0.005) {
    text = '$whole';
  } else {
    text = value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  return text.toNumeralStyle(style);
}

/// Compact counts for stat strips: 1200 → "1.2k".
String formatCount(int value, {NumeralStyle style = NumeralStyle.latin}) {
  final text = switch (value) {
    < 1000 => '$value',
    < 10000 => '${(value / 1000).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}k',
    < 1000000 => '${(value / 1000).round()}k',
    _ => '${(value / 1000000).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}m',
  };
  return text.toNumeralStyle(style);
}
