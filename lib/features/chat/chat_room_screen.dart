import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../data/models/chat.dart';
import '../../data/providers.dart';
import '../../data/repositories/safety_repository.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/error_view.dart';
import '../../shared/profile_avatar.dart';
import '../../shared/safety_actions.dart';

/// One conversation.
class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({required this.chatId, super.key});

  final String chatId;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the room is the read. Anything finer — marking each message as
    // it scrolls past — is a write per message for a badge nobody inspects
    // that closely.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = ref.read(currentUidProvider);
      if (uid == null || ref.read(isGuestProvider)) return;
      ref
          .read(chatRepositoryProvider)
          .markRead(chatId: widget.chatId, uid: uid)
          // The rule allows this only for a member. A moderator reading a
          // reported conversation is not one, and their badge write failing
          // should not take the screen down with it.
          .catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(chatProvider(widget.chatId));
    final uid = ref.watch(currentUidProvider);

    return async.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(error: error, where: 'chatRoom'),
      ),
      data: (chat) {
        if (chat == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.xxl),
                child: Text(l10n.chatsEmpty, textAlign: TextAlign.center),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: _RoomTitle(chat: chat),
            actions: [_RoomMenu(chat: chat)],
          ),
          body: Column(
            children: [
              Expanded(child: _MessageList(chat: chat)),
              // A request the recipient has not answered gets Accept/Delete
              // instead of a text field. Replying accepts it, so the buttons
              // are a shortcut rather than a wall — but they are also how
              // somebody says no without typing anything.
              if (!chat.hasAccepted(uid))
                _RequestBar(chat: chat)
              else
                MessageComposer(chat: chat),
            ],
          ),
        );
      },
    );
  }
}

class _RoomTitle extends ConsumerWidget {
  const _RoomTitle({required this.chat});

  final Chat chat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final uid = ref.watch(currentUidProvider);
    final other = chat.otherParty(uid);

    return InkWell(
      onTap: other == null ? null : () => context.push('/user/${other.uid}'),
      child: Row(
        children: [
          if (chat.kind == ChatKind.dm)
            ProfileAvatar(
              photoUrl: chat.displayPhoto(uid),
              name: chat.displayTitle(uid),
              radius: 16,
            )
          else
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Icon(
                chat.kind == ChatKind.community
                    ? Icons.groups_outlined
                    : Icons.forum_outlined,
                size: 18,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              chat.displayTitle(uid),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomMenu extends ConsumerWidget {
  const _RoomMenu({required this.chat});

  final Chat chat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final uid = ref.watch(currentUidProvider);
    final other = chat.otherParty(uid);

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) async {
        final repository = ref.read(chatRepositoryProvider);
        final router = GoRouter.of(context);

        switch (value) {
          case 'leave':
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                content: Text(l10n.chatLeaveConfirm),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l10n.actionCancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(l10n.chatLeave),
                  ),
                ],
              ),
            );
            if (confirmed != true || uid == null) return;
            await repository.leave(chatId: chat.id, uid: uid);
            router.pop();

          case 'report':
            if (!context.mounted || other == null) return;
            await showReportSheet(
              context,
              ref,
              targetType: ReportTarget.message,
              targetId: chat.id,
              targetOwner: other.uid,
            );
        }
      },
      itemBuilder: (context) => [
        // A DM has nothing to leave — leaving would just hide it, and delete
        // is what the requests tab is for.
        if (chat.kind != ChatKind.dm)
          PopupMenuItem(value: 'leave', child: Text(l10n.chatLeave)),
        if (other != null)
          PopupMenuItem(value: 'report', child: Text(l10n.actionReport)),
      ],
    );
  }
}

class _MessageList extends ConsumerWidget {
  const _MessageList({required this.chat});

  final Chat chat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(messagesProvider(chat.id));
    final uid = ref.watch(currentUidProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(error: error, where: 'messages'),
      data: (messages) {
        if (messages.isEmpty) {
          return Center(
            child: Text(
              l10n.chatNoMessages,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        // `reverse` with a newest-first query: the newest message is at index
        // zero and renders at the bottom, which means opening a conversation
        // lands on the latest without an animated scroll, and loading older
        // ones does not move what is on screen.
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          itemCount: messages.length,
          itemBuilder: (context, i) => MessageBubble(
            chat: chat,
            message: messages[i],
            mine: messages[i].author.uid == uid,
            // In a group, consecutive messages from one person only need the
            // name once.
            showAuthor:
                chat.kind != ChatKind.dm &&
                messages[i].author.uid != uid &&
                (i == messages.length - 1 ||
                    messages[i + 1].author.uid != messages[i].author.uid),
          ),
        );
      },
    );
  }
}

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    required this.chat,
    required this.message,
    required this.mine,
    required this.showAuthor,
    super.key,
  });

  final Chat chat;
  final Message message;
  final bool mine;
  final bool showAuthor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(activeLocaleProvider).locale.languageCode;

    final background = mine
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = mine
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: GestureDetector(
        onLongPress: mine
            ? () => ref
                  .read(chatRepositoryProvider)
                  .deleteMessage(chatId: chat.id, messageId: message.id)
            : null,
        child: Container(
          constraints: BoxConstraints(
            // Never full width: a bubble that reaches both edges is
            // indistinguishable from the one before it.
            maxWidth: MediaQuery.sizeOf(context).width * 0.76,
          ),
          margin: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.xs,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.sm,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showAuthor)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    message.author.name,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),

              if (message.mediaUrl != null &&
                  message.kind == MessageKind.image) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: message.mediaUrl!,
                    fit: BoxFit.cover,
                  ),
                ),
                if (message.text.isNotEmpty) const SizedBox(height: Gap.xs),
              ],

              if (message.kind == MessageKind.recipe &&
                  message.recipeId != null)
                TextButton.icon(
                  onPressed: () => context.push('/recipe/${message.recipeId}'),
                  icon: const Icon(Icons.restaurant_menu, size: 18),
                  label: Text(l10n.chatMessageRecipe),
                ),

              if (message.text.isNotEmpty)
                Text(
                  message.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                  ),
                ),

              if (message.at != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    timeago.format(
                      message.at!,
                      locale: locale == 'en' ? 'en' : 'ar',
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: foreground.withValues(alpha: 0.6),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Accept or delete, for a conversation the recipient has not answered.
class _RequestBar extends ConsumerWidget {
  const _RequestBar({required this.chat});

  final Chat chat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final uid = ref.watch(currentUidProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          children: [
            Text(
              l10n.chatsRequestNote,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final router = GoRouter.of(context);
                      await ref
                          .read(chatRepositoryProvider)
                          .declineRequest(chat.id);
                      router.pop();
                    },
                    child: Text(l10n.chatDelete),
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: FilledButton(
                    onPressed: uid == null
                        ? null
                        : () => ref
                              .read(chatRepositoryProvider)
                              .accept(chatId: chat.id, uid: uid),
                    child: Text(l10n.chatAccept),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The text field and the send button.
class MessageComposer extends ConsumerStatefulWidget {
  const MessageComposer({required this.chat, super.key});

  final Chat chat;

  @override
  ConsumerState<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends ConsumerState<MessageComposer> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send({String? mediaUrl, MessageKind? kind}) async {
    final text = _controller.text.trim();
    if (text.isEmpty && mediaUrl == null) return;

    setState(() => _busy = true);
    try {
      // Inside the try: resolving the author can fail, and when it did on the
      // recipe thread the spinner ran forever with nothing said.
      final me = await ref.read(myAuthorStubFuture.future);
      if (me == null) return;

      await ref
          .read(chatRepositoryProvider)
          .send(
            chatId: widget.chat.id,
            message: Message(
              id: '',
              author: me,
              kind: kind ?? MessageKind.text,
              text: text,
              mediaUrl: mediaUrl,
            ),
          );
      _controller.clear();
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      final url = await ref
          .read(mediaRepositoryProvider)
          .uploadChatImage(chatId: widget.chat.id, filePath: picked.path);
      await _send(mediaUrl: url, kind: MessageKind.image);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.sm, Gap.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: _busy ? null : _sendPhoto,
              icon: const Icon(Icons.image_outlined),
              tooltip: l10n.chatMessagePhoto,
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 5,
                maxLength: 4000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: l10n.chatMessageHint,
                  isDense: true,
                  counterText: '',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            IconButton.filled(
              onPressed: _busy ? null : () => _send(),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              tooltip: l10n.chatSend,
            ),
          ],
        ),
      ),
    );
  }
}
