import 'package:flutter/material.dart';

import '../../app/theme/brnj_theme.dart';
import '../../l10n/gen/app_localizations.dart';

/// The five things a person can make. Recipe and Weekly plan are the two
/// social objects; the rest are low-effort posts that keep the feed warm
/// between them.
void showCreateSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CreateOption(
              icon: Icons.menu_book_outlined,
              label: l10n.createRecipe,
              onTap: () => Navigator.pop(context),
            ),
            _CreateOption(
              icon: Icons.local_fire_department_outlined,
              label: l10n.createCooked,
              onTap: () => Navigator.pop(context),
            ),
            _CreateOption(
              icon: Icons.calendar_month_outlined,
              label: l10n.createPlan,
              onTap: () => Navigator.pop(context),
            ),
            _CreateOption(
              icon: Icons.help_outline,
              label: l10n.createQuestion,
              onTap: () => Navigator.pop(context),
            ),
            _CreateOption(
              icon: Icons.photo_outlined,
              label: l10n.createPhoto,
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: Gap.sm),
          ],
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
