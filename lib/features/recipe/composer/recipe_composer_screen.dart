import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/brnj_theme.dart';
import '../../../data/models/recipe.dart';
import '../../../data/providers.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'basics_step.dart';
import 'ingredients_step.dart';
import 'steps_step.dart';

/// The recipe composer.
///
/// Three steps and a review, with the draft written to Firestore after every
/// change. Nobody should ever lose a half-written recipe to a phone call, and
/// on a patchy connection "save" is the moment most likely to fail — so it
/// happens continuously and quietly rather than once at the end.
class RecipeComposerScreen extends ConsumerStatefulWidget {
  const RecipeComposerScreen({this.draftId, super.key});

  /// Existing draft to resume, or null to start a new one.
  final String? draftId;

  @override
  ConsumerState<RecipeComposerScreen> createState() =>
      _RecipeComposerScreenState();
}

enum SaveState { idle, saving, saved, failed }

class _RecipeComposerScreenState extends ConsumerState<RecipeComposerScreen> {
  final _pageController = PageController();

  Recipe? _recipe;
  int _page = 0;
  SaveState _saveState = SaveState.idle;
  Timer? _saveTimer;
  bool _loading = true;

  /// Debounce window for the autosave. Long enough that typing a title is one
  /// write rather than fifteen; short enough that closing the app right after
  /// a change loses nothing.
  static const _saveDebounce = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final author = await ref.read(myAuthorStubFuture.future);
    if (author == null) {
      setState(() => _loading = false);
      return;
    }

    if (widget.draftId != null) {
      final existing = await ref
          .read(recipeRepositoryProvider)
          .getRecipe(widget.draftId!);
      if (existing != null) {
        setState(() {
          _recipe = existing;
          _loading = false;
        });
        return;
      }
    }

    setState(() {
      _recipe = Recipe(
        id: '',
        author: author,
        title: '',
        // Content language defaults to the interface language but is editable:
        // plenty of people want a Kurdish interface and write in Arabic.
        language: ref.read(activeContentLanguageProvider),
      );
      _loading = false;
    });
  }

  /// Applies an edit and schedules a save. Every field in every step routes
  /// through here, so autosave can't be forgotten on a new field.
  void _edit(Recipe Function(Recipe) change) {
    final current = _recipe;
    if (current == null) return;
    setState(() => _recipe = change(current));
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () => unawaited(_save()));
  }

  Future<void> _save() async {
    final recipe = _recipe;
    if (recipe == null) return;

    setState(() => _saveState = SaveState.saving);
    try {
      final repository = ref.read(recipeRepositoryProvider);
      if (recipe.id.isEmpty) {
        final id = await repository.createDraft(recipe);
        // Keep the id so later saves update rather than creating a second draft.
        if (mounted) setState(() => _recipe = recipe.copyWith(id: id));
      } else {
        await repository.update(recipe);
      }
      if (mounted) setState(() => _saveState = SaveState.saved);
    } catch (_) {
      if (mounted) setState(() => _saveState = SaveState.failed);
    }
  }

  Future<void> _publish() async {
    final recipe = _recipe;
    if (recipe == null || !recipe.canPublish) return;

    // Flush any pending edit before publishing, or the published document is
    // one debounce window out of date.
    _saveTimer?.cancel();
    await _save();

    final current = _recipe;
    if (current == null || current.id.isEmpty) return;

    await ref.read(recipeRepositoryProvider).publish(current);
    if (mounted) context.pushReplacement('/recipe/${current.id}');
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recipe = _recipe;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (recipe == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.signInBody)),
      );
    }

    return PopScope(
      // Nothing to confirm on the way out — the draft is already saved, and
      // an "are you sure?" over work that is safe just trains people to
      // dismiss dialogs.
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _saveTimer?.cancel();
          unawaited(_save());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.createRecipe),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: (_page + 1) / 4,
              minHeight: 3,
            ),
          ),
          actions: [_SaveIndicator(state: _saveState)],
        ),
        body: PageView(
          controller: _pageController,
          onPageChanged: (page) => setState(() => _page = page),
          children: [
            BasicsStep(recipe: recipe, onChange: _edit),
            IngredientsStep(recipe: recipe, onChange: _edit),
            StepsStep(recipe: recipe, onChange: _edit),
            _ReviewStep(recipe: recipe, onJumpTo: _goToPage),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Row(
              children: [
                if (_page > 0)
                  OutlinedButton(
                    onPressed: () => _goToPage(_page - 1),
                    child: Text(l10n.composerBack),
                  ),
                const Spacer(),
                if (_page < 3)
                  FilledButton(
                    onPressed: () => _goToPage(_page + 1),
                    child: Text(l10n.composerNext),
                  )
                else
                  FilledButton(
                    onPressed: recipe.canPublish ? _publish : null,
                    child: Text(
                      recipe.status == RecipeStatus.published
                          ? l10n.actionSave
                          : l10n.composerPublish,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quiet confirmation that the draft is safe. Deliberately understated — this
/// is reassurance, not an event.
class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.state});

  final SaveState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: Gap.lg),
      child: Center(
        child: switch (state) {
          SaveState.idle => const SizedBox.shrink(),
          SaveState.saving => SizedBox(
            height: 14,
            width: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SaveState.saved => Text(
            l10n.composerDraftSaved,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SaveState.failed => Icon(
            Icons.cloud_off,
            size: 18,
            color: theme.colorScheme.error,
          ),
        },
      ),
    );
  }
}

/// The last page: what is still missing, and why it matters.
class _ReviewStep extends StatelessWidget {
  const _ReviewStep({required this.recipe, required this.onJumpTo});

  final Recipe recipe;
  final void Function(int page) onJumpTo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final blockers = recipe.publishBlockers;

    return ListView(
      padding: const EdgeInsets.all(Gap.xl),
      children: [
        Text(
          blockers.isEmpty ? l10n.composerReadyTitle : l10n.composerAlmostTitle,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: Gap.sm),
        Text(
          blockers.isEmpty ? l10n.composerReadyBody : l10n.composerAlmostBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Gap.xl),
        for (final blocker in blockers)
          Card(
            margin: const EdgeInsets.only(bottom: Gap.md),
            child: ListTile(
              leading: Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
              ),
              title: Text(_blockerLabel(l10n, blocker)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onJumpTo(_pageFor(blocker)),
            ),
          ),
        if (blockers.isEmpty) ...[
          _ReviewRow(label: l10n.composerTitleLabel, value: recipe.title),
          _ReviewRow(
            label: l10n.recipeIngredients,
            value: '${recipe.ingredients.length}',
          ),
          _ReviewRow(label: l10n.recipeSteps, value: '${recipe.steps.length}'),
          _ReviewRow(label: l10n.recipeServings, value: '${recipe.servings}'),
        ],
      ],
    );
  }

  static String _blockerLabel(AppLocalizations l10n, String key) =>
      switch (key) {
        'title' => l10n.composerNeedsTitle,
        'cover' => l10n.composerNeedsCover,
        'ingredients' => l10n.composerNeedsIngredients,
        _ => l10n.composerNeedsSteps,
      };

  static int _pageFor(String key) => switch (key) {
    'title' || 'cover' => 0,
    'ingredients' => 1,
    _ => 2,
  };
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
