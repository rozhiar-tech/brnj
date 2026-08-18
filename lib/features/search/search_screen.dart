import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../data/models/recipe.dart';
import '../../data/models/user_profile.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';

import '../../shared/error_view.dart';
import '../../shared/recipe_card.dart';
import '../../shared/verified_tick.dart';
import '../profile/profile_screen.dart';
import '../recipe/composer/composer_labels.dart';

/// Recipe search.
///
/// Firestore has no full-text search, so this queries the `keywords` array
/// built at publish time. Both sides run the same normaliser — the one that
/// folds hamza forms, strips tashkeel, and flips ك/ي to ک/ی for Kurdish — which
/// is the entire reason typing "دولمه" finds "دولمة".
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  final _controller = TextEditingController();
  Timer? _debounce;

  List<Recipe> _results = const [];
  String _query = '';
  bool _searching = false;
  bool _hasSearched = false;
  Region? _region;

  @override
  void dispose() {
    _tabs.dispose();
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Long enough that typing a dish name is one query rather than eight.
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    setState(() => _query = query);
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _hasSearched = false;
      });
      return;
    }

    setState(() => _searching = true);
    final results = await ref
        .read(recipeRepositoryProvider)
        .search(
          query,
          // The content language decides which way the script folds — Arabic
          // collapses toward ك/ي, Kurdish toward ک/ی, and running the wrong table
          // makes the query miss everything.
          language: ref.read(activeContentLanguageProvider),
          region: _region,
        );

    if (mounted) {
      setState(() {
        _results = results;
        _searching = false;
        _hasSearched = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: _tabs.index == 0
                ? l10n.searchHint
                : l10n.searchPeopleHint,
            border: InputBorder.none,
            filled: false,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              onPressed: () {
                _controller.clear();
                setState(() {
                  _results = const [];
                  _hasSearched = false;
                });
              },
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            onTap: (_) => setState(() {}),
            tabs: [
              Tab(text: l10n.searchTabRecipes),
              Tab(text: l10n.searchTabPeople),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _RecipeResults(
                  searching: _searching,
                  hasSearched: _hasSearched,
                  results: _results,
                  region: _region,
                  onRegion: (region) {
                    setState(() => _region = region);
                    _search();
                  },
                ),
                _PeopleResults(query: _query),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: theme.colorScheme.surface,
    );
  }
}

/// Recipes: results plus the region filter.
class _RecipeResults extends ConsumerWidget {
  const _RecipeResults({
    required this.searching,
    required this.hasSearched,
    required this.results,
    required this.region,
    required this.onRegion,
  });

  final bool searching;
  final bool hasSearched;
  final List<Recipe> results;
  final Region? region;
  final ValueChanged<Region?> onRegion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final numerals = ref.watch(numeralStyleProvider);

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.only(
              start: Gap.lg,
              end: Gap.lg,
            ),
            children: [
              for (final r in Region.values)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: Gap.sm),
                  child: FilterChip(
                    label: Text(regionLabel(l10n, r)),
                    selected: region == r,
                    onSelected: (selected) => onRegion(selected ? r : null),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: searching
              ? const Center(child: CircularProgressIndicator())
              : !hasSearched
              ? _Hint(message: l10n.searchPrompt)
              : results.isEmpty
              ? _Hint(message: l10n.searchNoResults)
              : ListView.separated(
                  padding: const EdgeInsets.all(Gap.lg),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Gap.lg),
                  itemBuilder: (context, i) =>
                      RecipeCard(recipe: results[i], numerals: numerals),
                ),
        ),
      ],
    );
  }
}

/// People. Handle matches first, then display-name prefixes.
class _PeopleResults extends ConsumerWidget {
  const _PeopleResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    if (query.trim().length < 2) {
      return _Hint(message: l10n.searchPeopleHint);
    }

    return ref
        .watch(peopleSearchProvider(query))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorView(error: error),
          data: (people) => people.isEmpty
              ? _Hint(message: l10n.searchNoPeople)
              : ListView.builder(
                  itemCount: people.length,
                  itemBuilder: (context, i) => _PersonTile(profile: people[i]),
                ),
        );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ListTile(
      leading: ProfileAvatar(
        photoUrl: profile.photoUrl,
        name: profile.displayName,
        radius: 20,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(profile.displayName, overflow: TextOverflow.ellipsis),
          ),
          if (profile.verified) ...[
            const SizedBox(width: Gap.xs),
            const VerifiedTick(size: 14),
          ],
        ],
      ),
      subtitle: Text(
        profile.handle != null ? '@${profile.handle}' : l10n.profileRecipes,
        textDirection: profile.handle != null ? TextDirection.ltr : null,
        style: theme.textTheme.labelSmall,
      ),
      onTap: () => context.push('/user/${profile.uid}'),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xxl),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
