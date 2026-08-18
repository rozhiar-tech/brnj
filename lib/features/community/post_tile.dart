import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../core/numerals.dart';
import '../../data/models/community.dart';
import '../../data/providers.dart';
import '../../data/repositories/safety_repository.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/profile_avatar.dart';
import '../../shared/safety_actions.dart';
import '../../shared/verified_tick.dart';

/// One post in a community feed.
class PostTile extends ConsumerWidget {
  const PostTile({
    required this.community,
    required this.post,
    this.showFullBody = false,
    super.key,
  });

  final Community community;
  final CommunityPost post;

  /// The feed truncates; the post's own screen does not.
  final bool showFullBody;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);
    final locale = ref.watch(activeLocaleProvider).locale.languageCode;
    final uid = ref.watch(currentUidProvider);

    final isAuthor = post.author.uid == uid;
    final canModerate = community.moderatedBy(uid);

    return InkWell(
      onTap: showFullBody
          ? null
          : () => context.push(
              '/communities/${community.id}/post/${post.id}',
            ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.sm, Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.pinned)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.xs),
                child: Row(
                  children: [
                    Icon(
                      Icons.push_pin,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: Gap.xs),
                    Text(
                      l10n.postPinned,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => context.push('/user/${post.author.uid}'),
                  child: ProfileAvatar(
                    photoUrl: post.author.photoUrl,
                    name: post.author.name,
                    radius: 18,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.author.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                          if (post.author.verified) ...[
                            const SizedBox(width: Gap.xs),
                            const VerifiedTick(size: 14),
                          ],
                        ],
                      ),
                      Row(
                        children: [
                          if (post.type == PostType.question)
                            Padding(
                              padding: const EdgeInsets.only(right: Gap.xs),
                              child: Icon(
                                Icons.help_outline,
                                size: 12,
                                color: theme.colorScheme.tertiary,
                              ),
                            ),
                          if (post.createdAt != null)
                            Text(
                              timeago.format(
                                post.createdAt!,
                                locale: locale == 'en' ? 'en' : 'ar',
                              ),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                _PostMenu(
                  community: community,
                  post: post,
                  isAuthor: isAuthor,
                  canModerate: canModerate,
                ),
              ],
            ),

            if (post.body.isNotEmpty) ...[
              const SizedBox(height: Gap.sm),
              Text(
                post.body,
                maxLines: showFullBody ? null : 6,
                overflow: showFullBody ? null : TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ],

            if (post.mediaUrl != null) ...[
              const SizedBox(height: Gap.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: post.mediaUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],

            // A recipe shared into a community is a link out, not a copy: the
            // recipe keeps one home, one view count, and one comment thread.
            if (post.recipeId != null) ...[
              const SizedBox(height: Gap.md),
              OutlinedButton.icon(
                onPressed: () => context.push('/recipe/${post.recipeId}'),
                icon: const Icon(Icons.restaurant_menu, size: 18),
                label: Text(l10n.postTypeRecipe),
              ),
            ],

            const SizedBox(height: Gap.sm),
            Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: Gap.xs),
                Text(
                  post.commentCount == 0
                      // A question with nothing under it reads differently
                      // from a post with nothing under it — one is waiting.
                      ? (post.type == PostType.question
                            ? l10n.postAnswer
                            : l10n.postNoReplies)
                      : l10n
                            .postReplyCount(post.commentCount)
                            .toNumeralStyle(numerals),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.xs),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
          ],
        ),
      ),
    );
  }
}

/// Delete, pin, or report — whichever the viewer is entitled to.
class _PostMenu extends ConsumerWidget {
  const _PostMenu({
    required this.community,
    required this.post,
    required this.isAuthor,
    required this.canModerate,
  });

  final Community community;
  final CommunityPost post;
  final bool isAuthor;
  final bool canModerate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repository = ref.watch(communityRepositoryProvider);

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz),
      onSelected: (value) async {
        switch (value) {
          case 'pin':
            await repository.setPinned(
              communityId: community.id,
              postId: post.id,
              pinned: !post.pinned,
            );
          case 'delete':
            await repository.deletePost(
              communityId: community.id,
              postId: post.id,
            );
          case 'report':
            if (!context.mounted) return;
            await showReportSheet(
              context,
              ref,
              targetType: ReportTarget.communityPost,
              targetId: post.id,
              targetOwner: post.author.uid,
            );
        }
      },
      itemBuilder: (context) => [
        if (canModerate)
          PopupMenuItem(
            value: 'pin',
            child: Text(post.pinned ? l10n.postUnpin : l10n.postPin),
          ),
        if (isAuthor || canModerate)
          PopupMenuItem(value: 'delete', child: Text(l10n.postDelete)),
        if (!isAuthor)
          PopupMenuItem(value: 'report', child: Text(l10n.actionReport)),
      ],
    );
  }
}
