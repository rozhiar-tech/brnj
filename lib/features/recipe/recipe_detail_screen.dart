import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../core/numerals.dart';
import '../../data/models/recipe.dart';
import '../../data/providers.dart';
import '../../data/repositories/view_tracker.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/error_view.dart';
import '../../data/repositories/safety_repository.dart';
import '../../shared/safety_actions.dart';
import '../../shared/verified_tick.dart';
import '../auth/sign_in_sheet.dart';
import 'composer/composer_labels.dart';
import 'recipe_social.dart';

final _recipeProvider = StreamProvider.family<Recipe?, String>(
  (ref, id) => ref.watch(recipeRepositoryProvider).watchRecipe(id),
);

class RecipeDetailScreen extends ConsumerStatefulWidget {
  const RecipeDetailScreen({required this.recipeId, super.key});

  final String recipeId;

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  void Function()? _endView;

  /// Local to the screen: what the reader is scaling to, which is often not
  /// what the author wrote. Not persisted — it is a reading aid, not an edit.
  int? _servings;

  /// Checked-off ingredients, kept in memory so the list survives scrolling
  /// but doesn't follow anyone around between sessions.
  final _checked = <int>{};

  @override
  void initState() {
    super.initState();
    final uid = ref.read(currentUidProvider);
    if (uid != null) {
      _endView = ref
          .read(viewTrackerProvider)
          .trackScreen(
            type: ViewTargetType.recipe,
            targetId: widget.recipeId,
            viewerUid: uid,
            isGuest: ref.read(isGuestProvider),
          );
    }
  }

  @override
  void dispose() {
    _endView?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recipeAsync = ref.watch(_recipeProvider(widget.recipeId));

    return Scaffold(
      body: recipeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(error: error),
        data: (recipe) => recipe == null
            ? Center(child: Text(l10n.errorGeneric))
            : _Body(
                recipe: recipe,
                servings: _servings ?? recipe.servings,
                checked: _checked,
                onServings: (value) => setState(() => _servings = value),
                onToggle: (index) => setState(() {
                  _checked.contains(index)
                      ? _checked.remove(index)
                      : _checked.add(index);
                }),
              ),
      ),
      bottomNavigationBar: recipeAsync.value == null
          ? null
          : _ActionBar(recipe: recipeAsync.value!),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.recipe,
    required this.servings,
    required this.checked,
    required this.onServings,
    required this.onToggle,
  });

  final Recipe recipe;
  final int servings;
  final Set<int> checked;
  final ValueChanged<int> onServings;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);
    final ingredients = recipe.ingredientsFor(servings);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 260,
          pinned: true,
          actions: [
            SafetyMenu(
              targetType: ReportTarget.recipe,
              targetId: recipe.id,
              targetOwner: recipe.author.uid,
              iconColor: Colors.white,
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: recipe.coverUrl == null
                ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
                : CachedNetworkImage(
                    imageUrl: recipe.coverUrl!,
                    fit: BoxFit.cover,
                  ),
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.all(Gap.xl),
          sliver: SliverList.list(
            children: [
              Text(recipe.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: Gap.md),
              InkWell(
                onTap: () => context.push('/user/\${recipe.author.uid}'),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      child: Text(
                        recipe.author.name.characters.first,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Text(recipe.author.name, style: theme.textTheme.labelLarge),
                    if (recipe.author.verified) ...[
                      const SizedBox(width: Gap.xs),
                      const VerifiedTick(size: 14),
                    ],
                    const SizedBox(width: Gap.xs),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: theme.colorScheme.outline,
                    ),
                  ],
                ),
              ),
              if (recipe.description != null) ...[
                const SizedBox(height: Gap.md),
                Text(recipe.description!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: Gap.lg),
              _StatStrip(recipe: recipe, numerals: numerals),
              const SizedBox(height: Gap.xl),

              Text(l10n.recipeIngredients, style: theme.textTheme.titleMedium),
              const SizedBox(height: Gap.sm),
              _ServingsScaler(
                servings: servings,
                original: recipe.servings,
                numerals: numerals,
                onChanged: onServings,
              ),
              if (recipe.hasNonLinearScaling && servings != recipe.servings)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.sm),
                  child: Text(
                    l10n.recipeScalingWarning,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ),
              const SizedBox(height: Gap.md),

              for (var i = 0; i < ingredients.length; i++)
                _IngredientTile(
                  ingredient: ingredients[i],
                  checked: checked.contains(i),
                  numerals: numerals,
                  showGroupHeader:
                      i == 0 ||
                      ingredients[i].group != ingredients[i - 1].group,
                  onToggle: () => onToggle(i),
                ),

              const SizedBox(height: Gap.xl),
              Text(l10n.recipeSteps, style: theme.textTheme.titleMedium),
              const SizedBox(height: Gap.md),
              for (var i = 0; i < recipe.steps.length; i++)
                _StepTile(index: i, step: recipe.steps[i], numerals: numerals),

              const SizedBox(height: Gap.xxl),
              const Divider(),
              const SizedBox(height: Gap.lg),
              CookedGallery(recipeId: recipe.id),
              const SizedBox(height: Gap.xxl),
              CommentThread(
                recipeId: recipe.id,
                recipeAuthorUid: recipe.author.uid,
              ),
              const SizedBox(height: Gap.xxl),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.recipe, required this.numerals});

  final Recipe recipe;
  final NumeralStyle numerals;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      children: [
        _Chip(
          icon: Icons.schedule,
          label: l10n.composerTimerMinutes(recipe.totalMinutes),
          numerals: numerals,
        ),
        _Chip(
          icon: Icons.place_outlined,
          label: regionLabel(l10n, recipe.region),
        ),
        _Chip(
          icon: Icons.local_fire_department_outlined,
          label: difficultyLabel(l10n, recipe.difficulty),
        ),
        _Chip(
          icon: Icons.payments_outlined,
          label: costBandLabel(l10n, recipe.costBand),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.numerals});

  final IconData icon;
  final String label;
  final NumeralStyle? numerals;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 14),
      label: Text(numerals == null ? label : label.toNumeralStyle(numerals!)),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// The servings scaler.
///
/// Cooking for twenty is routine in an Iraqi household, so this is a headline
/// control rather than a buried setting. It rewrites every quantity live.
class _ServingsScaler extends StatelessWidget {
  const _ServingsScaler({
    required this.servings,
    required this.original,
    required this.numerals,
    required this.onChanged,
  });

  final int servings;
  final int original;
  final NumeralStyle numerals;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Row(
      children: [
        Text(
          l10n.recipeServings,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        IconButton.outlined(
          onPressed: servings > 1 ? () => onChanged(servings - 1) : null,
          icon: const Icon(Icons.remove),
          visualDensity: VisualDensity.compact,
        ),
        SizedBox(
          width: 48,
          child: Text(
            '$servings'.toNumeralStyle(numerals),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: servings == original ? null : theme.colorScheme.primary,
            ),
          ),
        ),
        IconButton.outlined(
          onPressed: servings < 100 ? () => onChanged(servings + 1) : null,
          icon: const Icon(Icons.add),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _IngredientTile extends StatelessWidget {
  const _IngredientTile({
    required this.ingredient,
    required this.checked,
    required this.numerals,
    required this.showGroupHeader,
    required this.onToggle,
  });

  final Ingredient ingredient;
  final bool checked;
  final NumeralStyle numerals;
  final bool showGroupHeader;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final quantity = ingredient.quantity;
    final measure = [
      if (quantity != null) formatQuantity(quantity, style: numerals),
      if (ingredient.unit != Unit.piece) unitLabel(l10n, ingredient.unit),
    ].join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showGroupHeader && ingredient.group != null)
          Padding(
            padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.xs),
            child: Text(
              ingredient.group!,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  checked
                      ? Icons.check_box_outlined
                      : Icons.check_box_outline_blank,
                  size: 20,
                  color: checked
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        measure.isEmpty
                            ? ingredient.item
                            : '$measure ${ingredient.item}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          decoration: checked
                              ? TextDecoration.lineThrough
                              : null,
                          color: checked ? theme.colorScheme.outline : null,
                        ),
                      ),
                      // The substitution note is shown inline rather than
                      // hidden behind a tap: a recipe calling for something
                      // unavailable here is useless without it.
                      if (ingredient.note != null)
                        Text(
                          ingredient.note!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.index,
    required this.step,
    required this.numerals,
  });

  final int index;
  final RecipeStep step;
  final NumeralStyle numerals;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  '${index + 1}'.toNumeralStyle(numerals),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(step.text, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          if (step.imageUrl != null) ...[
            const SizedBox(height: Gap.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: step.imageUrl!,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          if (step.timerSeconds != null) ...[
            const SizedBox(height: Gap.sm),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 42),
              child: Chip(
                avatar: const Icon(Icons.timer_outlined, size: 14),
                label: Text(
                  l10n.composerTimerMinutes(step.timerSeconds! ~/ 60),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The bar that turns reading into cooking.
///
/// Cook mode is the primary action and gets the width to say so; "I cooked
/// this" sits beside it because the moment someone finishes is the moment they
/// might post, and asking later never works.
class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final saved = ref.watch(savedRecipeIdsProvider).value ?? const [];
    final isSaved = saved.contains(recipe.id);
    final isLiked = ref.watch(likedProvider(recipe.id)).value ?? false;
    final uid = ref.watch(currentUidProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Row(
          children: [
            IconButton.outlined(
              onPressed: uid == null
                  ? null
                  : () async {
                      if (!await requireAccount(context, ref)) return;
                      await ref
                          .read(recipeRepositoryProvider)
                          .setLiked(
                            recipeId: recipe.id,
                            uid: uid,
                            liked: !isLiked,
                          );
                    },
              icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border),
              tooltip: l10n.recipeLike,
            ),
            const SizedBox(width: Gap.sm),
            IconButton.outlined(
              onPressed: uid == null
                  ? null
                  : () async {
                      if (!await requireAccount(context, ref)) return;
                      await ref
                          .read(recipeRepositoryProvider)
                          .setSaved(
                            recipeId: recipe.id,
                            uid: uid,
                            saved: !isSaved,
                          );
                    },
              icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
              tooltip: l10n.actionSave,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: FilledButton.icon(
                onPressed: recipe.steps.isEmpty
                    ? null
                    : () => context.push('/cook/${recipe.id}'),
                icon: const Icon(Icons.play_arrow),
                label: Text(l10n.recipeCookMode),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
