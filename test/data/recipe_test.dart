import 'package:brnj/data/models/recipe.dart';
import 'package:brnj/data/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const author = AuthorStub(uid: 'u1', name: 'أم علي');

  Recipe base({
    String title = 'دولمة',
    String? coverUrl = 'https://example.test/cover.jpg',
    List<Ingredient> ingredients = const [
      Ingredient(item: 'رز', quantity: 2, unit: Unit.istikan),
    ],
    List<RecipeStep> steps = const [RecipeStep(text: 'اغسل الرز')],
    int servings = 4,
  }) => Recipe(
    id: 'r1',
    author: author,
    title: title,
    language: 'ar',
    coverUrl: coverUrl,
    ingredients: ingredients,
    steps: steps,
    servings: servings,
  );

  group('publish gate', () {
    test('a complete recipe can publish', () {
      expect(base().canPublish, isTrue);
      expect(base().publishBlockers, isEmpty);
    });

    test('names every missing piece rather than just refusing', () {
      const empty = Recipe(id: '', author: author, title: '', language: 'ar');
      expect(
        empty.publishBlockers,
        containsAll(['title', 'cover', 'ingredients', 'steps']),
      );
    });

    test('a cover is required — nobody cooks what they cannot see', () {
      expect(base(coverUrl: null).publishBlockers, ['cover']);
    });

    test('whitespace-only steps do not count as steps', () {
      expect(
        base(steps: const [RecipeStep(text: '   ')]).publishBlockers,
        ['steps'],
      );
    });
  });

  group('servings scaler', () {
    test('doubles quantities when servings double', () {
      final scaled = base().ingredientsFor(8);
      expect(scaled.single.quantity, 4);
      expect(scaled.single.unit, Unit.istikan);
    });

    test('halves them going the other way', () {
      expect(base().ingredientsFor(2).single.quantity, 1);
    });

    test('returns the original list untouched at the original count', () {
      // Same instance, not a rescaled copy: the detail screen calls this on
      // every rebuild, and multiplying by 1.0 would both allocate and risk
      // drifting the value through repeated floating-point round trips.
      final recipe = base();
      expect(identical(recipe.ingredientsFor(4), recipe.ingredients), isTrue);
      expect(recipe.ingredientsFor(4).single.quantity, 2);
    });

    test('quantity-less ingredients survive scaling unchanged', () {
      // "salt, to taste" must not become "2x to taste".
      final recipe = base(
        ingredients: const [Ingredient(item: 'ملح', unit: Unit.toTaste)],
      );
      expect(recipe.ingredientsFor(20).single.quantity, isNull);
    });

    test('flags recipes where scaling is not purely linear', () {
      // Anything measured in pieces, or a long cook, needs a warning rather
      // than silent multiplication.
      expect(
        base(
          ingredients: const [Ingredient(item: 'بيض', quantity: 2, unit: Unit.piece)],
        ).hasNonLinearScaling,
        isTrue,
      );
    });
  });

  group('keywords', () {
    test('cover the title and every ingredient', () {
      final keywords = base().keywords;
      expect(keywords, contains('دولمه'));
      expect(keywords, contains('رز'));
    });
  });

  test('canonical grams convert local measures for shopping lists', () {
    const istikan = Ingredient(item: 'رز', quantity: 2, unit: Unit.istikan);
    expect(istikan.canonicalGrams, 200);
    // Pieces have no sensible mass, so they stay out of any merge.
    const eggs = Ingredient(item: 'بيض', quantity: 3, unit: Unit.piece);
    expect(eggs.canonicalGrams, isNull);
  });
}
