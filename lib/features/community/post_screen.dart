import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../data/models/community.dart';
import '../../data/models/social.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/error_view.dart';
import '../../shared/profile_avatar.dart';
import '../../shared/verified_tick.dart';
import 'post_tile.dart';

/// One post and its replies.
///
/// A separate screen rather than an expanding card: a question with thirty
/// answers under it is a page, and a feed that grows a page in the middle of
/// itself loses your scroll position every time somebody replies.
class CommunityPostScreen extends ConsumerWidget {
  const CommunityPostScreen({
    required this.communityId,
    required this.postId,
    super.key,
  });

  final String communityId;
  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final community = ref.watch(communityProvider(communityId));
    final posts = ref.watch(communityPostsProvider(communityId));
    final pinned = ref.watch(pinnedPostsProvider(communityId)).value ?? [];

    return Scaffold(
      appBar: AppBar(title: Text(community.value?.name ?? '')),
      body: switch ((community, posts)) {
        (AsyncError(:final error), _) || (_, AsyncError(:final error)) =>
          ErrorView(error: error, where: 'communityPost'),
        (AsyncData(value: final c?), AsyncData(value: final list)) => () {
          // The post is found in whichever query already loaded it rather than
          // fetched again — arriving here means one of them has it, and a
          // second read would only add a spinner to a screen that has the data.
          final post = [
            ...list,
            ...pinned,
          ].where((p) => p.id == postId).firstOrNull;

          if (post == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.xxl),
                child: Text(l10n.communityDeleted, textAlign: TextAlign.center),
              ),
            );
          }
          return _PostBody(community: c, post: post);
        }(),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _PostBody extends ConsumerWidget {
  const _PostBody({required this.community, required this.post});

  final Community community;
  final CommunityPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final comments = ref.watch(
      communityPostCommentsProvider((
        communityId: community.id,
        postId: post.id,
      )),
    );
    final isMember =
        ref.watch(myMembershipProvider(community.id)).value != null;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: Gap.lg),
            children: [
              PostTile(
                community: community,
                post: post,
                showFullBody: true,
              ),
              ...switch (comments) {
                AsyncError(:final error) => [
                  ErrorView(error: error, where: 'postComments'),
                ],
                AsyncData(:final value) when value.isEmpty => [
                  Padding(
                    padding: const EdgeInsets.all(Gap.xl),
                    child: Text(
                      post.type == PostType.question
                          ? l10n.postAnswer
                          : l10n.postNoReplies,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ],
                AsyncData(:final value) => [
                  for (final comment in value)
                    _ReplyTile(
                      community: community,
                      post: post,
                      comment: comment,
                    ),
                ],
                _ => const [
                  Padding(
                    padding: EdgeInsets.all(Gap.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              },
            ],
          ),
        ),

        // Non-members see why they cannot reply rather than a disabled box
        // with no explanation.
        if (isMember)
          _ReplyComposer(community: community, post: post)
        else
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Text(
                l10n.communityJoinToPost,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReplyTile extends ConsumerWidget {
  const _ReplyTile({
    required this.community,
    required this.post,
    required this.comment,
  });

  final Community community;
  final CommunityPost post;
  final Comment comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final locale = ref.watch(activeLocaleProvider).locale.languageCode;
    final myUid = ref.watch(currentUidProvider);
    final canDelete =
        comment.author.uid == myUid || community.moderatedBy(myUid);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => context.push('/user/${comment.author.uid}'),
            child: ProfileAvatar(
              photoUrl: comment.author.photoUrl,
              name: comment.author.name,
              radius: 14,
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
                        comment.author.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    if (comment.author.verified) ...[
                      const SizedBox(width: Gap.xs),
                      const VerifiedTick(size: 12),
                    ],
                    // The person who wrote the post, answering their own
                    // question, is the most useful thing to spot at a glance.
                    if (comment.author.uid == post.author.uid) ...[
                      const SizedBox(width: Gap.xs),
                      Icon(
                        Icons.star,
                        size: 12,
                        color: theme.colorScheme.tertiary,
                      ),
                    ],
                    const Spacer(),
                    if (comment.at != null)
                      Text(
                        timeago.format(
                          comment.at!,
                          locale: locale == 'en' ? 'en' : 'ar',
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (canDelete)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        onPressed: () => ref
                            .read(communityRepositoryProvider)
                            .deletePostComment(
                              communityId: community.id,
                              postId: post.id,
                              commentId: comment.id,
                            ),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                Text(comment.text, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplyComposer extends ConsumerStatefulWidget {
  const _ReplyComposer({required this.community, required this.post});

  final Community community;
  final CommunityPost post;

  @override
  ConsumerState<_ReplyComposer> createState() => _ReplyComposerState();
}

class _ReplyComposerState extends ConsumerState<_ReplyComposer> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      // Inside the try: resolving the author can fail, and when that happened
      // on the recipe thread the spinner ran forever with nothing said.
      final author = await ref.read(myAuthorStubFuture.future);
      if (author == null) return;

      await ref
          .read(communityRepositoryProvider)
          .addPostComment(
            communityId: widget.community.id,
            postId: widget.post.id,
            comment: Comment(id: '', author: author, text: text),
          );
      _controller.clear();
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.sm, Gap.sm),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: widget.post.type == PostType.question
                      ? l10n.postAnswer
                      : l10n.postComposerHint,
                  isDense: true,
                  counterText: '',
                ),
              ),
            ),
            IconButton(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
