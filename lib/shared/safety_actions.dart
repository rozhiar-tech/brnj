import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme/brnj_theme.dart';
import '../data/providers.dart';
import '../data/repositories/safety_repository.dart';
import '../l10n/gen/app_localizations.dart';
import '../features/auth/sign_in_sheet.dart';

/// The overflow menu that every piece of content carries.
///
/// Report and block are on every object because the plan treats them as
/// product requirements, not settings — and because the person who needs them
/// is looking at the thing that upset them, not hunting through preferences.
class SafetyMenu extends ConsumerWidget {
  const SafetyMenu({
    required this.targetType,
    required this.targetId,
    required this.targetOwner,
    this.iconColor,
    super.key,
  });

  final ReportTarget targetType;
  final String targetId;

  /// Whose content it is. Null disables blocking — you cannot block a thing,
  /// only a person.
  final String? targetOwner;

  final Color? iconColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final myUid = ref.watch(currentUidProvider);
    final isMine = targetOwner != null && targetOwner == myUid;
    final blocked = targetOwner == null
        ? false
        : ref.watch(isBlockedProvider(targetOwner!)).value ?? false;

    // Nothing to report or block on your own content.
    if (isMine) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, color: iconColor),
      onSelected: (value) async {
        if (value == 'report') {
          await showReportSheet(
            context,
            ref,
            targetType: targetType,
            targetId: targetId,
            targetOwner: targetOwner,
          );
        } else if (value == 'block' && targetOwner != null) {
          await _toggleBlock(context, ref, targetOwner!, !blocked);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'report', child: Text(l10n.actionReport)),
        if (targetOwner != null)
          PopupMenuItem(
            value: 'block',
            child: Text(blocked ? l10n.actionUnblock : l10n.actionBlock),
          ),
      ],
    );
  }

  Future<void> _toggleBlock(
    BuildContext context,
    WidgetRef ref,
    String targetUid,
    bool block,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (!await requireAccount(context, ref)) return;

    if (block && context.mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.actionBlock),
          content: Text(l10n.blockConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(l10n.actionBlock),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    await ref.read(safetyRepositoryProvider).setBlocked(
      uid: uid,
      targetUid: targetUid,
      blocked: block,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(block ? l10n.blockDone : l10n.unblockDone)),
      );
    }
  }
}

/// Reporting.
///
/// Five reasons and a free-text box. A longer list makes people pick the
/// closest wrong one and makes the queue harder to triage; the nuance goes in
/// the note.
Future<void> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required ReportTarget targetType,
  required String targetId,
  String? targetOwner,
}) async {
  if (!await requireAccount(context, ref)) return;
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReportSheet(
      targetType: targetType,
      targetId: targetId,
      targetOwner: targetOwner,
    ),
  );
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({
    required this.targetType,
    required this.targetId,
    this.targetOwner,
  });

  final ReportTarget targetType;
  final String targetId;
  final String? targetOwner;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _note = TextEditingController();
  ReportReason? _reason;
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null || _reason == null) return;

    setState(() => _sending = true);
    try {
      await ref.read(safetyRepositoryProvider).report(
        reporterId: uid,
        targetType: widget.targetType,
        targetId: widget.targetId,
        targetOwner: widget.targetOwner,
        reason: _reason!,
        note: _note.text,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).reportDone)),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _sending = false);
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
            Text(l10n.actionReport, style: theme.textTheme.headlineSmall),
            const SizedBox(height: Gap.sm),
            Text(
              l10n.reportBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Gap.lg),

            for (final reason in ReportReason.values)
              RadioGroup<ReportReason>(
                groupValue: _reason,
                onChanged: (value) => setState(() => _reason = value),
                child: RadioListTile<ReportReason>(
                  title: Text(_label(l10n, reason)),
                  value: reason,
                  contentPadding: EdgeInsets.zero,
                ),
              ),

            const SizedBox(height: Gap.sm),
            TextField(
              controller: _note,
              maxLength: 500,
              maxLines: 3,
              decoration: InputDecoration(labelText: l10n.reportNote),
            ),
            const SizedBox(height: Gap.md),
            FilledButton(
              onPressed: _reason == null || _sending ? null : _send,
              child: _sending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.reportSend),
            ),
          ],
        ),
      ),
    );
  }

  String _label(AppLocalizations l10n, ReportReason reason) => switch (reason) {
    ReportReason.harassment => l10n.reportHarassment,
    ReportReason.spam => l10n.reportSpam,
    ReportReason.wrongOrStolen => l10n.reportStolen,
    ReportReason.inappropriate => l10n.reportInappropriate,
    ReportReason.other => l10n.reportOther,
  };
}
