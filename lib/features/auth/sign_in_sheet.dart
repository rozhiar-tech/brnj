import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/brnj_theme.dart';
import '../../data/providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../../l10n/gen/app_localizations.dart';

/// Gate for any action that needs a real account.
///
/// Returns true when the caller may proceed. The contract that matters: on
/// success the caller **completes the original action**. Signing someone in and
/// then dumping them back on the feed to find the button again is how you lose
/// the registration you just earned.
///
/// ```dart
/// if (!await requireAccount(context, ref)) return;
/// await repository.setLiked(...);
/// ```
Future<bool> requireAccount(BuildContext context, WidgetRef ref) async {
  if (!ref.read(isGuestProvider)) return true;

  final signedIn = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _SignInSheet(),
  );
  return signedIn ?? false;
}

class _SignInSheet extends ConsumerStatefulWidget {
  const _SignInSheet();

  @override
  ConsumerState<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends ConsumerState<_SignInSheet> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  String? _verificationId;
  bool _busy = false;
  AuthFailure? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.failure);
    } catch (_) {
      if (mounted) setState(() => _error = AuthFailure.unknown);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    final uid = ref.read(authRepositoryProvider).uid;
    if (uid != null) {
      // Now, not at launch: the person has just chosen to take part, which is
      // the only moment a notification prompt reads as reasonable.
      unawaited(ref.read(messagingRepositoryProvider).register(uid));
    }
    // A moderator who signs in goes straight to the queues.
    unawaited(_routeModerator());
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _routeModerator() async {
    final claims = await ref
        .read(adminRepositoryProvider)
        .claims(refresh: true);
    if (!claims.canModerate || !mounted) return;
    ref.invalidate(adminClaimsProvider);
    // Not awaited: the route outlives this sheet, which is about to close.
    if (mounted) unawaited(context.push('/admin'));
  }

  Future<void> _sendCode() => _run(() async {
    final id = await _auth.startPhoneVerification(
      // Iraqi numbers are typed as 0770…, which E.164 needs as +964770….
      phoneNumber: _toE164(_phoneController.text),
      onAutoVerified: (_) => _done(),
    );
    if (mounted) setState(() => _verificationId = id);
  });

  Future<void> _confirmCode() => _run(() async {
    await _auth.confirmPhoneCode(
      verificationId: _verificationId!,
      smsCode: _codeController.text.trim(),
    );
    _done();
  });

  Future<void> _google() => _run(() async {
    await _auth.signInWithGoogle();
    _done();
  });

  /// Iraq is +964, and people drop the leading zero when they add the country
  /// code. Both "07701234567" and "+9647701234567" have to work.
  static String _toE164(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('964')) return '+$digits';
    if (digits.startsWith('0')) return '+964${digits.substring(1)}';
    return '+964$digits';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final onCodeStep = _verificationId != null;

    return Padding(
      padding: EdgeInsets.only(
        left: Gap.xl,
        right: Gap.xl,
        top: Gap.sm,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Gap.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              onCodeStep ? l10n.signInCodeTitle : l10n.signInTitle,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: Gap.sm),
            Text(
              l10n.signInBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Gap.xl),

            if (onCodeStep) ...[
              TextField(
                controller: _codeController,
                autofocus: true,
                // Latin keypad regardless of locale: people type 123 even when
                // they read ١٢٣, and an Arabic-Indic keypad generates complaints.
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  letterSpacing: 8,
                ),
                decoration: InputDecoration(hintText: l10n.signInCodeHint),
              ),
              const SizedBox(height: Gap.lg),
              FilledButton(
                onPressed: _busy ? null : _confirmCode,
                child: _busy ? const _Spinner() : Text(l10n.signInVerify),
              ),
            ] else ...[
              TextField(
                controller: _phoneController,
                autofocus: true,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  hintText: l10n.signInPhoneHint,
                  prefixText: '+964 ',
                ),
              ),
              const SizedBox(height: Gap.lg),
              FilledButton(
                onPressed: _busy ? null : _sendCode,
                child: _busy ? const _Spinner() : Text(l10n.signInWithPhone),
              ),
              const SizedBox(height: Gap.md),
              OutlinedButton.icon(
                onPressed: _busy ? null : _google,
                icon: const Icon(Icons.g_mobiledata, size: 28),
                label: Text(l10n.signInWithGoogle),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: Gap.md),
              Text(
                _messageFor(_error!, l10n),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],

            const SizedBox(height: Gap.sm),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: Text(l10n.signInLater),
            ),
          ],
        ),
      ),
    );
  }

  /// Errors say what went wrong and what to do — never "an error occurred".
  String _messageFor(AuthFailure failure, AppLocalizations l10n) =>
      switch (failure) {
        AuthFailure.invalidCode => l10n.signInErrorInvalidCode,
        AuthFailure.codeExpired => l10n.signInErrorCodeExpired,
        AuthFailure.tooManyRequests => l10n.signInErrorTooMany,
        AuthFailure.network => l10n.errorOffline,
        AuthFailure.cancelled => '',
        _ => l10n.errorGeneric,
      };
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 20,
    width: 20,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: Theme.of(context).colorScheme.onPrimary,
    ),
  );
}
