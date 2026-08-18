import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../core/numerals.dart';
import '../../data/models/chat.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/error_view.dart';
import '../../shared/profile_avatar.dart';
import '../auth/sign_in_sheet.dart';
import 'chat_labels.dart';

/// The chats tab: accepted conversations, and the ones waiting on an answer.
///
/// Requests are a separate tab rather than a section at the top of one list.
/// The gate only works if an unwanted message is somewhere you choose to go
/// and look, not something you scroll past every time you open the app.
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final requests = ref.watch(chatRequestsProvider).value ?? const <Chat>[];

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.navChats),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.chatsInbox),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.chatsRequests),
                    if (requests.isNotEmpty) ...[
                      const SizedBox(width: Gap.xs),
                      _Dot(count: requests.length),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            if (!await requireAccount(context, ref)) return;
            if (!context.mounted) return;
            await context.push('/chats/new');
          },
          child: const Icon(Icons.edit_outlined),
        ),
        body: TabBarView(
          children: [
            _ChatList(
              provider: inboxProvider,
              emptyMessage: l10n.chatsEmpty,
            ),
            _ChatList(
              provider: chatRequestsProvider,
              emptyMessage: l10n.chatsRequestsEmpty,
              note: l10n.chatsRequestNote,
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends ConsumerWidget {
  const _Dot({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count'.toNumeralStyle(numerals),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
        ),
      ),
    );
  }
}

class _ChatList extends ConsumerWidget {
  const _ChatList({
    required this.provider,
    required this.emptyMessage,
    this.note,
  });

  final Provider<AsyncValue<List<Chat>>> provider;
  final String emptyMessage;

  /// One line explaining what this tab is. Shown above the requests, because
  /// a list of strangers' names with no explanation reads as a bug.
  final String? note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(provider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(error: error, where: 'chats'),
      data: (chats) {
        if (chats.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(Gap.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.forum_outlined,
                    size: 40,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: Gap.md),
                  Text(
                    emptyMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          itemCount: chats.length + (note == null ? 0 : 1),
          itemBuilder: (context, i) {
            if (note != null && i == 0) {
              return Padding(
                padding: const EdgeInsets.all(Gap.lg),
                child: Text(
                  note!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return ChatTile(chat: chats[i - (note == null ? 0 : 1)]);
          },
        );
      },
    );
  }
}

/// One conversation in the list.
class ChatTile extends ConsumerWidget {
  const ChatTile({required this.chat, super.key});

  final Chat chat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final uid = ref.watch(currentUidProvider);
    final locale = ref.watch(activeLocaleProvider).locale.languageCode;

    final unread = chat.unreadFor(uid);
    final preview = chatPreview(l10n, chat);

    return ListTile(
      onTap: () => context.push('/chats/${chat.id}'),
      leading: chat.kind == ChatKind.dm
          ? ProfileAvatar(
              photoUrl: chat.displayPhoto(uid),
              name: chat.displayTitle(uid),
              radius: 24,
            )
          : CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Icon(
                chat.kind == ChatKind.community
                    ? Icons.groups_outlined
                    : Icons.forum_outlined,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
      title: Text(
        chat.displayTitle(uid),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: unread > 0
            ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
            : theme.textTheme.titleSmall,
      ),
      subtitle: preview.isEmpty
          ? null
          : Text(
              // In a group it matters who said it; in a DM there are only two
              // people and the name would be noise on every row.
              chat.kind == ChatKind.dm
                  ? preview
                  : '${_senderLabel(l10n, uid)}$preview',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: unread > 0
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (chat.lastMessage?.at != null)
            Text(
              timeago.format(
                chat.lastMessage!.at!,
                locale: locale == 'en' ? 'en' : 'ar',
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (unread > 0) ...[
            const SizedBox(height: Gap.xs),
            _Dot(count: unread),
          ],
        ],
      ),
    );
  }

  String _senderLabel(AppLocalizations l10n, String? myUid) {
    final sender = chat.lastMessage?.senderUid;
    if (sender == null) return '';
    if (sender == myUid) return '${l10n.chatYou}: ';
    final name = chat.members[sender]?.name ?? '';
    return name.isEmpty ? '' : '$name: ';
  }
}
