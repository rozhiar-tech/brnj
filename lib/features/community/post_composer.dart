import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/brnj_theme.dart';
import '../../data/models/community.dart';
import '../../data/models/recipe.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import 'community_labels.dart';

/// Opens the post composer for [community].
Future<void> showPostComposer(
  BuildContext context,
  WidgetRef ref,
  Community community,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _PostComposer(community: community),
);

/// Writing a post.
///
/// One sheet for all four types rather than four entry points: the difference
/// between a post and a question is one chip, and asking someone to decide
/// which kind of thing they are writing before they have written it is how you
/// get people not writing.
class _PostComposer extends ConsumerStatefulWidget {
  const _PostComposer({required this.community});

  final Community community;

  @override
  ConsumerState<_PostComposer> createState() => _PostComposerState();
}

class _PostComposerState extends ConsumerState<_PostComposer> {
  final _body = TextEditingController();
  PostType _type = PostType.text;
  String? _mediaUrl;
  String? _recipeId;
  bool _busy = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      final url = await ref
          .read(mediaRepositoryProvider)
          .uploadCommunityImage(
            communityId: widget.community.id,
            filePath: picked.path,
          );
      if (mounted) {
        setState(() {
          _mediaUrl = url;
          _type = PostType.photo;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickRecipe() async {
    final recipes = await ref.read(myRecipesProvider.future);
    if (!mounted) return;

    final published = recipes
        .where((r) => r.status == RecipeStatus.published)
        .toList();
    if (published.isEmpty) return;

    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final recipe in published)
              ListTile(
                title: Text(recipe.title),
                onTap: () => Navigator.pop(context, recipe.id),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _recipeId = chosen;
      _type = PostType.recipe;
    });
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // A photo post can carry no words; a text post cannot be nothing at all.
    if (_body.text.trim().isEmpty && _mediaUrl == null && _recipeId == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.postEmptyBody)));
      return;
    }

    setState(() => _busy = true);
    try {
      final me = await ref.read(myAuthorStubFuture.future);
      if (me == null) return;

      await ref
          .read(communityRepositoryProvider)
          .addPost(
            communityId: widget.community.id,
            post: CommunityPost(
              id: '',
              author: me,
              type: _type,
              body: _body.text,
              mediaUrl: _mediaUrl,
              recipeId: _recipeId,
            ),
          );
      navigator.pop();
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      // Lifts the sheet clear of the keyboard. Without it the send button sits
      // underneath it and the sheet looks broken.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.community.name, style: theme.textTheme.titleSmall),
              const SizedBox(height: Gap.md),

              Wrap(
                spacing: Gap.sm,
                children: [
                  for (final type in [PostType.text, PostType.question])
                    ChoiceChip(
                      label: Text(postTypeLabel(l10n, type)),
                      selected: _type == type,
                      onSelected: (_) => setState(() => _type = type),
                    ),
                ],
              ),
              const SizedBox(height: Gap.md),

              TextField(
                controller: _body,
                autofocus: true,
                maxLines: 6,
                minLines: 3,
                maxLength: 5000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: _type == PostType.question
                      ? l10n.postQuestionHint
                      : l10n.postComposerHint,
                  border: const OutlineInputBorder(),
                ),
              ),

              if (_mediaUrl != null || _recipeId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.sm),
                  child: Chip(
                    label: Text(
                      _mediaUrl != null
                          ? l10n.postTypePhoto
                          : l10n.postTypeRecipe,
                    ),
                    onDeleted: () => setState(() {
                      _mediaUrl = null;
                      _recipeId = null;
                      _type = PostType.text;
                    }),
                  ),
                ),

              Row(
                children: [
                  IconButton(
                    onPressed: _busy ? null : _pickPhoto,
                    icon: const Icon(Icons.image_outlined),
                    tooltip: l10n.postTypePhoto,
                  ),
                  IconButton(
                    onPressed: _busy ? null : _pickRecipe,
                    icon: const Icon(Icons.restaurant_menu),
                    tooltip: l10n.postTypeRecipe,
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.postPublish),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
