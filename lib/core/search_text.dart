/// Text normalisation for Arabic and Kurdish search.
///
/// Firestore has no full-text search, so recipes carry a `keywords` array and
/// we query it with `arrayContainsAny`. That only works if the tokens written
/// at publish time and the tokens typed at query time are normalised
/// *identically* — hence one function, used by both sides.
///
/// The problems this solves:
///   • Arabic hamza forms are typed interchangeably: أ إ آ ٱ vs ا
///   • ة and ه, ى and ي are confused constantly
///   • tashkeel (harakat) and tatweel appear or don't, at random
///   • Kurdish uses ک and ی where Arabic uses ك and ي — the *same* codepoints
///     mean different letters, and Kurdish keyboards are inconsistent about it
library;

const _tashkeel = {
  'ؐ', 'ؑ', 'ؒ', 'ؓ', 'ؔ', 'ؕ', 'ؖ',
  'ؗ', 'ؘ', 'ؙ', 'ؚ',
  'ً', 'ٌ', 'ٍ', 'َ', 'ُ', 'ِ', 'ّ',
  'ْ', 'ٓ', 'ٔ', 'ٕ', 'ٖ', 'ٗ', '٘',
  'ٙ', 'ٚ', 'ٛ', 'ٜ', 'ٝ', 'ٞ', 'ٟ',
  'ٰ',
  'ـ', // tatweel / kashida
};

/// Arabic-Indic and Eastern Arabic-Indic digits → Latin, so "١٢" and "12" match.
const _digitFolding = {
  '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
  '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
  '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
  '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
};

/// Shared folding: applied to every language.
const _commonFolding = {
  'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا',
  'ة': 'ه',
  'ؤ': 'ء', 'ئ': 'ء',
};

/// Arabic content collapses toward the Arabic letterforms.
const _arabicFolding = {'ک': 'ك', 'ی': 'ي', 'ى': 'ي', 'ھ': 'ه'};

/// Kurdish content collapses the other way — toward the Kurdish letterforms.
/// Note this is deliberately the *inverse* of [_arabicFolding]; running the
/// Arabic rules over Kurdish text destroys the distinction between ی and ي.
const _kurdishFolding = {'ك': 'ک', 'ي': 'ی', 'ى': 'ی', 'ه‌': 'ە'};

/// Words too common to be worth indexing.
const _stopwords = {
  // Arabic
  'من', 'في', 'على', 'مع', 'الى', 'الي', 'او', 'و', 'ال', 'هذا', 'هذه',
  'طريقة', 'عمل', 'وصفة', 'اكلة', 'طبخ',
  // Kurdish
  'لە', 'بۆ', 'وە', 'یان', 'ڕێسەت', 'چێشت', 'دروستکردن',
  // English
  'the', 'a', 'an', 'of', 'for', 'with', 'and', 'or', 'to', 'in',
  'recipe', 'how', 'make', 'best', 'easy',
};

/// Which folding table to use. Content language, not UI language.
enum SearchScript { arabic, kurdish, latin }

SearchScript scriptForLanguage(String languageCode) => switch (languageCode) {
  'ckb' || 'kmr' || 'ku' => SearchScript.kurdish,
  'ar' => SearchScript.arabic,
  _ => SearchScript.latin,
};

/// Normalises a string for indexing or querying. Idempotent.
String normalizeForSearch(String input, {SearchScript script = SearchScript.arabic}) {
  final buffer = StringBuffer();
  final folding = {
    ..._commonFolding,
    ..._digitFolding,
    if (script == SearchScript.kurdish) ..._kurdishFolding else ..._arabicFolding,
  };

  for (final char in input.toLowerCase().characters) {
    if (_tashkeel.contains(char)) continue;
    buffer.write(folding[char] ?? char);
  }

  // Anything that isn't a letter or digit becomes a separator.
  return buffer
      .toString()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// Stopwords have to be compared *after* normalisation, or they never match:
/// "طريقة" normalises to "طريقه", which isn't the string in the list. Cached
/// per script because the two scripts fold in opposite directions.
final Map<SearchScript, Set<String>> _normalizedStopwords = {};

Set<String> _stopwordsFor(SearchScript script) => _normalizedStopwords.putIfAbsent(
  script,
  () => {for (final word in _stopwords) normalizeForSearch(word, script: script)},
);

/// Arabic glues the definite article onto the noun, so "الدولمة" and "دولمة"
/// are the same dish and have to produce overlapping tokens. Both forms get
/// indexed rather than only the stripped one — stripping is a guess ("ألوان"
/// is not "ال" + "وان"), and indexing both makes a wrong guess harmless.
String? _withoutDefiniteArticle(String word) {
  if (word.length > 4 && word.startsWith('ال')) return word.substring(2);
  return null;
}

/// Tokens to store in a document's `keywords` array.
///
/// Includes every word plus every prefix of 3+ characters, so typing "دول"
/// finds "دولمة". Prefixes are the reason this works without a search service;
/// they're also why the array must be capped — Firestore indexes every entry.
List<String> searchKeywords(
  String text, {
  SearchScript script = SearchScript.arabic,
  int maxTokens = 60,
}) {
  final normalized = normalizeForSearch(text, script: script);
  if (normalized.isEmpty) return const [];

  final stopwords = _stopwordsFor(script);
  final tokens = <String>{};

  void addWithPrefixes(String word) {
    tokens.add(word);
    for (var i = 3; i < word.length; i++) {
      tokens.add(word.substring(0, i));
    }
  }

  for (final word in normalized.split(' ')) {
    if (word.length < 2 || stopwords.contains(word)) continue;
    addWithPrefixes(word);

    final bare = _withoutDefiniteArticle(word);
    if (bare != null && !stopwords.contains(bare)) addWithPrefixes(bare);
  }
  return tokens.take(maxTokens).toList(growable: false);
}

/// Tokens to send in a query. No prefixes — the stored side already has them.
///
/// Capped at 30 because that is Firestore's `arrayContainsAny` limit.
List<String> searchQueryTokens(String query, {SearchScript script = SearchScript.arabic}) {
  final normalized = normalizeForSearch(query, script: script);
  if (normalized.isEmpty) return const [];
  final stopwords = _stopwordsFor(script);
  return normalized
      .split(' ')
      .where((w) => w.length >= 2 && !stopwords.contains(w))
      .take(30)
      .toList(growable: false);
}

extension on String {
  /// Grapheme-naive but correct for the scripts we handle: Arabic combining
  /// marks are filtered by codepoint above, so splitting on runes is safe.
  Iterable<String> get characters => runes.map(String.fromCharCode);
}
