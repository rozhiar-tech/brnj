import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/brnj_theme.dart';
import '../../l10n/gen/app_localizations.dart';

/// Shown when a location matches no route — a stale share link, a deep link
/// from an older build, a typo in a `go()` call.
///
/// go_router's built-in fallback is a developer artefact: untranslated, and a
/// non-scrolling [Column] that overflows on a phone-sized screen, so a routing
/// miss surfaces as a layout error rather than as itself. This replaces it with
/// something a person can read and act on, and logs the offending URI in debug
/// so the miss is diagnosable.
class RouteNotFoundScreen extends StatelessWidget {
  const RouteNotFoundScreen({required this.uri, this.error, super.key});

  final Uri uri;
  final Exception? error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (kDebugMode) {
      debugPrint('Route not found: $uri${error == null ? '' : ' ($error)'}');
    }

    return Scaffold(
      appBar: AppBar(),
      // Scrollable, so long content can never overflow the way the default
      // screen does.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: Gap.xxl),
              Icon(
                Icons.link_off,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: Gap.lg),
              Text(
                l10n.routeNotFoundTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: Gap.sm),
              Text(
                l10n.routeNotFoundBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Gap.xl),
              FilledButton(
                onPressed: () => context.go('/'),
                child: Text(l10n.navHome),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: Gap.xl),
                SelectableText(
                  uri.toString(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
