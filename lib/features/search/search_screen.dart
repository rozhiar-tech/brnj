import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../data/models/recipe.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/recipe_card.dart';
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

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  List<Recipe> _results = const [];
  bool _searching = false;
  bool _hasSearched = false;
  Region? _region;

  @override
  void dispose() {
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
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _hasSearched = false;
      });
      return;
    }

    setState(() => _searching = true);
    final results = await ref.read(recipeRepositoryProvider).search(
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
    final numerals = ref.watch(numeralStyleProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: l10n.searchHint,
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
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.only(
                start: Gap.lg,
                end: Gap.lg,
              ),
              children: [
                for (final region in Region.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: Gap.sm),
                    child: FilterChip(
                      label: Text(regionLabel(l10n, region)),
                      selected: _region == region,
                      onSelected: (selected) {
                        setState(() => _region = selected ? region : null);
                        _search();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator())
                : !_hasSearched
                ? _Hint(message: l10n.searchPrompt)
                : _results.isEmpty
                ? _Hint(message: l10n.searchNoResults)
                : ListView.separated(
                    padding: const EdgeInsets.all(Gap.lg),
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Gap.lg),
                    itemBuilder: (context, i) =>
                        RecipeCard(recipe: _results[i], numerals: numerals),
                  ),
          ),
        ],
      ),
      backgroundColor: theme.colorScheme.surface,
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
