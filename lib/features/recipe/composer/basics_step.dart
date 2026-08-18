import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/brnj_theme.dart';
import '../../../data/models/recipe.dart';
import '../../../data/providers.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'composer_labels.dart';

/// Step 1: what the dish is.
///
/// Region sits up here rather than buried in tags because it is the single
/// most argued-about property of an Iraqi recipe — whose kubba, whose pacha,
/// dolma with dibs rumman or without — and those arguments are the engagement.
class BasicsStep extends ConsumerStatefulWidget {
  const BasicsStep({required this.recipe, required this.onChange, super.key});

  final Recipe recipe;
  final void Function(Recipe Function(Recipe)) onChange;

  @override
  ConsumerState<BasicsStep> createState() => _BasicsStepState();
}

class _BasicsStepState extends ConsumerState<BasicsStep> {
  late final _title = TextEditingController(text: widget.recipe.title);
  late final _description = TextEditingController(
    text: widget.recipe.description ?? '',
  );
  bool _uploading = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    // The recipe needs an id before its images have somewhere to live, so a
    // cover chosen on a brand-new draft waits for the first autosave.
    var recipeId = widget.recipe.id;
    if (recipeId.isEmpty) {
      recipeId = await ref
          .read(recipeRepositoryProvider)
          .createDraft(widget.recipe);
      widget.onChange((r) => r.copyWith(id: recipeId));
    }

    setState(() => _uploading = true);
    try {
      final url = await ref
          .read(mediaRepositoryProvider)
          .uploadRecipeImage(
            recipeId: recipeId,
            filePath: picked.path,
            slot: 'cover',
          );
      widget.onChange((r) => r.copyWith(coverUrl: url));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recipe = widget.recipe;

    return ListView(
      padding: const EdgeInsets.all(Gap.xl),
      children: [
        _CoverPicker(
          coverUrl: recipe.coverUrl,
          uploading: _uploading,
          onTap: _pickCover,
        ),
        const SizedBox(height: Gap.xl),

        TextField(
          controller: _title,
          maxLength: 120,
          textInputAction: TextInputAction.next,
          onChanged: (value) =>
              widget.onChange((r) => r.copyWith(title: value)),
          decoration: InputDecoration(labelText: l10n.composerTitleLabel),
        ),
        const SizedBox(height: Gap.lg),

        TextField(
          controller: _description,
          maxLength: 500,
          maxLines: 3,
          onChanged: (value) =>
              widget.onChange((r) => r.copyWith(description: value)),
          decoration: InputDecoration(
            labelText: l10n.composerDescriptionLabel,
            helperText: l10n.composerDescriptionHelp,
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: Gap.xl),

        _Label(l10n.composerRegionLabel),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final region in Region.values)
              ChoiceChip(
                label: Text(regionLabel(l10n, region)),
                selected: recipe.region == region,
                onSelected: (_) =>
                    widget.onChange((r) => r.copyWith(region: region)),
              ),
          ],
        ),
        const SizedBox(height: Gap.xl),

        _Label(l10n.composerTimeLabel),
        Row(
          children: [
            Expanded(
              child: _NumberField(
                label: l10n.composerPrepMinutes,
                value: recipe.prepMinutes,
                onChanged: (v) =>
                    widget.onChange((r) => r.copyWith(prepMinutes: v)),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: _NumberField(
                label: l10n.composerCookMinutes,
                value: recipe.cookMinutes,
                onChanged: (v) =>
                    widget.onChange((r) => r.copyWith(cookMinutes: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg),

        _Label(l10n.recipeServings),
        _ServingsStepper(
          value: recipe.servings,
          onChanged: (v) => widget.onChange((r) => r.copyWith(servings: v)),
        ),
        const SizedBox(height: Gap.xl),

        _Label(l10n.composerDifficultyLabel),
        Wrap(
          spacing: Gap.sm,
          children: [
            for (final difficulty in Difficulty.values)
              ChoiceChip(
                label: Text(difficultyLabel(l10n, difficulty)),
                selected: recipe.difficulty == difficulty,
                onSelected: (_) =>
                    widget.onChange((r) => r.copyWith(difficulty: difficulty)),
              ),
          ],
        ),
        const SizedBox(height: Gap.xl),

        _Label(l10n.composerCostLabel),
        Wrap(
          spacing: Gap.sm,
          children: [
            for (final band in CostBand.values)
              ChoiceChip(
                label: Text(costBandLabel(l10n, band)),
                selected: recipe.costBand == band,
                onSelected: (_) =>
                    widget.onChange((r) => r.copyWith(costBand: band)),
              ),
          ],
        ),
        const SizedBox(height: Gap.xxl),
      ],
    );
  }
}

class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.coverUrl,
    required this.uploading,
    required this.onTap,
  });

  final String? coverUrl;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AspectRatio(
      // 4:3 is the shape food photography wants, and the shape the feed card
      // will crop to — showing it here means no surprises after publishing.
      aspectRatio: 4 / 3,
      child: InkWell(
        onTap: uploading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: uploading
                ? const Center(child: CircularProgressIndicator())
                : coverUrl == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo_outlined,
                        size: 32,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: Gap.sm),
                      Text(
                        l10n.composerAddCover,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                : CachedNetworkImage(imageUrl: coverUrl!, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value == 0 ? '' : '$value',
      keyboardType: TextInputType.number,
      // Latin keypad regardless of locale — people type 123 even where they
      // read ١٢٣.
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(labelText: label),
      onChanged: (text) => onChanged(int.tryParse(text) ?? 0),
    );
  }
}

/// Servings matters more here than in most recipe apps: Iraqi hospitality
/// means cooking for twenty is routine, and this number is what the scaler on
/// the detail screen divides by.
class _ServingsStepper extends StatelessWidget {
  const _ServingsStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton.outlined(
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 64,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
        ),
        IconButton.outlined(
          onPressed: value < 100 ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
