import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../data/models/social.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/error_view.dart';

/// The notification list.
///
/// Push is a courtesy; this is the durable record. Without it a notification
/// that was missed, swiped away, or arrived while the phone was off is simply
/// lost — and on a device that never got an APNs token, push never arrives at
/// all, which is most Android phones in Iraq with no Play Services.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the screen is the read. Making people tap each one would leave
    // the badge on forever.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = ref.read(currentUidProvider);
      if (uid != null && !ref.read(isGuestProvider)) {
        ref.read(notificationRepositoryProvider).markAllRead(uid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationsTitle)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(error: error),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Gap.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.notifications_none,
                      size: 40,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: Gap.md),
                    Text(
                      l10n.notificationsEmpty,
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
            itemCount: items.length,
            itemBuilder: (context, i) => _NotificationTile(item: items[i]),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.item});

  final AppNotification item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(activeLocaleProvider).locale.languageCode;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          _icon,
          size: 18,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(_title(l10n)),
      subtitle: item.body == null
          ? null
          : Text(item.body!, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: item.at == null
          ? null
          : Text(
              timeago.format(item.at!, locale: locale == 'en' ? 'en' : 'ar'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      // Unread stays visually distinct even though opening the screen marks
      // everything read — the tint is gone next time, which is the point.
      tileColor: item.read
          ? null
          : theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
      onTap: () {
        final route = item.route;
        if (route != null) context.push(route);
      },
    );
  }

  IconData get _icon => switch (item.type) {
    NotificationType.like => Icons.favorite,
    NotificationType.cooked => Icons.local_fire_department,
    NotificationType.comment => Icons.chat_bubble_outline,
    NotificationType.follow => Icons.person_add_alt,
    NotificationType.planCopied => Icons.copy_all_outlined,
    NotificationType.communityJoinRequest => Icons.person_add_alt_1,
    NotificationType.communityApproved => Icons.groups,
    NotificationType.communityPost => Icons.forum_outlined,
    NotificationType.unknown => Icons.notifications_none,
  };

  String _title(AppLocalizations l10n) {
    final who = item.actorName ?? '';
    return switch (item.type) {
      NotificationType.like => l10n.notificationLiked(who),
      NotificationType.cooked => l10n.notificationCooked(who),
      NotificationType.comment => l10n.notificationCommented(who),
      NotificationType.follow => l10n.notificationFollowed(who),
      NotificationType.planCopied => l10n.notificationCopiedWeek(who),
      NotificationType.communityJoinRequest => l10n.notificationJoinRequest(who),
      NotificationType.communityApproved => l10n.notificationCommunityApproved(
        who,
      ),
      NotificationType.communityPost => l10n.notificationCommunityPost(who),
      NotificationType.unknown => who,
    };
  }
}
