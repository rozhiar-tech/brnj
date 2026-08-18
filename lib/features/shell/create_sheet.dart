import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/brnj_theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/sign_in_sheet.dart';

/// The five things a person can make. Recipe and Weekly plan are the two
/// social objects; the rest are low-effort posts that keep the feed warm
/// between them.
void showCreateSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final l10n = AppLocalizations.of(context);

      // Creating anything needs an account. The gate signs the person in and
      // then completes what they were doing, rather than dropping them back
      // on the feed to find the button again.
      Future<void> go(WidgetRef ref, String route) async {
        final navigator = Navigator.of(context);
        if (!await requireAccount(context, ref)) return;
        navigator.pop();
        // Not awaited: the pushed route's result is nothing this sheet needs,
        // and the sheet is already gone by the time it returns.
        if (context.mounted) unawaited(context.push(route));
      }

      return Consumer(
        builder: (context, ref, _) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CreateOption(
                icon: Icons.menu_book_outlined,
                label: l10n.createRecipe,
                onTap: () => go(ref, '/create/recipe'),
              ),
              // "I cooked this" attaches to a specific recipe, so it starts
              // from the recipe rather than from here — this sends you to find
              // one instead of asking which.
              _CreateOption(
                icon: Icons.local_fire_department_outlined,
                label: l10n.createCooked,
                onTap: () => go(ref, '/search'),
              ),
              _CreateOption(
                icon: Icons.calendar_month_outlined,
                label: l10n.createPlan,
                onTap: () => go(ref, '/me/week'),
              ),
              const SizedBox(height: Gap.sm),
            ],
          ),
        ),
      );
    },
  );
}

class _CreateOption extends StatelessWidget {
  const _CreateOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label, style: Theme.of(context).textTheme.titleMedium),
      onTap: onTap,
    );
  }
}
