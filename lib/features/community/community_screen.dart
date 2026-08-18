import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../core/numerals.dart';
import '../../data/models/community.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/error_view.dart';
import '../auth/sign_in_sheet.dart';
import 'community_labels.dart';
import 'post_composer.dart';
import 'post_tile.dart';

/// One community: what it is, who is in it, and what has been posted.
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({required this.communityId, super.key});

  final String communityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(communityProvider(communityId));

    return async.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(error: error, where: 'community'),
      ),
      data: (community) {
        // A deleted community, or a stale link out of someone's chat history.
        // The rules resolve this to null rather than a permission error
        // precisely so it can say so plainly.
        if (community == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.xxl),
                child: Text(
                  l10n.communityDeleted,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return _CommunityBody(community: community);
      },
    );
  }
}

class _CommunityBody extends ConsumerWidget {
  const _CommunityBody({required this.community});

  final Community community;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final uid = ref.watch(currentUidProvider);
    final membership = ref.watch(myMembershipProvider(community.id)).value;
    final isMember = membership != null;
    final canModerate = community.moderatedBy(uid);

    // Posts are only read when they can be: watching a private community's
    // posts as an outsider is a guaranteed permission error, and an error
    // screen is the wrong answer to "you are not in this room".
    final canSeePosts = !community.isPrivate || isMember || canModerate;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          _CommunityHeader(community: community, canModerate: canModerate),
          SliverToBoxAdapter(
            child: _CommunityAbout(community: community, isMember: isMember),
          ),
        ],
        body: canSeePosts
            ? _PostFeed(community: community)
            : _PrivateNotice(message: l10n.communityPrivateNotice),
      ),
      floatingActionButton: isMember
          ? FloatingActionButton(
              onPressed: () => showPostComposer(context, ref, community),
              child: const Icon(Icons.edit_outlined),
            )
          : null,
    );
  }
}

class _CommunityHeader extends ConsumerWidget {
  const _CommunityHeader({required this.community, required this.canModerate});

  final Community community;
  final bool canModerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SliverAppBar(
      pinned: true,
      expandedHeight: community.coverUrl == null ? null : 180,
      actions: [
        IconButton(
          onPressed: () =>
              context.push('/communities/${community.id}/members'),
          icon: const Icon(Icons.people_outline),
          tooltip: l10n.communityMembersTitle,
        ),
        if (canModerate)
          IconButton(
            onPressed: () =>
                context.push('/communities/${community.id}/settings'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.communitySettings,
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          community.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        background: community.coverUrl == null
            ? null
            : Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: community.coverUrl!,
                    fit: BoxFit.cover,
                  ),
                  // The title sits on top of the photo, and food photography
                  // is bright. Without this the name disappears into a plate
                  // of rice.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CommunityAbout extends ConsumerWidget {
  const _CommunityAbout({required this.community, required this.isMember});

  final Community community;
  final bool isMember;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n
                    .communityMemberCount(community.memberCount)
                    .toNumeralStyle(numerals),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                l10n
                    .communityPostCount(community.postCount)
                    .toNumeralStyle(numerals),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Chip(
                label: Text(categoryLabel(l10n, community.category)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              if (community.isPrivate)
                Chip(
                  avatar: const Icon(Icons.lock_outline, size: 14),
                  label: Text(privacyLabel(l10n, community.privacy)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
            ],
          ),

          if (community.description != null) ...[
            const SizedBox(height: Gap.md),
            Text(community.description!, style: theme.textTheme.bodyMedium),
          ],

          if (community.rules.isNotEmpty) ...[
            const SizedBox(height: Gap.sm),
            _RulesTile(rules: community.rules),
          ],

          const SizedBox(height: Gap.md),
          JoinButton(community: community),
          const SizedBox(height: Gap.sm),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

/// Rules, collapsed.
///
/// Expanded by default they push the first post below the fold on every visit,
/// which is a cost paid by the people who already know them.
class _RulesTile extends StatelessWidget {
  const _RulesTile({required this.rules});

  final List<String> rules;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          l10n.communityRulesTitle,
          style: theme.textTheme.labelLarge,
        ),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: Gap.sm),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, rule) in rules.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${i + 1}.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(rule, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Join, ask to join, wait, or leave — whichever of the four applies.
class JoinButton extends ConsumerStatefulWidget {
  const JoinButton({required this.community, super.key});

  final Community community;

  @override
  ConsumerState<JoinButton> createState() => _JoinButtonState();
}

class _JoinButtonState extends ConsumerState<JoinButton> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Exception catch (error) {
      if (mounted) _snack('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _join() async {
    final l10n = AppLocalizations.of(context);
    if (!await requireAccount(context, ref)) return;

    // Awaited, not read: read() on a provider nothing has watched yet returns
    // null while the profile stream warms up, and the join silently did
    // nothing. Same failure that made commenting look broken.
    final me = await ref.read(myAuthorStubFuture.future);
    if (me == null || !mounted) return;

    await _run(() async {
      final joined = await ref
          .read(communityRepositoryProvider)
          .join(community: widget.community, who: me);
      if (!joined && mounted) _snack(l10n.communityRequestSent);
    });
  }

  Future<void> _leave() async {
    final l10n = AppLocalizations.of(context);
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    if (uid == widget.community.createdBy) {
      _snack(l10n.communityOwnerCannotLeave);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.communityLeaveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.communityLeave),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(
      () => ref
          .read(communityRepositoryProvider)
          .leave(community: widget.community, uid: uid),
    );
  }

  Future<void> _withdraw() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    await _run(
      () => ref
          .read(communityRepositoryProvider)
          .withdrawRequest(communityId: widget.community.id, uid: uid),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final membership = ref.watch(myMembershipProvider(widget.community.id));
    final pending = ref.watch(myJoinRequestProvider(widget.community.id));

    if (_busy) {
      return const SizedBox(
        height: 40,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (membership.value != null) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _leave,
          icon: const Icon(Icons.check),
          label: Text(l10n.communityJoined),
        ),
      );
    }

    if (pending.value ?? false) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _withdraw,
          icon: const Icon(Icons.hourglass_empty),
          label: Text(l10n.communityPending),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _join,
        child: Text(
          widget.community.needsApproval
              ? l10n.communityAskToJoin
              : l10n.communityJoin,
        ),
      ),
    );
  }
}

class _PostFeed extends ConsumerWidget {
  const _PostFeed({required this.community});

  final Community community;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final posts = ref.watch(communityPostsProvider(community.id));
    final pinned = ref.watch(pinnedPostsProvider(community.id)).value ?? [];
    final isMember =
        ref.watch(myMembershipProvider(community.id)).value != null;

    return posts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(error: error, where: 'communityPosts'),
      data: (all) {
        // Pinned posts come from their own query, so they appear in both
        // lists. Dropping them from the chronological one keeps each post on
        // screen once.
        final pinnedIds = pinned.map((p) => p.id).toSet();
        final rest = all.where((p) => !pinnedIds.contains(p.id)).toList();

        if (pinned.isEmpty && rest.isEmpty) {
          return _EmptyFeed(
            message: isMember ? l10n.communityNoPosts : l10n.communityJoinToPost,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: pinned.length + rest.length,
          itemBuilder: (context, i) => PostTile(
            community: community,
            post: i < pinned.length ? pinned[i] : rest[i - pinned.length],
          ),
        );
      },
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.xxl),
          child: Column(
            children: [
              Icon(
                Icons.forum_outlined,
                size: 40,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: Gap.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrivateNotice extends StatelessWidget {
  const _PrivateNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.xxl),
          child: Column(
            children: [
              Icon(
                Icons.lock_outline,
                size: 40,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: Gap.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
