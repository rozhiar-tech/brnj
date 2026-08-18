import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/brnj_theme.dart';
import '../../data/models/community.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/error_view.dart';
import '../../shared/profile_avatar.dart';
import '../../shared/verified_tick.dart';
import 'community_labels.dart';

/// Members, and — for a moderator — the queue of people asking to get in.
///
/// The queue is a tab rather than a separate screen so that the notification
/// telling a moderator someone is waiting lands one tap from the approve
/// button.
class CommunityMembersScreen extends ConsumerWidget {
  const CommunityMembersScreen({required this.communityId, super.key});

  final String communityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(communityProvider(communityId));

    return async.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(error: error, where: 'communityMembers'),
      ),
      data: (community) {
        if (community == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(l10n.communityDeleted)),
          );
        }

        final canModerate = community.moderatedBy(
          ref.watch(currentUidProvider),
        );

        // One tab for everyone else. A tab bar with a single tab is noise, so
        // it only appears when there is a second thing to switch to.
        if (!canModerate) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.communityMembersTitle)),
            body: _MemberList(community: community, canModerate: false),
          );
        }

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(community.name),
              bottom: TabBar(
                tabs: [
                  Tab(text: l10n.communityMembersTitle),
                  Tab(text: l10n.communityRequestsTitle),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _MemberList(community: community, canModerate: true),
                _RequestList(community: community),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MemberList extends ConsumerWidget {
  const _MemberList({required this.community, required this.canModerate});

  final Community community;
  final bool canModerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(communityMembersProvider(community.id));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(error: error, where: 'members'),
      data: (members) => ListView.builder(
        itemCount: members.length,
        itemBuilder: (context, i) => _MemberTile(
          community: community,
          member: members[i],
          canModerate: canModerate,
        ),
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.community,
    required this.member,
    required this.canModerate,
  });

  final Community community;
  final CommunityMember member;
  final bool canModerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final label = roleLabel(l10n, member.role);

    // The owner is not demotable or removable by anyone, including themselves:
    // a community with nobody who can approve or promote is stuck for good.
    final isOwner = member.uid == community.createdBy;
    final isModerator = community.moderators.contains(member.uid);

    return ListTile(
      onTap: () => context.push('/user/${member.uid}'),
      leading: ProfileAvatar(
        photoUrl: member.author.photoUrl,
        name: member.author.name,
        radius: 20,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              member.author.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (member.author.verified) ...[
            const SizedBox(width: Gap.xs),
            const VerifiedTick(size: 14),
          ],
        ],
      ),
      subtitle: label == null
          ? null
          : Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
      trailing: !canModerate || isOwner
          ? null
          : PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) async {
                final repository = ref.read(communityRepositoryProvider);
                switch (value) {
                  case 'promote':
                    await repository.setModerator(
                      communityId: community.id,
                      uid: member.uid,
                      value: true,
                    );
                  case 'demote':
                    await repository.setModerator(
                      communityId: community.id,
                      uid: member.uid,
                      value: false,
                    );
                  case 'remove':
                    await repository.removeMember(
                      communityId: community.id,
                      uid: member.uid,
                    );
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: isModerator ? 'demote' : 'promote',
                  child: Text(
                    isModerator
                        ? l10n.communityRemoveModerator
                        : l10n.communityMakeModerator,
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Text(l10n.communityRemoveMember),
                ),
              ],
            ),
    );
  }
}

class _RequestList extends ConsumerWidget {
  const _RequestList({required this.community});

  final Community community;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(communityRequestsProvider(community.id));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(error: error, where: 'requests'),
      data: (requests) {
        if (requests.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(Gap.xxl),
              child: Text(
                l10n.communityNoRequests,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }

        return ListView.builder(
          itemCount: requests.length,
          itemBuilder: (context, i) {
            final request = requests[i];
            return ListTile(
              onTap: () => context.push('/user/${request.uid}'),
              leading: ProfileAvatar(
                photoUrl: request.author.photoUrl,
                name: request.author.name,
                radius: 20,
              ),
              title: Text(
                request.author.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.communityReject,
                    onPressed: () => ref
                        .read(communityRepositoryProvider)
                        .reject(
                          communityId: community.id,
                          uid: request.uid,
                        ),
                    icon: const Icon(Icons.close),
                  ),
                  IconButton.filled(
                    tooltip: l10n.communityApprove,
                    onPressed: () => ref
                        .read(communityRepositoryProvider)
                        .approve(
                          communityId: community.id,
                          request: request,
                        ),
                    icon: const Icon(Icons.check),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
