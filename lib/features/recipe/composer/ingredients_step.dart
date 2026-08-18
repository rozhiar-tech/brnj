import 'package:flutter/material.dart';

import '../../../app/theme/brnj_theme.dart';
import '../../../data/models/recipe.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'composer_labels.dart';

/// Step 2: what goes in.
///
/// Rows are quantity / unit / ingredient, reorderable, and grouped ("for the
/// filling", "for the sauce") because that is how Iraqi recipes are actually
/// written down. Each row can carry a substitution note — a recipe calling for
/// something you can't buy in Iraq is useless, and the note is where "no
/// mascarpone, qaimar works" lives.
class IngredientsStep extends StatelessWidget {
  const IngredientsStep({
    required this.recipe,
    required this.onChange,
    super.key,
  });

  final Recipe recipe;
  final void Function(Recipe Function(Recipe)) onChange;

  void _update(int index, Ingredient ingredient) {
    final list = [...recipe.ingredients]..[index] = ingredient;
    onChange((r) => r.copyWith(ingredients: list));
  }

  void _add() {
    onChange(
      (r) => r.copyWith(
        ingredients: [
          ...r.ingredients,
          const Ingredient(item: ''),
        ],
      ),
    );
  }

  void _remove(int index) {
    final list = [...recipe.ingredients]..removeAt(index);
    onChange((r) => r.copyWith(ingredients: list));
  }

  /// `onReorderItem` rather than the deprecated `onReorder`: it hands back an
  /// index already adjusted for the removed item, so the off-by-one dance the
  /// old callback required is gone.
  void _reorder(int oldIndex, int newIndex) {
    final list = [...recipe.ingredients];
    list.insert(newIndex, list.removeAt(oldIndex));
    onChange((r) => r.copyWith(ingredients: list));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: recipe.ingredients.isEmpty
              ? _Empty(message: l10n.composerIngredientsEmpty)
              : ReorderableListView.builder(
                  padding: const EdgeInsets.all(Gap.lg),
                  itemCount: recipe.ingredients.length,
                  onReorderItem: _reorder,
                  itemBuilder: (context, index) => _IngredientRow(
                    // The key must follow the row's identity, not its position,
                    // or reordering rebuilds the wrong text fields.
                    key: ValueKey(
                      'ingredient-$index-${recipe.ingredients.length}',
                    ),
                    ingredient: recipe.ingredients[index],
                    onChanged: (value) => _update(index, value),
                    onRemove: () => _remove(index),
                  ),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.composerAddIngredient),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (recipe.ingredients.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
            child: Text(
              l10n.composerScalingNote,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _IngredientRow extends StatefulWidget {
  const _IngredientRow({
    required this.ingredient,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final Ingredient ingredient;
  final ValueChanged<Ingredient> onChanged;
  final VoidCallback onRemove;

  @override
  State<_IngredientRow> createState() => _IngredientRowState();
}

class _IngredientRowState extends State<_IngredientRow> {
  late final _item = TextEditingController(text: widget.ingredient.item);
  late final _quantity = TextEditingController(
    text: widget.ingredient.quantity?.toString() ?? '',
  );
  late final _note = TextEditingController(text: widget.ingredient.note ?? '');
  late final _group = TextEditingController(
    text: widget.ingredient.group ?? '',
  );
  bool _expanded = false;

  @override
  void dispose() {
    _item.dispose();
    _quantity.dispose();
    _note.dispose();
    _group.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      Ingredient(
        item: _item.text,
        quantity: double.tryParse(_quantity.text),
        unit: widget.ingredient.unit,
        group: _group.text.trim().isEmpty ? null : _group.text.trim(),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        itemId: widget.ingredient.itemId,
        hardToFind: widget.ingredient.hardToFind,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: Gap.md),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: _quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textDirection: TextDirection.ltr,
                    onChanged: (_) => _emit(),
                    decoration: InputDecoration(
                      hintText: l10n.composerQuantityHint,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                _UnitPicker(
                  unit: widget.ingredient.unit,
                  onChanged: (unit) {
                    widget.onChanged(
                      Ingredient(
                        item: _item.text,
                        quantity: double.tryParse(_quantity.text),
                        unit: unit,
                        group: widget.ingredient.group,
                        note: widget.ingredient.note,
                        itemId: widget.ingredient.itemId,
                        hardToFind: widget.ingredient.hardToFind,
                      ),
                    );
                  },
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: TextField(
                    controller: _item,
                    onChanged: (_) => _emit(),
                    decoration: InputDecoration(
                      hintText: l10n.composerIngredientHint,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: Gap.sm),
              TextField(
                controller: _group,
                onChanged: (_) => _emit(),
                decoration: InputDecoration(
                  labelText: l10n.composerGroupLabel,
                  helperText: l10n.composerGroupHelp,
                  isDense: true,
                ),
              ),
              const SizedBox(height: Gap.sm),
              TextField(
                controller: _note,
                onChanged: (_) => _emit(),
                decoration: InputDecoration(
                  labelText: l10n.composerSubstituteLabel,
                  helperText: l10n.composerSubstituteHelp,
                  helperMaxLines: 2,
                  isDense: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnitPicker extends StatelessWidget {
  const _UnitPicker({required this.unit, required this.onChanged});

  final Unit unit;
  final ValueChanged<Unit> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DropdownButton<Unit>(
      value: unit,
      underline: const SizedBox.shrink(),
      isDense: true,
      onChanged: (value) => value == null ? null : onChanged(value),
      items: [
        for (final u in Unit.values)
          DropdownMenuItem(value: u, child: Text(unitLabel(l10n, u))),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xxl),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ),
    );
  }
}
