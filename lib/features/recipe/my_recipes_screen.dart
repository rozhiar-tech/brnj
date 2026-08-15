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

/// Everything this person has written, drafts first.
///
/// Drafts lead because an unfinished recipe is the one thing on this screen
/// that still wants something from you.
class MyRecipesScreen extends ConsumerWidget {
  const MyRecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);
    final recipesAsync = ref.watch(myRecipesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileMyRecipes)),
      body: recipesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(myRecipesProvider),
        ),
        data: (recipes) {
          if (recipes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.feedEmpty,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Gap.lg),
                    FilledButton(
                      onPressed: () => context.push('/create/recipe'),
                      child: Text(l10n.createRecipe),
                    ),
                  ],
                ),
              ),
            );
          }

          final drafts = recipes
              .where((r) => r.status == RecipeStatus.draft)
              .toList();
          final published = recipes
              .where((r) => r.status != RecipeStatus.draft)
              .toList();

          return ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              if (drafts.isNotEmpty) ...[
                _SectionLabel(l10n.recipeDrafts),
                for (final draft in drafts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.md),
                    child: RecipeCard(
                      recipe: draft,
                      numerals: numerals,
                      // A draft opens back into the composer, not the reader.
                      onTap: () => context.push('/create/recipe/${draft.id}'),
                    ),
                  ),
                const SizedBox(height: Gap.lg),
              ],
              if (published.isNotEmpty) ...[
                _SectionLabel(l10n.recipePublished),
                for (final recipe in published)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.md),
                    child: RecipeCard(recipe: recipe, numerals: numerals),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
