import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../core/numerals.dart';
import '../../data/models/recipe.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/error_view.dart';
import '../recipe/composer/composer_labels.dart';

/// One line on the list: an ingredient gathered from across the week.
class ShoppingLine {
  ShoppingLine({required this.item, required this.unit, this.quantity});

  final String item;
  final Unit unit;
  double? quantity;

  /// Entries that share a name and a *convertible* unit are added together.
  /// Two istikans of rice and three istikans of rice is five. Two eggs and
  /// "eggs, to taste" is not four of anything, so those stay as separate
  /// lines rather than inventing a number.
  bool canMergeWith(ShoppingLine other) =>
      item == other.item &&
      unit == other.unit &&
      unit.isConvertible &&
      quantity != null &&
      other.quantity != null;
}

/// Merges every linked recipe in a week into one list.
///
/// The most-requested feature in every recipe app ever built, and here it
/// falls out of the weekly plan almost for free — which is most of the reason
/// the plan exists.
List<ShoppingLine> buildShoppingList(List<Recipe> recipes) {
  final lines = <ShoppingLine>[];

  for (final recipe in recipes) {
    for (final ingredient in recipe.ingredients) {
      final line = ShoppingLine(
        item: ingredient.item.trim(),
        unit: ingredient.unit,
        quantity: ingredient.quantity,
      );
      if (line.item.isEmpty) continue;

      final existing = lines.where(line.canMergeWith).firstOrNull;
      if (existing != null) {
        existing.quantity = (existing.quantity ?? 0) + (line.quantity ?? 0);
      } else {
        lines.add(line);
      }
    }
  }

  lines.sort((a, b) => a.item.compareTo(b.item));
  return lines;
}

final _shoppingListProvider =
    FutureProvider.family<(List<ShoppingLine>, int), String>((ref, planId) async {
      final plan = await ref.watch(planRepositoryProvider).getPlan(planId);
      final ids = plan?.linkedRecipeIds ?? const <String>[];
      if (ids.isEmpty) return (const <ShoppingLine>[], 0);

      final recipes = await ref.watch(recipeRepositoryProvider).byIds(ids);
      return (buildShoppingList(recipes), recipes.length);
    });

class ShoppingListScreen extends ConsumerStatefulWidget {
  const ShoppingListScreen({required this.planId, super.key});

  final String planId;

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  /// Ticked items, in memory. A shopping list is for one trip — carrying the
  /// ticks into next week would be wrong.
  final _checked = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);
    final async = ref.watch(_shoppingListProvider(widget.planId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.shoppingListTitle)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(error: error),
        data: (result) {
          final (lines, recipeCount) = result;
          if (lines.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.xxl),
                child: Text(
                  l10n.shoppingListEmpty,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }

          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.sm),
                child: Text(
                  l10n.shoppingListFrom(recipeCount),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final line in lines)
                CheckboxListTile(
                  value: _checked.contains(line.item),
                  onChanged: (_) => setState(() {
                    _checked.contains(line.item)
                        ? _checked.remove(line.item)
                        : _checked.add(line.item);
                  }),
                  title: Text(
                    _label(l10n, line, numerals),
                    style: TextStyle(
                      decoration: _checked.contains(line.item)
                          ? TextDecoration.lineThrough
                          : null,
                      color: _checked.contains(line.item)
                          ? theme.colorScheme.outline
                          : null,
                    ),
                  ),
                ),
              const SizedBox(height: Gap.xxl),
            ],
          );
        },
      ),
    );
  }

  String _label(AppLocalizations l10n, ShoppingLine line, NumeralStyle numerals) {
    final parts = [
      if (line.quantity != null) formatQuantity(line.quantity!, style: numerals),
      if (line.unit != Unit.piece && line.unit != Unit.toTaste)
        unitLabel(l10n, line.unit),
      line.item,
    ];
    return parts.join(' ');
  }
}
