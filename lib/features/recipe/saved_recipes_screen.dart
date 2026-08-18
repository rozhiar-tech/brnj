import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../data/models/recipe.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/error_view.dart';
import '../../shared/recipe_card.dart';

/// Recipes this person saved.
///
/// Saves live under the user rather than the recipe precisely so this screen
/// is one query, and it is the query that actually gets run — people return to
/// what they meant to cook far more often than they browse.
final _savedRecipesProvider = FutureProvider<List<Recipe>>((ref) async {
  final ids = ref.watch(savedRecipeIdsProvider).value ?? const <String>[];
  if (ids.isEmpty) return const [];

  final repository = ref.watch(recipeRepositoryProvider);
  final recipes = await repository.byIds(ids);

  // byIds returns documents in whatever order Firestore hands them back;
  // the saved list is ordered by when you saved it, which is the order that
  // means something.
  final position = {for (var i = 0; i < ids.length; i++) ids[i]: i};
  recipes.sort((a, b) => (position[a.id] ?? 0).compareTo(position[b.id] ?? 0));
  return recipes;
});

class SavedRecipesScreen extends ConsumerWidget {
  const SavedRecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileSaved)),
      body: ref
          .watch(_savedRecipesProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                ErrorView(where: 'saved recipes', error: error),
            data: (recipes) {
              if (recipes.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.xxl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bookmark_border,
                          size: 40,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: Gap.md),
                        Text(
                          l10n.savedEmpty,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: Gap.lg),
                        OutlinedButton(
                          onPressed: () => context.go('/'),
                          child: Text(l10n.feedDiscover),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(Gap.lg),
                itemCount: recipes.length,
                separatorBuilder: (_, _) => const SizedBox(height: Gap.lg),
                itemBuilder: (context, i) =>
                    RecipeCard(recipe: recipes[i], numerals: numerals),
              );
            },
          ),
    );
  }
}
