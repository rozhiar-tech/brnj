import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/brnj_theme.dart';
import '../../data/models/recipe.dart';
import '../../data/models/weekly_plan.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';

/// Picks a dish for one day of the week.
///
/// The order of the options is the whole design. Typing a name is at the top
/// and always available, because most dishes people cook are not written up as
/// recipes and never will be — forcing every entry to be a linked recipe would
/// leave the week empty. Saved recipes come next, since a plan is usually
/// assembled from things you already meant to cook. Search is last.
Future<PlanEntry?> showAddDishSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<PlanEntry>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _AddDishSheet(),
  );
}

class _AddDishSheet extends ConsumerStatefulWidget {
  const _AddDishSheet();

  @override
  ConsumerState<_AddDishSheet> createState() => _AddDishSheetState();
}

class _AddDishSheetState extends ConsumerState<_AddDishSheet> {
  final _controller = TextEditingController();
  MealType _mealType = MealType.lunch;
  List<Recipe> _results = const [];
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitFreeText() {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(context, PlanEntry(title: title, mealType: _mealType));
  }

  void _pickRecipe(Recipe recipe) {
    Navigator.pop(
      context,
      PlanEntry(
        title: recipe.title,
        recipeId: recipe.id,
        mealType: _mealType,
        photoUrl: recipe.coverUrl,
      ),
    );
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _searching = true);
    final results = await ref.read(recipeRepositoryProvider).search(query);
    if (mounted) {
      setState(() {
        _results = results;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final savedIds = ref.watch(savedRecipeIdsProvider).value ?? const [];

    return Padding(
      padding: EdgeInsets.only(
        left: Gap.lg,
        right: Gap.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Gap.lg,
      ),
      // The keyboard is open the whole time this sheet is used, so the height
      // has to come out of what is left rather than out of the full screen.
      child: SizedBox(
        height:
            (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom) *
            0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: _search,
              onSubmitted: (_) => _submitFreeText(),
              decoration: InputDecoration(
                hintText: l10n.planAddDish,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _submitFreeText,
                  icon: const Icon(Icons.check),
                  tooltip: l10n.planAddDish,
                ),
              ),
            ),
            const SizedBox(height: Gap.md),

            // Ramadan weeks need suhoor and iftar to be first-class, not
            // squeezed into "breakfast" and "dinner".
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final type in MealType.values)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: Gap.sm),
                      child: ChoiceChip(
                        label: Text(_mealLabel(l10n, type)),
                        selected: _mealType == type,
                        onSelected: (_) => setState(() => _mealType = type),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Gap.md),

            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isNotEmpty
                  ? _RecipeList(recipes: _results, onPick: _pickRecipe)
                  : _SavedRecipes(savedIds: savedIds, onPick: _pickRecipe),
            ),

            if (_controller.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Gap.sm),
                child: FilledButton(
                  onPressed: _submitFreeText,
                  child: Text(
                    l10n.planAddNamed(_controller.text.trim()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _mealLabel(AppLocalizations l10n, MealType type) => switch (type) {
    MealType.lunch => l10n.mealLunch,
    MealType.dinner => l10n.mealDinner,
    MealType.breakfast => l10n.mealBreakfast,
    MealType.suhoor => l10n.mealSuhoor,
    MealType.iftar => l10n.mealIftar,
  };
}

class _SavedRecipes extends ConsumerWidget {
  const _SavedRecipes({required this.savedIds, required this.onPick});

  final List<String> savedIds;
  final void Function(Recipe) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (savedIds.isEmpty) {
      return Center(
        child: Text(
          l10n.planPickerEmpty,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }

    return FutureBuilder<List<Recipe>>(
      future: ref.read(recipeRepositoryProvider).byIds(savedIds),
      builder: (context, snapshot) {
        final recipes = snapshot.data;
        if (recipes == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return _RecipeList(recipes: recipes, onPick: onPick);
      },
    );
  }
}

class _RecipeList extends StatelessWidget {
  const _RecipeList({required this.recipes, required this.onPick});

  final List<Recipe> recipes;
  final void Function(Recipe) onPick;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: recipes.length,
      itemBuilder: (context, i) {
        final recipe = recipes[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.restaurant, size: 20),
          ),
          title: Text(
            recipe.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(recipe.author.name),
          onTap: () => onPick(recipe),
        );
      },
    );
  }
}
