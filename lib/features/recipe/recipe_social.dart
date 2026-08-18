import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../core/numerals.dart';
import '../../data/models/social.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../data/repositories/safety_repository.dart';
import '../../shared/safety_actions.dart';
import '../../shared/verified_tick.dart';
import '../auth/sign_in_sheet.dart';
import '../profile/profile_screen.dart';
import 'cooked_sheet.dart';

/// The "I cooked this" gallery.
///
/// Sits above the comments, because it is the reason to read them. Someone
/// else's imperfect photo of the same dish is what says "you can do this" far
/// better than the author's styled cover shot.
class CookedGallery extends ConsumerWidget {
  const CookedGallery({required this.recipeId, super.key});

  final String recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);
    final posts = ref.watch(cookedPostsProvider(recipeId)).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l10n.recipeCookedThis, style: theme.textTheme.titleMedium),
            const SizedBox(width: Gap.sm),
            Text(
              formatCount(posts.length, style: numerals),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),

        if (posts.isEmpty)
          Text(
            l10n.cookedGalleryEmpty,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          )
        else
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: posts.length,
              separatorBuilder: (_, _) => const SizedBox(width: Gap.md),
              itemBuilder: (context, i) => _CookedCard(post: posts[i]),
            ),
          ),

        const SizedBox(height: Gap.md),
        OutlinedButton.icon(
          onPressed: () => showCookedSheet(context, ref, recipeId: recipeId),
          icon: const Icon(Icons.add_a_photo_outlined, size: 18),
          label: Text(
            ref.watch(hasCookedProvider(recipeId)).value ?? false
                ? l10n.cookedUpdateMine
                : l10n.recipeCookedThis,
          ),
        ),
      ],
    );
  }
}

class _CookedCard extends StatelessWidget {
  const _CookedCard({required this.post});

  final CookedPost post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: post.hasPhoto
                  ? CachedNetworkImage(
                      imageUrl: post.photoUrl!,
                      width: 130,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 130,
                      color: theme.colorScheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(Gap.sm),
                      // A note without a photo is still a contribution and
                      // still gets a card — requiring a photo would have
                      // filtered these people out at the door.
                      child: Text(
                        post.note ?? '',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: Gap.xs),
          Row(
            children: [
              Flexible(
                child: Text(
                  post.author.name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (post.author.verified) ...[
                const SizedBox(width: 2),
                const VerifiedTick(size: 11),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The conversation under a recipe.
///
/// Oldest first, because it reads as a conversation rather than a feed. The
/// author's own replies are tinted, since "the person who wrote this answered"
/// is the single most useful thing to be able to spot at a glance.
class CommentThread extends ConsumerStatefulWidget {
  const CommentThread({
    required this.recipeId,
    required this.recipeAuthorUid,
    super.key,
  });

  final String recipeId;
  final String recipeAuthorUid;

  @override
  ConsumerState<CommentThread> createState() => _CommentThreadState();
}

class _CommentThreadState extends ConsumerState<CommentThread> {
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
    if (!await requireAccount(context, ref)) return;

    final author = ref.read(myAuthorStubProvider);
    if (author == null) return;

    setState(() => _sending = true);
    try {
      await ref.read(recipeRepositoryProvider).addComment(
        recipeId: widget.recipeId,
        author: author,
        text: text,
      );
      _controller.clear();
    } catch (error) {
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
    final theme = Theme.of(context);
    final comments = ref.watch(commentsProvider(widget.recipeId)).value ?? const [];
    final myUid = ref.watch(currentUidProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.commentsTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: Gap.md),

        if (comments.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: Text(
              l10n.commentsEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          )
        else
          for (final comment in comments)
            _CommentTile(
              comment: comment,
              isRecipeAuthor: comment.author.uid == widget.recipeAuthorUid,
              canDelete:
                  comment.author.uid == myUid || myUid == widget.recipeAuthorUid,
              onDelete: () => ref.read(recipeRepositoryProvider).deleteComment(
                recipeId: widget.recipeId,
                commentId: comment.id,
              ),
            ),

        const SizedBox(height: Gap.md),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: l10n.commentsHint,
                  counterText: '',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: Gap.sm),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ],
    );
  }
}

class _CommentTile extends ConsumerWidget {
  const _CommentTile({
    required this.comment,
    required this.isRecipeAuthor,
    required this.canDelete,
    required this.onDelete,
  });

  final Comment comment;
  final bool isRecipeAuthor;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(activeLocaleProvider).locale.languageCode;

    return Container(
      margin: const EdgeInsets.only(bottom: Gap.md),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: isRecipeAuthor
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
            : theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => context.push('/user/${comment.author.uid}'),
                child: ProfileAvatar(
                  photoUrl: comment.author.photoUrl,
                  name: comment.author.name,
                  radius: 12,
                ),
              ),
              const SizedBox(width: Gap.sm),
              Flexible(
                child: Text(
                  comment.author.name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              if (comment.author.verified) ...[
                const SizedBox(width: Gap.xs),
                const VerifiedTick(size: 13),
              ],
              if (isRecipeAuthor) ...[
                const SizedBox(width: Gap.sm),
                Text(
                  l10n.commentsAuthorTag,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
              const Spacer(),
              if (comment.at != null)
                Text(
                  // timeago carries ar; Kurdish falls back to it, which is
                  // closer than English for a Sorani or Badini reader.
                  timeago.format(
                    comment.at!,
                    locale: locale == 'en' ? 'en' : 'ar',
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (!canDelete)
                SafetyMenu(
                  targetType: ReportTarget.comment,
                  targetId: comment.id,
                  targetOwner: comment.author.uid,
                ),
              if (canDelete)
                InkWell(
                  onTap: onDelete,
                  child: Padding(
                    padding: const EdgeInsets.only(left: Gap.sm),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text(comment.text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
