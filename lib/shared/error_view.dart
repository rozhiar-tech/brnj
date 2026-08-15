import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme/brnj_theme.dart';
import '../l10n/gen/app_localizations.dart';

/// The standard failure state.
///
/// Shows a plain sentence to a person and the real exception to a developer.
/// That second half is not a nicety: a Firestore query missing an index fails
/// with a message containing a one-click URL that creates it, and swallowing
/// that behind "something went wrong" turned a thirty-second fix into a
/// debugging session.
///
/// In release builds only the sentence is shown.
class ErrorView extends StatelessWidget {
  const ErrorView({required this.error, this.onRetry, super.key});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (kDebugMode && error != null) {
      debugPrint('ErrorView: $error');
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 36,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: Gap.md),
            Text(l10n.errorGeneric, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: Gap.md),
              OutlinedButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
            ],
            if (kDebugMode && error != null) ...[
              const SizedBox(height: Gap.xl),
              // Selectable and copyable: index errors carry a long URL that is
              // useless if it can't leave the screen.
              InkWell(
                onTap: () => Clipboard.setData(
                  ClipboardData(text: error.toString()),
                ),
                child: Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
