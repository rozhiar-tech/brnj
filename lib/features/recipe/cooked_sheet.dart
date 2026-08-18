import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/brnj_theme.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/sign_in_sheet.dart';

/// "I cooked this."
///
/// The strongest signal in the app and the cheapest thing a person can
/// contribute — a photo of their own attempt, attached to someone else's
/// recipe. It is what turns a reader into a participant, and it is weighted
/// above likes and saves in ranking because it is proof rather than intent.
///
/// The photo is optional. Requiring one would filter out exactly the people
/// whose dinner looked fine but not photogenic, which is most of them.
Future<bool> showCookedSheet(
  BuildContext context,
  WidgetRef ref, {
  required String recipeId,
}) async {
  if (!await requireAccount(context, ref)) return false;
  if (!context.mounted) return false;

  final posted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CookedSheet(recipeId: recipeId),
  );
  return posted ?? false;
}

class _CookedSheet extends ConsumerStatefulWidget {
  const _CookedSheet({required this.recipeId});

  final String recipeId;

  @override
  ConsumerState<_CookedSheet> createState() => _CookedSheetState();
}

class _CookedSheetState extends ConsumerState<_CookedSheet> {
  final _note = TextEditingController();
  XFile? _photo;
  bool _posting = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _photo = picked);
  }

  Future<void> _post() async {
    setState(() => _posting = true);
    final author = await ref.read(myAuthorStubFuture.future);
    if (author == null) {
      if (mounted) setState(() => _posting = false);
      return;
    }
    final uid = author.uid;

    try {
      String? photoUrl;
      if (_photo != null) {
        photoUrl = await ref
            .read(mediaRepositoryProvider)
            .uploadRecipeImage(
              recipeId: widget.recipeId,
              filePath: _photo!.path,
              // Namespaced by uid so two people's attempts never collide, and one
              // person re-posting replaces their own.
              slot: 'cooked_$uid',
            );
      }

      await ref
          .read(recipeRepositoryProvider)
          .markCooked(
            recipeId: widget.recipeId,
            author: author,
            photoUrl: photoUrl,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );

      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _posting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: Gap.xl,
        right: Gap.xl,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Gap.xl,
      ),
      // Scrollable: with the keyboard up there is roughly half a screen left,
      // and a photo box plus two fields does not fit in it.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.recipeCookedThis, style: theme.textTheme.headlineSmall),
            const SizedBox(height: Gap.sm),
            Text(
              l10n.cookedSheetBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Gap.xl),

            InkWell(
              onTap: _pickPhoto,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: _photo == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo_outlined,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: Gap.sm),
                          Text(
                            l10n.cookedAddPhoto,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          _photo!.path,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, _, _) => Center(
                            child: Icon(
                              Icons.check_circle,
                              color: theme.colorScheme.primary,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: Gap.lg),

            TextField(
              controller: _note,
              maxLength: 280,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: l10n.cookedNoteLabel,
                helperText: l10n.cookedNoteHelp,
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: Gap.md),

            FilledButton(
              onPressed: _posting ? null : _post,
              child: _posting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.cookedPost),
            ),
          ],
        ),
      ),
    );
  }
}
