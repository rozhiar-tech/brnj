import 'package:flutter/material.dart';

import '../app/theme/brnj_colors.dart';
import '../l10n/gen/app_localizations.dart';

/// The verified mark. Brass, not blue — brass is reserved for verified and
/// seasonal moments so it keeps meaning something.
///
/// Verification is a curation tool, not a status game: it's granted and revoked
/// by an admin, lapses on inactivity, and the criteria are published in-app so
/// it doesn't read as arbitrary.
class VerifiedTick extends StatelessWidget {
  const VerifiedTick({this.size = 16, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Tooltip(
      message: AppLocalizations.of(context).verifiedBadge,
      child: Icon(
        Icons.verified,
        size: size,
        color: isLight ? BrnjColors.brass : BrnjColors.brassLight,
        semanticLabel: AppLocalizations.of(context).verifiedBadge,
      ),
    );
  }
}
