import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/brnj_theme.dart';
import '../../data/models/user_profile.dart';
import '../../data/providers.dart';
import '../../data/repositories/admin_repository.dart';
import '../../l10n/gen/app_localizations.dart';
import '../profile/profile_screen.dart';

final _verificationQueueProvider = StreamProvider<List<VerificationRequest>>(
  (ref) => ref.watch(adminRepositoryProvider).watchVerificationRequests(),
);

final _reportsQueueProvider = StreamProvider<List<ModerationReport>>(
  (ref) => ref.watch(adminRepositoryProvider).watchOpenReports(),
);

/// The moderation console.
///
/// Deliberately inside the app rather than a separate web tool: reviewing
/// reports in the Firebase console is slow enough that it doesn't get done, and
/// a queue nobody works is the same as no moderation at all.
///
/// Access is gated on the Auth token, not on a user-document field — the token
/// is what the security rules and the callables actually trust.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final claimsAsync = ref.watch(adminClaimsProvider);

    return claimsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.errorGeneric)),
      ),
      data: (claims) {
        if (!claims.canModerate) return const _NoAccess();

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(l10n.adminTitle),
              leading: IconButton(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.close),
              ),
              bottom: TabBar(
                tabs: [
                  Tab(text: l10n.adminVerification),
                  Tab(text: l10n.adminReports),
                  Tab(text: l10n.adminUsers),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                const _VerificationQueue(),
                const _ReportsQueue(),
                _UserLookup(canPromote: claims.admin),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shown to anyone who reaches the route without the claim.
///
/// Says plainly that the screen exists and they can't use it, rather than
/// pretending the route is missing — a moderator whose claim hasn't refreshed
/// yet needs to be told to sign in again, not told they typed a bad URL.
class _NoAccess extends ConsumerWidget {
  const _NoAccess();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: Gap.lg),
              Text(l10n.adminNoAccess, textAlign: TextAlign.center),
              const SizedBox(height: Gap.sm),
              Text(
                l10n.adminNoAccessHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Gap.lg),
              OutlinedButton(
                // A claim granted a minute ago is not on this device's token
                // yet. Forcing a refresh is faster than explaining that.
                onPressed: () async {
                  await ref.read(adminRepositoryProvider).claims(refresh: true);
                  ref.invalidate(adminClaimsProvider);
                },
                child: Text(l10n.actionRetry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerificationQueue extends ConsumerWidget {
  const _VerificationQueue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final queueAsync = ref.watch(_verificationQueueProvider);

    return queueAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _QueueError(error: error),
      data: (requests) {
        if (requests.isEmpty) return _EmptyQueue(message: l10n.adminQueueEmpty);

        return ListView.builder(
          padding: const EdgeInsets.all(Gap.lg),
          itemCount: requests.length,
          itemBuilder: (context, i) => _VerificationCard(request: requests[i]),
        );
      },
    );
  }
}

class _VerificationCard extends ConsumerStatefulWidget {
  const _VerificationCard({required this.request});

  final VerificationRequest request;

  @override
  ConsumerState<_VerificationCard> createState() => _VerificationCardState();
}

class _VerificationCardState extends ConsumerState<_VerificationCard> {
  bool _working = false;

  Future<void> _decide(bool approve) async {
    setState(() => _working = true);
    try {
      final repository = ref.read(adminRepositoryProvider);
      if (approve) {
        await repository.setVerified(uid: widget.request.uid, verified: true);
      } else {
        await repository.declineVerification(widget.request.uid);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final profile = widget.request.profile;

    return Card(
      margin: const EdgeInsets.only(bottom: Gap.md),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProfileAvatar(
                  photoUrl: profile?.photoUrl,
                  name: profile?.displayName ?? '?',
                  radius: 20,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.displayName ?? widget.request.uid,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (profile?.handle != null)
                        Text(
                          '@${profile!.handle}',
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                // The numbers a reviewer actually needs: does this person
                // publish, and does anyone follow them.
                _MiniStat(
                  label: l10n.profileRecipes,
                  value: profile?.counts.recipes ?? 0,
                ),
                const SizedBox(width: Gap.md),
                _MiniStat(
                  label: l10n.profileFollowers,
                  value: profile?.counts.followers ?? 0,
                ),
              ],
            ),
            if (widget.request.note.isNotEmpty) ...[
              const SizedBox(height: Gap.md),
              Text(widget.request.note, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: Gap.md),
            Row(
              children: [
                TextButton(
                  onPressed: _working ? null : () => _decide(false),
                  child: Text(l10n.adminDecline),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _working ? null : () => _decide(true),
                  child: _working
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.adminApprove),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportsQueue extends ConsumerWidget {
  const _ReportsQueue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final reportsAsync = ref.watch(_reportsQueueProvider);

    return reportsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _QueueError(error: error),
      data: (reports) {
        if (reports.isEmpty) return _EmptyQueue(message: l10n.adminQueueEmpty);

        return ListView.builder(
          padding: const EdgeInsets.all(Gap.lg),
          itemCount: reports.length,
          itemBuilder: (context, i) {
            final report = reports[i];
            return Card(
              margin: const EdgeInsets.only(bottom: Gap.md),
              child: Padding(
                padding: const EdgeInsets.all(Gap.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${report.targetType} · ${report.reason}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: Gap.sm),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => ref
                              .read(adminRepositoryProvider)
                              .resolveReport(
                                reportId: report.id,
                                outcome: 'dismissed',
                              ),
                          child: Text(l10n.adminDismiss),
                        ),
                        const Spacer(),
                        // Hide rather than delete: reversible, and it buys time
                        // for a second, more deliberate decision.
                        FilledButton.tonal(
                          onPressed: () async {
                            final repository = ref.read(adminRepositoryProvider);
                            await repository.hideContent(
                              targetType: report.targetType,
                              targetId: report.targetId,
                            );
                            await repository.resolveReport(
                              reportId: report.id,
                              outcome: 'upheld',
                            );
                          },
                          child: Text(l10n.adminHide),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _UserLookup extends ConsumerStatefulWidget {
  const _UserLookup({required this.canPromote});

  final bool canPromote;

  @override
  ConsumerState<_UserLookup> createState() => _UserLookupState();
}

class _UserLookupState extends ConsumerState<_UserLookup> {
  final _controller = TextEditingController();
  UserProfile? _found;
  bool _searching = false;
  String? _message;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _message = null;
    });
    final profile = await ref
        .read(adminRepositoryProvider)
        .findByHandle(_controller.text);
    if (mounted) {
      setState(() {
        _found = profile;
        _searching = false;
        _message = profile == null ? 'Not found' : null;
      });
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) setState(() => _message = done);
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = _found;

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        TextField(
          controller: _controller,
          textDirection: TextDirection.ltr,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: l10n.profileHandle,
            prefixText: '@',
            suffixIcon: IconButton(
              onPressed: _searching ? null : _search,
              icon: const Icon(Icons.search),
            ),
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: Gap.md),
          Text(_message!, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (profile != null) ...[
          const SizedBox(height: Gap.lg),
          ListTile(
            leading: ProfileAvatar(
              photoUrl: profile.photoUrl,
              name: profile.displayName,
              radius: 20,
            ),
            title: Text(profile.displayName),
            subtitle: Text(profile.uid, style: const TextStyle(fontSize: 11)),
          ),
          const Divider(),
          SwitchListTile(
            title: Text(l10n.verifiedBadge),
            value: profile.verified,
            onChanged: (value) => _run(
              () => ref
                  .read(adminRepositoryProvider)
                  .setVerified(uid: profile.uid, verified: value),
              'Updated',
            ),
          ),
          if (widget.canPromote)
            ListTile(
              title: Text(l10n.adminMakeModerator),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _run(
                () => ref
                    .read(adminRepositoryProvider)
                    .setModerator(uid: profile.uid, moderator: true),
                'Updated',
              ),
            ),
        ],
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text('$value', style: theme.textTheme.titleSmall),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: Gap.md),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueError extends StatelessWidget {
  const _QueueError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xxl),
        child: Text('$error', textAlign: TextAlign.center),
      ),
    );
  }
}
