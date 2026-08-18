import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/brnj_theme.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';

/// Applying for the verified mark.
///
/// Verification is a curation tool, not a status game — it is granted and
/// revoked by a human, it lapses on inactivity, and the criteria are published
/// here rather than left to rumour. Publishing the bar is what stops the tick
/// from breeding resentment among everyone who doesn't have one.
class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key});

  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  final _note = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit(String uid) async {
    setState(() => _submitting = true);
    try {
      await ref
          .read(userRepositoryProvider)
          .requestVerification(uid: uid, note: _note.text);
      if (mounted) context.go('/me');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final uid = ref.watch(currentUidProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileGetVerified)),
      body: ListView(
        padding: const EdgeInsets.all(Gap.xl),
        children: [
          Text(l10n.verificationIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: Gap.xl),
          Text(
            l10n.verificationCriteriaTitle,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: Gap.sm),
          for (final criterion in [
            l10n.verificationCriterion1,
            l10n.verificationCriterion2,
            l10n.verificationCriterion3,
            l10n.verificationCriterion4,
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(criterion, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Gap.xl),
          TextField(
            controller: _note,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: l10n.verificationNote,
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: Gap.lg),
          FilledButton(
            onPressed: _submitting || uid == null ? null : () => _submit(uid),
            child: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.verificationSubmit),
          ),
          const SizedBox(height: Gap.md),
          Text(
            l10n.verificationReviewedByHuman,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
