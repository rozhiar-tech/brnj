import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../core/numerals.dart';
import '../../data/models/user_profile.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/verified_tick.dart';
import '../auth/sign_in_sheet.dart';

/// The Me tab.
///
/// Deliberately not a wall of numbers. The things people come here for are
/// their week, their saved recipes, and their settings; the counts are context,
/// not the point.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isGuest = ref.watch(isGuestProvider);
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navMe),
        actions: [
          IconButton(
            onPressed: () => context.go('/me/settings'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTitle,
          ),
        ],
      ),
      body: isGuest
          ? const _GuestProfile()
          : profileAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ProfileError(error: error),
              data: (profile) => profile == null
                  ? const Center(child: CircularProgressIndicator())
                  : _ProfileBody(profile: profile),
            ),
    );
  }
}

/// A guest still gets a Me tab — it explains what an account is for instead of
/// being a locked door. Language and data settings work without one.
class _GuestProfile extends ConsumerWidget {
  const _GuestProfile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Gap.xl),
      child: Column(
        children: [
          const SizedBox(height: Gap.xxl),
          CircleAvatar(
            radius: 40,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.person_outline,
              size: 36,
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: Gap.lg),
          Text(l10n.signInTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: Gap.sm),
          Text(
            l10n.signInBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Gap.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => requireAccount(context, ref),
              child: Text(l10n.signInWithPhone),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: Gap.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            children: [
              ProfileAvatar(photoUrl: profile.photoUrl, name: profile.displayName),
              const SizedBox(height: Gap.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      profile.displayName,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  if (profile.verified) ...[
                    const SizedBox(width: Gap.sm),
                    const VerifiedTick(size: 20),
                  ],
                ],
              ),
              if (profile.handle != null)
                Text(
                  '@${profile.handle}',
                  // Handles are Latin-only, so they render LTR even inside an
                  // Arabic or Kurdish layout.
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (profile.bio != null) ...[
                const SizedBox(height: Gap.md),
                Text(
                  profile.bio!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (profile.city != null) ...[
                const SizedBox(height: Gap.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: Gap.xs),
                    Text(
                      profile.city!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: Gap.lg),
              _Counts(counts: profile.counts, numerals: numerals),
              const SizedBox(height: Gap.lg),
              OutlinedButton(
                onPressed: () => context.go('/me/edit'),
                child: Text(l10n.profileEdit),
              ),
            ],
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.calendar_month_outlined),
          title: Text(l10n.myWeek),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/me/week'),
        ),
        ListTile(
          leading: const Icon(Icons.bookmark_border),
          title: Text(l10n.profileSaved),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {},
        ),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: Text(l10n.profileMyRecipes),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/me/recipes'),
        ),
        if (!profile.verified)
          ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: Text(l10n.profileGetVerified),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/me/verification'),
          ),
      ],
    );
  }
}

class _Counts extends StatelessWidget {
  const _Counts({required this.counts, required this.numerals});

  final UserCounts counts;
  final NumeralStyle numerals;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _Count(label: l10n.profileRecipes, value: counts.recipes, numerals: numerals),
        _Count(label: l10n.profilePlans, value: counts.plans, numerals: numerals),
        _Count(
          label: l10n.profileFollowers,
          value: counts.followers,
          numerals: numerals,
        ),
        _Count(
          label: l10n.profileFollowing,
          value: counts.following,
          numerals: numerals,
        ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({
    required this.label,
    required this.value,
    required this.numerals,
  });

  final String label;
  final int value;
  final NumeralStyle numerals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          formatCount(value, style: numerals),
          style: theme.textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Avatar with an initial fallback.
///
/// Illustrated and letter avatars are normal here, not a placeholder for a
/// missing photo — plenty of people will never upload a face, and the default
/// should not look like something is missing.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.photoUrl,
    required this.name,
    this.radius = 44,
    super.key,
  });

  final String? photoUrl;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (photoUrl == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          name.isEmpty ? '?' : name.characters.first,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      );
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: photoUrl!,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        placeholder: (_, _) => CircleAvatar(
          radius: radius,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        errorWidget: (_, _, _) => CircleAvatar(
          radius: radius,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(name.isEmpty ? '?' : name.characters.first),
        ),
      ),
    );
  }
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Text(l10n.errorGeneric, textAlign: TextAlign.center),
      ),
    );
  }
}
