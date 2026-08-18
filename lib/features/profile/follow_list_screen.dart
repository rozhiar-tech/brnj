import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/brnj_theme.dart';
import '../../data/models/user_profile.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/error_view.dart';
import '../../shared/verified_tick.dart';
import 'profile_screen.dart';

enum FollowListKind { followers, following }

/// Followers and following, one screen with two tabs.
///
/// They are the same list rendered twice, and people arrive expecting to swap
/// between them — separate screens would just mean going back and tapping the
/// other number.
class FollowListScreen extends ConsumerWidget {
  const FollowListScreen({required this.uid, required this.initial, super.key});

  final String uid;
  final FollowListKind initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return DefaultTabController(
      length: 2,
      initialIndex: initial == FollowListKind.followers ? 0 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            ref.watch(userProfileProvider(uid)).value?.displayName ?? '',
          ),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.profileFollowers),
              Tab(text: l10n.profileFollowing),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _List(
              provider: followersProvider(uid),
              emptyText: l10n.followersEmpty,
            ),
            _List(
              provider: followingProvider(uid),
              emptyText: l10n.followingEmpty,
            ),
          ],
        ),
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.provider, required this.emptyText});

  final FutureProvider<List<UserProfile>> provider;
  final String emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ref
        .watch(provider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorView(where: 'follow list', error: error),
          data: (people) {
            if (people.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(Gap.xxl),
                  child: Text(
                    emptyText,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }

            return ListView.builder(
              itemCount: people.length,
              itemBuilder: (context, i) {
                final profile = people[i];
                return ListTile(
                  leading: ProfileAvatar(
                    photoUrl: profile.photoUrl,
                    name: profile.displayName,
                    radius: 20,
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (profile.verified) ...[
                        const SizedBox(width: Gap.xs),
                        const VerifiedTick(size: 14),
                      ],
                    ],
                  ),
                  subtitle: profile.handle == null
                      ? null
                      : Text(
                          '@${profile.handle}',
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.labelSmall,
                        ),
                  onTap: () => context.push('/user/${profile.uid}'),
                );
              },
            );
          },
        );
  }
}
