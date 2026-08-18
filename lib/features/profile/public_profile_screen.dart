import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../core/numerals.dart';
import '../../data/models/user_profile.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/error_view.dart';
import 'package:go_router/go_router.dart';

import '../../core/iraqi_week.dart';
import '../../shared/recipe_card.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/safety_repository.dart';
import '../../shared/safety_actions.dart';
import '../../shared/verified_tick.dart';
import '../auth/sign_in_sheet.dart';
import '../../shared/profile_avatar.dart';
import 'profile_screen.dart';

/// Someone else's profile.
///
/// The only place following happens, which makes it the thing standing between
/// the Following feed and being permanently empty.
class PublicProfileScreen extends ConsumerWidget {
  const PublicProfileScreen({required this.uid, super.key});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider(uid));
    final myUid = ref.watch(currentUidProvider);

    // Your own profile has different actions — editing, not following — so
    // send yourself to the real one rather than showing a follow button that
    // makes no sense.
    if (myUid == uid) return const ProfileScreen();

    return Scaffold(
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(error: error),
        // A profile that isn't there is not a failure — it is an answer, and
        // "something went wrong" sends people looking for a bug that isn't one.
        data: (profile) => profile == null
            ? const _ProfileNotFound()
            : _Body(profile: profile),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);
    final recipes =
        ref.watch(userRecipesProvider(profile.uid)).value ?? const [];

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          title: Text(profile.displayName),
          actions: [
            SafetyMenu(
              targetType: ReportTarget.profile,
              targetId: profile.uid,
              targetOwner: profile.uid,
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.all(Gap.xl),
          sliver: SliverList.list(
            children: [
              Center(
                child: ProfileAvatar(
                  photoUrl: profile.photoUrl,
                  name: profile.displayName,
                ),
              ),
              const SizedBox(height: Gap.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      profile.displayName,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  if (profile.verified) ...[
                    const SizedBox(width: Gap.sm),
                    const VerifiedTick(size: 20),
                  ],
                ],
              ),
              if (profile.handle != null)
                Text(
                  '@${profile.handle}',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (profile.bio != null) ...[
                const SizedBox(height: Gap.md),
                Text(
                  profile.bio!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (profile.city != null) ...[
                const SizedBox(height: Gap.sm),
                Text(
                  profile.city!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: Gap.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Stat(
                    label: l10n.profileRecipes,
                    value: profile.counts.recipes,
                    numerals: numerals,
                  ),
                  _Stat(
                    label: l10n.profileFollowers,
                    value: profile.counts.followers,
                    numerals: numerals,
                    onTap: () => context.push('/user/${profile.uid}/followers'),
                  ),
                  _Stat(
                    label: l10n.profileFollowing,
                    value: profile.counts.following,
                    numerals: numerals,
                    onTap: () => context.push('/user/${profile.uid}/following'),
                  ),
                ],
              ),
              const SizedBox(height: Gap.lg),
              Row(
                children: [
                  Expanded(child: _FollowButton(targetUid: profile.uid)),
                  const SizedBox(width: Gap.md),
                  Expanded(child: _MessageButton(profile: profile)),
                ],
              ),
              const SizedBox(height: Gap.xl),
              _PlanArchive(uid: profile.uid),
              if (recipes.isNotEmpty)
                Text(l10n.profileRecipes, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xxl),
          sliver: SliverList.separated(
            itemCount: recipes.length,
            separatorBuilder: (_, _) => const SizedBox(height: Gap.lg),
            itemBuilder: (context, i) =>
                RecipeCard(recipe: recipes[i], numerals: numerals),
          ),
        ),
      ],
    );
  }
}

class _FollowButton extends ConsumerWidget {
  const _FollowButton({required this.targetUid});

  final String targetUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final following = ref.watch(isFollowingProvider(targetUid)).value ?? false;

    Future<void> toggle() async {
      if (!await requireAccount(context, ref)) return;
      final uid = ref.read(currentUidProvider);
      if (uid == null) return;

      // Only this edge is written. The mirrored follower edge and both counts
      // are the Function's job, so nobody can inflate their own following.
      await ref
          .read(userRepositoryProvider)
          .setFollowing(uid: uid, targetUid: targetUid, following: !following);
    }

    return SizedBox(
      width: double.infinity,
      child: following
          ? OutlinedButton(
              onPressed: toggle,
              child: Text(l10n.profileFollowing),
            )
          : FilledButton(onPressed: toggle, child: Text(l10n.profileFollow)),
    );
  }
}

/// Opens the conversation with this person.
///
/// Shown to everyone rather than hidden behind whether the gate would let it
/// through. Hiding it would mean silently telling people they have been shut
/// out, which is a different message from the one their setting actually
/// makes — and the refusal here names which of the three reasons applies.
class _MessageButton extends ConsumerStatefulWidget {
  const _MessageButton({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_MessageButton> createState() => _MessageButtonState();
}

class _MessageButtonState extends ConsumerState<_MessageButton> {
  bool _busy = false;

  Future<void> _open() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (!await requireAccount(context, ref)) return;
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      final me = await ref.read(myAuthorStubFuture.future);
      if (me == null) return;

      final followsMe = await ref.read(
        followsMeProvider(widget.profile.uid).future,
      );

      final id = await ref
          .read(chatRepositoryProvider)
          .openDm(
            me: me,
            other: AuthorStub.fromMap(widget.profile.authorStub),
            theirPrivacy: widget.profile.privacy,
            theyFollowMe: followsMe,
          );
      if (mounted) await context.push('/chats/$id');
    } on DmNotAllowed catch (error) {
      final name = widget.profile.displayName;
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
      // cannot see and so cannot name any more precisely than this.
      messenger.showSnackBar(SnackBar(content: Text(l10n.chatDmBlocked)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final myUid = ref.watch(currentUidProvider);

    // Nothing to message on your own profile.
    if (myUid == widget.profile.uid) return const SizedBox.shrink();

    return OutlinedButton(
      onPressed: _busy ? null : _open,
      child: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(l10n.chatsInbox),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.numerals,
    this.onTap,
  });

  final String label;
  final int value;
  final NumeralStyle numerals;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.xs,
        ),
        child: Column(
          children: [
            Text(
              formatCount(value, style: numerals),
              style: theme.textTheme.titleMedium,
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileNotFound extends StatelessWidget {
  const _ProfileNotFound();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_off_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: Gap.md),
            Text(
              l10n.profileNotFound,
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
}

/// Published weeks, newest first.
///
/// Only public ones come back — the rules see to that — so this is safe to show
/// on anyone's profile without filtering here.
class _PlanArchive extends ConsumerWidget {
  const _PlanArchive({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final plans = ref.watch(userPlansProvider(uid)).value ?? const [];
    final published = plans.where((p) => p.isPublished).toList();

    if (published.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.planArchive, style: theme.textTheme.titleMedium),
        const SizedBox(height: Gap.sm),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: published.length,
            separatorBuilder: (_, _) => const SizedBox(width: Gap.md),
            itemBuilder: (context, i) {
              final plan = published[i];
              return SizedBox(
                width: 170,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.push('/plan/${plan.id}'),
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.title ?? l10n.myWeek,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          const Spacer(),
                          Text(
                            IraqiWeek(plan.week.start).id,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}
