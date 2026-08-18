import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/brnj_theme.dart';
import '../../data/models/user_profile.dart';
import '../../data/providers.dart';
import '../../data/repositories/chat_repository.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/error_view.dart';
import '../../shared/profile_avatar.dart';
import '../../shared/verified_tick.dart';

/// Starting a conversation.
///
/// The candidate list is the people you follow. Not a search over every account
/// in the app: the first thing anyone does with an open user search is message
/// strangers, and the DM gate exists precisely to make that not work — offering
/// it here would be offering an action that mostly fails.
class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _selected = <String, UserProfile>{};
  final _title = TextEditingController();
  bool _busy = false;

  bool get _isGroup => _selected.length > 1;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _openDm(UserProfile them) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    setState(() => _busy = true);
    try {
      final me = await ref.read(myAuthorStubFuture.future);
      if (me == null) return;

      // Read the gate before writing, so a refusal can say which of the three
      // reasons applies. The rules enforce the same thing; this is only for
      // the wording, since permission-denied says nothing a person can act on.
      final followsMe = await ref.read(followsMeProvider(them.uid).future);

      final id = await ref
          .read(chatRepositoryProvider)
          .openDm(
            me: me,
            other: AuthorStub.fromMap(them.authorStub),
            theirPrivacy: them.privacy,
            theyFollowMe: followsMe,
          );
      await router.pushReplacement('/chats/$id');
    } on DmNotAllowed catch (error) {
      final name = them.displayName;
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (error.reason) {
            DmBlockReason.closed => l10n.chatDmClosed(name),
            DmBlockReason.followersOnly => l10n.chatDmFollowersOnly(name),
            DmBlockReason.blocked => l10n.chatDmBlocked,
          }),
        ),
      );
    } on Exception {
      // A rules refusal lands here — most often a block, which the client
      // cannot see and so cannot name more precisely than this.
      messenger.showSnackBar(SnackBar(content: Text(l10n.chatDmBlocked)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createGroup() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final title = _title.text.trim();
    if (title.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.chatGroupNameHint)),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final me = await ref.read(myAuthorStubFuture.future);
      if (me == null) return;

      final id = await ref
          .read(chatRepositoryProvider)
          .createGroup(
            me: me,
            others: [
              for (final profile in _selected.values)
                AuthorStub.fromMap(profile.authorStub),
            ],
            title: title,
          );
      await router.pushReplacement('/chats/$id');
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
    final uid = ref.watch(currentUidProvider);
    final candidates = uid == null
        ? const AsyncValue<List<UserProfile>>.data([])
        : ref.watch(followingProvider(uid));

    return Scaffold(
      appBar: AppBar(
        title: Text(_isGroup ? l10n.chatNewGroup : l10n.chatNewMessage),
      ),
      body: Column(
        children: [
          // Only once it is actually a group. Asking for a name before anyone
          // is picked is asking a question about something that may never
          // exist.
          if (_isGroup)
            Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: TextField(
                controller: _title,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: l10n.chatGroupNameHint,
                  isDense: true,
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l10n.chatPickPeople,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),

          Expanded(
            child: candidates.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ErrorView(error: error, where: 'newChat'),
              data: (people) {
                if (people.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.xxl),
                      child: Text(
                        l10n.chatNoOneToAdd,
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
                    final person = people[i];
                    final picked = _selected.containsKey(person.uid);

                    return ListTile(
                      leading: ProfileAvatar(
                        photoUrl: person.photoUrl,
                        name: person.displayName,
                        radius: 20,
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              person.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (person.verified) ...[
                            const SizedBox(width: Gap.xs),
                            const VerifiedTick(size: 14),
                          ],
                        ],
                      ),
                      trailing: picked
                          ? Icon(
                              Icons.check_circle,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      // One tap opens a DM; long press starts building a
                      // group. Two separate screens for that would be two
                      // screens with the same list on them.
                      onTap: _busy
                          ? null
                          : () {
                              if (_selected.isEmpty) {
                                _openDm(person);
                              } else {
                                setState(() {
                                  picked
                                      ? _selected.remove(person.uid)
                                      : _selected[person.uid] = person;
                                });
                              }
                            },
                      onLongPress: _busy
                          ? null
                          : () => setState(() {
                              picked
                                  ? _selected.remove(person.uid)
                                  : _selected[person.uid] = person;
                            }),
                    );
                  },
                );
              },
            ),
          ),

          if (_selected.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Gap.lg),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : _isGroup
                        ? _createGroup
                        : () => _openDm(_selected.values.first),
                    child: Text(
                      _isGroup ? l10n.chatNewGroup : l10n.chatNewMessage,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
