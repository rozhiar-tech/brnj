/**
 * Arabic and Kurdish search normalisation — the server-side twin of
 * lib/core/search_text.dart.
 *
 * These two implementations have to agree exactly, because one builds the
 * stored `keywords` array and the other builds the query tokens. Rather than
 * trust two hand-written copies to stay in step, `keywordsOnRecipeWrite` below
 * recomputes keywords on the server for every recipe, so the Dart copy only
 * ever has to be right about the *query* side. That also means recipes written
 * by the seed importer — which never runs Dart — are searchable.
 */

const TASHKEEL = new Set([
  'ؐ', 'ؑ', 'ؒ', 'ؓ', 'ؔ', 'ؕ', 'ؖ',
  'ؗ', 'ؘ', 'ؙ', 'ؚ',
  'ً', 'ٌ', 'ٍ', 'َ', 'ُ', 'ِ', 'ّ',
  'ْ', 'ٓ', 'ٔ', 'ٕ', 'ٖ', 'ٗ', '٘',
  'ٙ', 'ٚ', 'ٛ', 'ٜ', 'ٝ', 'ٞ', 'ٟ',
  'ٰ',
  'ـ', // tatweel
]);

const DIGITS: Record<string, string> = {
  '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
  '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
  '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
  '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
};

const COMMON: Record<string, string> = {
  'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا',
  'ة': 'ه',
  'ؤ': 'ء', 'ئ': 'ء',
};

/** Arabic content collapses toward the Arabic letterforms. */
const ARABIC: Record<string, string> = { 'ک': 'ك', 'ی': 'ي', 'ى': 'ي', 'ھ': 'ه' };

/** Kurdish collapses the other way — running the Arabic table over Kurdish
 *  destroys the distinction between ی and ي. */
const KURDISH: Record<string, string> = { 'ك': 'ک', 'ي': 'ی', 'ى': 'ی' };

const STOPWORDS = [
  'من', 'في', 'على', 'مع', 'الى', 'الي', 'او', 'و', 'ال', 'هذا', 'هذه',
  'طريقة', 'عمل', 'وصفة', 'اكلة', 'طبخ',
  'لە', 'بۆ', 'وە', 'یان', 'ڕێسەت', 'چێشت', 'دروستکردن',
  'the', 'a', 'an', 'of', 'for', 'with', 'and', 'or', 'to', 'in',
  'recipe', 'how', 'make', 'best', 'easy',
];

export type Script = 'arabic' | 'kurdish' | 'latin';

export function scriptForLanguage(language: string): Script {
  if (language === 'ckb' || language === 'kmr' || language === 'ku') return 'kurdish';
  if (language === 'ar') return 'arabic';
  return 'latin';
}

export function normalize(input: string, script: Script = 'arabic'): string {
  const folding = {
    ...COMMON,
    ...DIGITS,
    ...(script === 'kurdish' ? KURDISH : ARABIC),
  };

  let out = '';
  for (const ch of input.toLowerCase()) {
    if (TASHKEEL.has(ch)) continue;
    out += folding[ch] ?? ch;
  }

  return out
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

const stopwordsFor = (script: Script) =>
  new Set(STOPWORDS.map((w) => normalize(w, script)));

/**
 * Words plus every 3+ character prefix, so typing "دول" finds "دولمة", and
 * both the article-prefixed and bare Arabic forms, so "الدولمة" and "دولمة"
 * are the same dish.
 */
export function searchKeywords(
  text: string,
  script: Script = 'arabic',
  maxTokens = 60,
): string[] {
  const normalized = normalize(text, script);
  if (!normalized) return [];

  const stop = stopwordsFor(script);
  const tokens = new Set<string>();

  const addWithPrefixes = (word: string) => {
    tokens.add(word);
    for (let i = 3; i < word.length; i++) tokens.add(word.slice(0, i));
  };

  for (const word of normalized.split(' ')) {
    if (word.length < 2 || stop.has(word)) continue;
    addWithPrefixes(word);

    if (word.length > 4 && word.startsWith('ال')) {
      const bare = word.slice(2);
      if (!stop.has(bare)) addWithPrefixes(bare);
    }
  }

  return [...tokens].slice(0, maxTokens);
}

/** Everything a recipe should be findable by. */
export function keywordsForRecipe(data: FirebaseFirestore.DocumentData): string[] {
  const ingredients = Array.isArray(data.ingredients) ? data.ingredients : [];
  const tags = Array.isArray(data.tags) ? data.tags : [];

  const text = [
    data.title ?? '',
    data.description ?? '',
    ...tags,
    ...ingredients.map((i: { item?: string }) => i?.item ?? ''),
  ].join(' ');

  return searchKeywords(text, scriptForLanguage(data.language ?? 'ar'));
}
