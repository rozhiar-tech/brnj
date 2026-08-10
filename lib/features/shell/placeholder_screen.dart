import 'package:flutter/material.dart';

import '../../app/theme/brnj_theme.dart';

/// Stand-in for a tab that isn't built yet. Every one of these is a phase in
/// the plan; delete them as the phases land.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    required this.title,
    required this.icon,
    required this.note,
    super.key,
  });

  final String title;
  final IconData icon;
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: Gap.lg),
              Text(
                note,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
