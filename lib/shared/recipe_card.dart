import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/theme/brnj_theme.dart';
import '../core/numerals.dart';
import '../data/models/recipe.dart';
import '../l10n/gen/app_localizations.dart';
import 'verified_tick.dart';

/// The feed card. One shape everywhere a recipe appears in a list.
class RecipeCard extends StatelessWidget {
  const RecipeCard({
    required this.recipe,
    required this.numerals,
    this.onTap,
    super.key,
  });

  final Recipe recipe;
  final NumeralStyle numerals;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () => context.push('/recipe/${recipe.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 4:3 is the shape food photography wants. Once the Resize Images
            // extension is running this should load the 400px variant rather
            // than the original — a feed that fetches full-size images is the
            // fastest way to a surprising bandwidth bill.
            AspectRatio(
              aspectRatio: 4 / 3,
              child: recipe.coverUrl == null
                  ? ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: Icon(
                          Icons.restaurant,
                          size: 32,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: recipe.coverUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: Gap.xs),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          recipe.author.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (recipe.author.verified) ...[
                        const SizedBox(width: Gap.xs),
                        const VerifiedTick(size: 14),
                      ],
                      const Spacer(),
                      if (recipe.totalMinutes > 0)
                        Text(
                          l10n.composerTimerMinutes(recipe.totalMinutes),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  if (recipe.tags.isNotEmpty) ...[
                    const SizedBox(height: Gap.md),
                    Wrap(
                      spacing: Gap.sm,
                      children: [
                        for (final tag in recipe.tags.take(3))
                          Chip(
                            label: Text(tag),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
