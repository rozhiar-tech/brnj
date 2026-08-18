import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../core/numerals.dart';
import '../../data/models/community.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/error_view.dart';
import '../auth/sign_in_sheet.dart';
import 'community_labels.dart';

/// The communities tab.
///
/// Two things stacked, in this order: the ones you are already in, then the
/// directory. That order is deliberate — for anyone with a membership this is a
/// "go back to my room" screen, and making them scroll past a directory they
/// have already used is a small daily tax. For everyone else the rail is absent
/// and the directory is simply the screen.
class CommunitiesScreen extends ConsumerStatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  ConsumerState<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends ConsumerState<CommunitiesScreen> {
  CommunityCategory? _category;

  Future<void> _create() async {
    if (!await requireAccount(context, ref)) return;
    if (!mounted) return;
    await context.push('/communities/new');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mine = ref.watch(myCommunitiesProvider);
    final directory = ref.watch(
      communityDirectoryProvider((category: _category, region: null)),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navCommunities),
        actions: [
          IconButton(
            onPressed: () => showSearch(
              context: context,
              delegate: _CommunitySearchDelegate(ref, l10n),
            ),
            icon: const Icon(Icons.search),
            tooltip: l10n.communitiesSearchHint,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(l10n.communitiesCreate),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myCommunitiesProvider);
          ref.invalidate(communityDirectoryProvider);
        },
        child: CustomScrollView(
          slivers: [
            // The rail is skipped entirely when empty rather than showing an
            // empty-state box: a guest would otherwise meet two empty states
            // stacked on one screen.
            ...switch (mine.value) {
              final list? when list.isNotEmpty => [
                _SectionHeader(title: l10n.communitiesMine),
                SliverToBoxAdapter(child: _MineRail(communities: list)),
              ],
              _ => const <Widget>[],
            },

            // Said once, above the directory that answers it. Guests are
            // excluded: telling someone with no account that they have joined
            // nothing is not news.
            if (!ref.watch(isGuestProvider) &&
                (mine.value?.isEmpty ?? false))
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.lg,
                    Gap.lg,
                    Gap.lg,
                    0,
                  ),
                  child: Text(
                    l10n.communitiesEmptyMine,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),

            _SectionHeader(title: l10n.communitiesDiscover),
            SliverToBoxAdapter(
              child: _CategoryFilter(
                selected: _category,
                onSelected: (value) => setState(() => _category = value),
              ),
            ),

            switch (directory) {
              AsyncError(:final error) => SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorView(error: error, where: 'communities'),
              ),
              AsyncData(:final value) when value.isEmpty => SliverFillRemaining(
                hasScrollBody: false,
                child: _Empty(message: l10n.communitiesEmptyDirectory),
              ),
              AsyncData(:final value) => SliverList.builder(
                itemCount: value.length,
                itemBuilder: (context, i) =>
                    CommunityTile(community: value[i]),
              ),
              _ => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
            },

            const SliverToBoxAdapter(child: SizedBox(height: 88)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.sm),
        child: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// The communities you are in, as a horizontal rail.
///
/// Horizontal because this is a shortcut, not a browsing surface — it should
/// cost one row of screen no matter how many memberships someone accumulates.
class _MineRail extends ConsumerWidget {
  const _MineRail({required this.communities});

  final List<Community> communities;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
        itemCount: communities.length,
        separatorBuilder: (_, _) => const SizedBox(width: Gap.md),
        itemBuilder: (context, i) {
          final community = communities[i];
          return SizedBox(
            width: 96,
            child: InkWell(
              onTap: () => context.push('/communities/${community.id}'),
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  _CommunityBadge(community: community, size: 64),
                  const SizedBox(height: Gap.xs),
                  Text(
                    community.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The cover, or the first letter of the name when there isn't one.
///
/// Same fallback the profile avatar uses, and for the same reason: a grid of
/// identical grey placeholders is unreadable, a grid of letters is not.
class _CommunityBadge extends StatelessWidget {
  const _CommunityBadge({required this.community, this.size = 56});

  final Community community;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(size / 4);

    if (community.coverUrl != null) {
      return ClipRRect(
        borderRadius: radius,
        child: CachedNetworkImage(
          imageUrl: community.coverUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }

    final letter = community.name.trim().isEmpty
        ? '#'
        : community.name.trim().characters.first;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: radius,
      ),
      child: Text(
        letter,
        maxLines: 1,
        style: TextStyle(
          // Same ratio as the profile avatar: tall enough to read, short
          // enough that a Kurdish ڵ stays inside the box.
          fontSize: size * 0.45,
          height: 1,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({required this.selected, required this.onSelected});

  final CommunityCategory? selected;
  final ValueChanged<CommunityCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: Gap.sm),
            child: FilterChip(
              label: Text(l10n.communitiesAll),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final category in CommunityCategory.values)
            Padding(
              padding: const EdgeInsets.only(right: Gap.sm),
              child: FilterChip(
                label: Text(categoryLabel(l10n, category)),
                selected: selected == category,
                onSelected: (value) => onSelected(value ? category : null),
              ),
            ),
        ],
      ),
    );
  }
}

/// One row in the directory.
class CommunityTile extends ConsumerWidget {
  const CommunityTile({required this.community, super.key});

  final Community community;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);

    return ListTile(
      onTap: () => context.push('/communities/${community.id}'),
      leading: _CommunityBadge(community: community),
      title: Row(
        children: [
          Flexible(
            child: Text(
              community.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (community.isPrivate) ...[
            const SizedBox(width: Gap.xs),
            Icon(Icons.lock_outline, size: 14, color: theme.colorScheme.outline),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (community.description != null)
            Text(
              community.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            l10n
                .communityMemberCount(community.memberCount)
                .toNumeralStyle(numerals),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      isThreeLine: community.description != null,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

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
              Icons.groups_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: Gap.md),
            Text(
              message,
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

/// Name search over the directory.
///
/// A prefix match, not the Arabic/Kurdish normaliser the recipe search uses:
/// the keyword array that normaliser needs earns its write cost across
/// thousands of recipes and not across dozens of communities.
class _CommunitySearchDelegate extends SearchDelegate<void> {
  _CommunitySearchDelegate(this._ref, AppLocalizations l10n)
    : super(searchFieldLabel: l10n.communitiesSearchHint);

  final WidgetRef _ref;

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        onPressed: () => query = '',
        icon: const Icon(Icons.clear),
      ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const BackButtonIcon(),
  );

  @override
  Widget buildSuggestions(BuildContext context) => buildResults(context);

  @override
  Widget buildResults(BuildContext context) {
    if (query.trim().isEmpty) return const SizedBox.shrink();

    return FutureBuilder(
      future: _ref
          .read(communityRepositoryProvider)
          .searchCommunities(query),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorView(error: snapshot.error, where: 'communitySearch');
        }
        final results = snapshot.data;
        if (results == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (results.isEmpty) {
          return _Empty(
            message: AppLocalizations.of(context).communitiesEmptyDirectory,
          );
        }
        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, i) => CommunityTile(community: results[i]),
        );
      },
    );
  }
}
