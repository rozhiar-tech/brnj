import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/brnj_theme.dart';
import '../../data/models/weekly_plan.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';

/// Title, note and tags for a week.
///
/// These are what make a published week worth opening — "أسبوع اقتصادي" tells
/// someone more than seven dish names do, and the tags are what the browse rail
/// filters on. Without an editor the fields existed and nobody could fill them.
Future<void> showPlanDetailsSheet(
  BuildContext context,
  WidgetRef ref, {
  required WeeklyPlan plan,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PlanDetailsSheet(plan: plan),
  );
}

class _PlanDetailsSheet extends ConsumerStatefulWidget {
  const _PlanDetailsSheet({required this.plan});

  final WeeklyPlan plan;

  @override
  ConsumerState<_PlanDetailsSheet> createState() => _PlanDetailsSheetState();
}

class _PlanDetailsSheetState extends ConsumerState<_PlanDetailsSheet> {
  late final _title = TextEditingController(text: widget.plan.title ?? '');
  late final _note = TextEditingController(text: widget.plan.note ?? '');
  late List<String> _tags = [...widget.plan.tags];
  final _tagInput = TextEditingController();
  bool _saving = false;

  /// Suggestions rather than a fixed vocabulary: these are the weeks people
  /// actually plan, and a free-text field alongside means the list is a
  /// shortcut, not a cage.
  static const _suggested = [
    'اقتصادي',
    'سريع',
    'رمضان',
    'عزيمة',
    'صحي',
    'أطفال',
  ];

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  void _addTag(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty || _tags.contains(tag) || _tags.length >= 6) return;
    setState(() {
      _tags = [..._tags, tag];
      _tagInput.clear();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(planRepositoryProvider)
          .save(
            widget.plan.copyWith(
              title: _title.text.trim(),
              note: _note.text.trim(),
              tags: _tags,
            ),
          );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.planDetailsTitle, style: theme.textTheme.headlineSmall),
            const SizedBox(height: Gap.lg),

            TextField(
              controller: _title,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: l10n.planTitleLabel,
                helperText: l10n.planTitleHelp,
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: Gap.md),

            TextField(
              controller: _note,
              maxLength: 200,
              maxLines: 2,
              decoration: InputDecoration(labelText: l10n.planNoteLabel),
            ),
            const SizedBox(height: Gap.lg),

            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l10n.planTagsLabel,
                style: theme.textTheme.labelLarge,
              ),
            ),
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                for (final tag in _tags)
                  InputChip(
                    label: Text(tag),
                    onDeleted: () =>
                        setState(() => _tags = [..._tags]..remove(tag)),
                  ),
                for (final tag in _suggested.where((t) => !_tags.contains(t)))
                  ActionChip(label: Text(tag), onPressed: () => _addTag(tag)),
              ],
            ),
            const SizedBox(height: Gap.sm),
            TextField(
              controller: _tagInput,
              textInputAction: TextInputAction.done,
              onSubmitted: _addTag,
              decoration: InputDecoration(
                labelText: l10n.planTagAdd,
                isDense: true,
              ),
            ),
            const SizedBox(height: Gap.lg),

            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.actionSave),
            ),
          ],
        ),
      ),
    );
  }
}
