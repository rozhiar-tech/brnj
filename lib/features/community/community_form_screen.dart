import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/brnj_theme.dart';
import '../../data/models/community.dart';
import '../../data/models/recipe.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/error_view.dart';
import '../recipe/composer/composer_labels.dart';
import 'community_labels.dart';

/// Create a community, or edit one.
///
/// One screen for both: the fields are identical, and a separate edit screen
/// is a second place for the two of them to drift apart.
class CommunityFormScreen extends ConsumerStatefulWidget {
  const CommunityFormScreen({this.communityId, super.key});

  /// Null when creating.
  final String? communityId;

  @override
  ConsumerState<CommunityFormScreen> createState() =>
      _CommunityFormScreenState();
}

class _CommunityFormScreenState extends ConsumerState<CommunityFormScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _rule = TextEditingController();

  CommunityCategory _category = CommunityCategory.other;
  Region? _region;
  CommunityPrivacy _privacy = CommunityPrivacy.public;
  JoinPolicy _joinPolicy = JoinPolicy.open;
  List<String> _rules = [];

  bool _busy = false;
  bool _loaded = false;

  bool get _isEditing => widget.communityId != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _rule.dispose();
    super.dispose();
  }

  /// Fills the fields from the existing community, once.
  ///
  /// Guarded by `_loaded` because the provider is a stream: every counter
  /// update re-emits, and without the guard each one would overwrite whatever
  /// the person was in the middle of typing.
  void _hydrate(Community community) {
    if (_loaded) return;
    _loaded = true;
    _name.text = community.name;
    _description.text = community.description ?? '';
    _category = community.category;
    _region = Region.values
        .where((r) => r.name == community.region)
        .firstOrNull;
    _privacy = community.privacy;
    _joinPolicy = community.joinPolicy;
    _rules = [...community.rules];
  }

  void _addRule() {
    final text = _rule.text.trim();
    if (text.isEmpty || _rules.length >= 10) return;
    setState(() {
      _rules = [..._rules, text];
      _rule.clear();
    });
  }

  Future<void> _submit(Community? existing) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    if (_name.text.trim().isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.postEmptyBody)));
      return;
    }

    setState(() => _busy = true);
    try {
      final repository = ref.read(communityRepositoryProvider);
      final me = await ref.read(myAuthorStubFuture.future);
      if (me == null) return;

      final draft = Community(
        id: existing?.id ?? '',
        name: _name.text,
        description: _description.text.trim().isEmpty
            ? null
            : _description.text,
        category: _category,
        region: _region?.name,
        privacy: _privacy,
        joinPolicy: _joinPolicy,
        rules: _rules,
        moderators: existing?.moderators ?? const [],
        createdBy: existing?.createdBy ?? me.uid,
        coverUrl: existing?.coverUrl,
      );

      if (existing == null) {
        final id = await repository.create(community: draft, owner: me);
        // Replace rather than push: backing out of a community you just made
        // should land on the list, not on the form that made it.
        await router.pushReplacement('/communities/$id');
      } else {
        await repository.update(draft);
        router.pop();
      }
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (!_isEditing) return _form(l10n, null);

    final async = ref.watch(communityProvider(widget.communityId!));
    return async.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(error: error, where: 'communityForm'),
      ),
      data: (community) {
        if (community == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(l10n.communityDeleted)),
          );
        }
        _hydrate(community);
        return _form(l10n, community);
      },
    );
  }

  Widget _form(AppLocalizations l10n, Community? existing) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          existing == null ? l10n.communitiesCreate : l10n.communitySettings,
        ),
        actions: [
          if (existing != null) _DeleteAction(community: existing),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Gap.xl),
        children: [
          TextField(
            controller: _name,
            maxLength: 60,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: l10n.communityNameLabel),
          ),
          const SizedBox(height: Gap.md),

          TextField(
            controller: _description,
            maxLength: 500,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l10n.communityDescriptionLabel,
            ),
          ),
          const SizedBox(height: Gap.lg),

          _Label(l10n.communityCategoryLabel),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final category in CommunityCategory.values)
                ChoiceChip(
                  label: Text(categoryLabel(l10n, category)),
                  selected: _category == category,
                  onSelected: (_) => setState(() => _category = category),
                ),
            ],
          ),
          const SizedBox(height: Gap.lg),

          // Optional. "Baghdad kitchens" is a real community; "Iraqi food" is
          // not a regional one, and forcing a choice would put every community
          // in a region it does not belong to.
          _Label(l10n.composerRegionLabel),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final region in Region.values)
                ChoiceChip(
                  label: Text(regionLabel(l10n, region)),
                  selected: _region == region,
                  onSelected: (value) =>
                      setState(() => _region = value ? region : null),
                ),
            ],
          ),
          const SizedBox(height: Gap.lg),

          _Label(l10n.communityPrivacyLabel),
          SegmentedButton<CommunityPrivacy>(
            segments: [
              for (final privacy in CommunityPrivacy.values)
                ButtonSegment(
                  value: privacy,
                  label: Text(privacyLabel(l10n, privacy)),
                ),
            ],
            selected: {_privacy},
            onSelectionChanged: (value) =>
                setState(() => _privacy = value.first),
          ),
          const SizedBox(height: Gap.lg),

          _Label(l10n.communityJoinPolicyLabel),
          // RadioGroup rather than a groupValue on each tile: the per-tile form
          // was deprecated after 3.32, and the ancestor is what the radios read
          // their selection from now.
          RadioGroup<JoinPolicy>(
            groupValue: _joinPolicy,
            onChanged: (value) =>
                setState(() => _joinPolicy = value ?? _joinPolicy),
            child: Column(
              children: [
                for (final policy in JoinPolicy.values)
                  RadioListTile<JoinPolicy>(
                    value: policy,
                    title: Text(joinPolicyLabel(l10n, policy)),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          Text(
            l10n.communityJoinPolicyHelp,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Gap.lg),

          _Label(l10n.communityRulesLabel),
          Text(
            l10n.communityRulesHelp,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Gap.sm),
          for (final (i, rule) in _rules.indexed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text('${i + 1}.'),
              title: Text(rule),
              trailing: IconButton(
                onPressed: () => setState(
                  () => _rules = [..._rules]..removeAt(i),
                ),
                icon: const Icon(Icons.close),
              ),
            ),
          if (_rules.length < 10)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _rule,
                    onSubmitted: (_) => _addRule(),
                    decoration: InputDecoration(
                      hintText: l10n.communityAddRule,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(onPressed: _addRule, icon: const Icon(Icons.add)),
              ],
            ),

          const SizedBox(height: Gap.xxl),
          FilledButton(
            onPressed: _busy ? null : () => _submit(existing),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    existing == null
                        ? l10n.communityCreateAction
                        : l10n.communitySaveAction,
                  ),
          ),
          const SizedBox(height: Gap.xxl),
        ],
      ),
    );
  }
}

class _DeleteAction extends ConsumerWidget {
  const _DeleteAction({required this.community});

  final Community community;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final uid = ref.watch(currentUidProvider);

    // Only the person who made it. A moderator who can delete the community
    // out from under its owner is a moderator with too much.
    if (uid != community.createdBy) return const SizedBox.shrink();

    return IconButton(
      tooltip: l10n.communityDelete,
      icon: const Icon(Icons.delete_outline),
      onPressed: () async {
        final router = GoRouter.of(context);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(l10n.communityDeleteConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.actionCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.actionDelete),
              ),
            ],
          ),
        );
        if (confirmed != true) return;

        await ref.read(communityRepositoryProvider).deleteCommunity(
          community.id,
        );
        // Back to the list: the two screens behind this one both showed a
        // community that no longer exists.
        router.go('/communities');
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
