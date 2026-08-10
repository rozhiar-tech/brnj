import 'package:brnj/core/search_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeForSearch', () {
    test('folds Arabic hamza forms onto bare alef', () {
      expect(normalizeForSearch('أرز'), normalizeForSearch('ارز'));
      expect(normalizeForSearch('إمام'), normalizeForSearch('امام'));
      expect(normalizeForSearch('آيس'), normalizeForSearch('ايس'));
    });

    test('folds ta marbuta onto ha', () {
      expect(normalizeForSearch('دولمة'), normalizeForSearch('دولمه'));
    });

    test('strips tashkeel and tatweel', () {
      expect(normalizeForSearch('كُبَّة'), normalizeForSearch('كبة'));
      expect(normalizeForSearch('كــبة'), normalizeForSearch('كبة'));
    });

    test('folds Arabic-Indic digits to Latin so ١٢ matches 12', () {
      expect(normalizeForSearch('١٢ شخص'), normalizeForSearch('12 شخص'));
    });

    test('Arabic and Kurdish scripts fold in opposite directions', () {
      // Arabic content collapses toward ك / ي.
      expect(
        normalizeForSearch('کوردی', script: SearchScript.arabic),
        'كوردي',
      );
      // Kurdish content collapses toward ک / ی — the inverse. Running the
      // Arabic table over Kurdish text would destroy the distinction.
      expect(
        normalizeForSearch('كوردي', script: SearchScript.kurdish),
        'کوردی',
      );
    });

    test('is idempotent', () {
      const input = 'دُولْمَة بَغْدادية ١٢';
      final once = normalizeForSearch(input);
      expect(normalizeForSearch(once), once);
    });

    test('collapses punctuation and whitespace', () {
      expect(normalizeForSearch('  تمن،  وقيمة!! '), 'تمن وقيمه');
    });
  });

  group('searchKeywords', () {
    test('emits the word plus 3+ character prefixes', () {
      final tokens = searchKeywords('دولمة');
      expect(tokens, contains('دولمه'));
      expect(tokens, contains('دول'));
      expect(tokens, contains('دولم'));
      expect(tokens, isNot(contains('دو'))); // prefixes start at 3
    });

    test('drops stopwords after normalising them', () {
      // "طريقة" normalises to "طريقه", so the stopword list has to be folded
      // with the same function or it silently never matches.
      final tokens = searchKeywords('طريقة عمل الدولمة');
      expect(tokens, isNot(contains('طريقه')));
      expect(tokens, isNot(contains('عمل')));
    });

    test('indexes both the article-prefixed and bare Arabic forms', () {
      // "الدولمة" and "دولمة" are the same dish, so searching either finds it.
      final tokens = searchKeywords('الدولمة');
      expect(tokens, contains('الدولمه'));
      expect(tokens, contains('دولمه'));
      expect(tokens, containsAll(searchQueryTokens('دولمة')));
    });

    test('caps the token count so the index stays bounded', () {
      final tokens = searchKeywords(List.filled(50, 'باذنجان').join(' '), maxTokens: 20);
      expect(tokens.length, lessThanOrEqualTo(20));
    });
  });

  group('searchQueryTokens', () {
    test('query tokens carry no prefixes — the stored side has them', () {
      final tokens = searchQueryTokens('دولمة');
      expect(tokens, ['دولمه']);
    });

    test('caps at 30, the arrayContainsAny limit', () {
      final query = List.generate(60, (i) => 'كلمه$i').join(' ');
      expect(searchQueryTokens(query).length, 30);
    });

    test('a query matches keywords stored from the recipe title', () {
      final stored = searchKeywords('دولمة بغدادية بدبس الرمان');
      for (final token in searchQueryTokens('دولمه')) {
        expect(stored, contains(token));
      }
      // Prefix search: typing three letters finds the dish.
      expect(stored, containsAll(searchQueryTokens('بغد').map((t) => t)));
    });
  });
}
