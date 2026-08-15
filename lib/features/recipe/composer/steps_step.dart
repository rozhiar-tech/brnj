import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/brnj_theme.dart';
import '../../../data/models/recipe.dart';
import '../../../data/providers.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/option_sheet.dart';

/// Step 3: how it's made.
///
/// Each step can carry a photo and a timer. The timer is not decoration — it
/// becomes a real countdown chip in cook mode, which is where these steps are
/// actually read, one at a time, by someone with their hands full.
class StepsStep extends ConsumerWidget {
  const StepsStep({required this.recipe, required this.onChange, super.key});

  final Recipe recipe;
  final void Function(Recipe Function(Recipe)) onChange;

  void _update(int index, RecipeStep step) {
    final list = [...recipe.steps]..[index] = step;
    onChange((r) => r.copyWith(steps: list));
  }

  void _add() {
    onChange((r) => r.copyWith(steps: [...r.steps, const RecipeStep(text: '')]));
  }

  void _remove(int index) {
    final list = [...recipe.steps]..removeAt(index);
    onChange((r) => r.copyWith(steps: list));
  }

  void _reorder(int oldIndex, int newIndex) {
    final list = [...recipe.steps];
    list.insert(newIndex, list.removeAt(oldIndex));
    onChange((r) => r.copyWith(steps: list));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        Expanded(
          child: recipe.steps.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.xxl),
                    child: Text(
                      l10n.composerStepsEmpty,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.all(Gap.lg),
                  itemCount: recipe.steps.length,
                  onReorderItem: _reorder,
                  itemBuilder: (context, index) => _StepCard(
                    key: ValueKey('step-$index-${recipe.steps.length}'),
                    index: index,
                    step: recipe.steps[index],
                    recipeId: recipe.id,
                    onChanged: (value) => _update(index, value),
                    onRemove: () => _remove(index),
                  ),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: Text(l10n.composerAddStep),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepCard extends ConsumerStatefulWidget {
  const _StepCard({
    required this.index,
    required this.step,
    required this.recipeId,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final int index;
  final RecipeStep step;
  final String recipeId;
  final ValueChanged<RecipeStep> onChanged;
  final VoidCallback onRemove;

  @override
  ConsumerState<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends ConsumerState<_StepCard> {
  late final _text = TextEditingController(text: widget.step.text);
  bool _uploading = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _emit({String? imageUrl, int? timerSeconds, bool clearTimer = false}) {
    widget.onChanged(
      RecipeStep(
        text: _text.text,
        imageUrl: imageUrl ?? widget.step.imageUrl,
        audioUrl: widget.step.audioUrl,
        timerSeconds: clearTimer ? null : (timerSeconds ?? widget.step.timerSeconds),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    if (widget.recipeId.isEmpty) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final url = await ref.read(mediaRepositoryProvider).uploadRecipeImage(
        recipeId: widget.recipeId,
        filePath: picked.path,
        slot: 'step_${widget.index}',
      );
      _emit(imageUrl: url);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickTimer() async {
    final l10n = AppLocalizations.of(context);
    final minutes = await showOptionSheet<int>(
      context,
      title: l10n.composerStepTimer,
      selected: widget.step.timerSeconds == null
          ? 0
          : widget.step.timerSeconds! ~/ 60,
      options: [
        SheetOption(value: 0, label: l10n.composerNoTimer),
        for (final m in [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120])
          SheetOption(value: m, label: l10n.composerTimerMinutes(m)),
      ],
    );
    if (minutes == null) return;
    _emit(timerSeconds: minutes * 60, clearTimer: minutes == 0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final timer = widget.step.timerSeconds;

    return Card(
      margin: const EdgeInsets.only(bottom: Gap.md),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
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
                    '${widget.index + 1}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: TextField(
                    controller: _text,
                    maxLines: null,
                    onChanged: (_) => _emit(),
                    decoration: InputDecoration(
                      hintText: l10n.composerStepHint,
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (widget.step.imageUrl != null) ...[
              const SizedBox(height: Gap.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: widget.step.imageUrl!,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _uploading || widget.recipeId.isEmpty
                      ? null
                      : _pickPhoto,
                  icon: _uploading
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.image_outlined, size: 18),
                  label: Text(l10n.composerStepPhoto),
                ),
                TextButton.icon(
                  onPressed: _pickTimer,
                  icon: const Icon(Icons.timer_outlined, size: 18),
                  label: Text(
                    timer == null
                        ? l10n.composerStepTimer
                        : l10n.composerTimerMinutes(timer ~/ 60),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
