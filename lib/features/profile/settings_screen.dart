import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/localization.dart';
import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../core/numerals.dart';
import '../../data/models/user_profile.dart';
import '../../data/providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/option_sheet.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final activeLocale = ref.watch(activeLocaleProvider);
    final isGuest = ref.watch(isGuestProvider);
    final profile = ref.watch(myProfileProvider).value;
    final uid = ref.watch(currentUidProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          _SectionHeader(l10n.settingsLanguage),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(l10n.settingsUiLanguage),
            subtitle: Text(activeLocale.nativeName),
            onTap: () => _pickLanguage(context, ref, activeLocale),
          ),
          ListTile(
            leading: const Icon(Icons.numbers),
            title: Text(l10n.settingsNumerals),
            subtitle: Text(
              settings.numeralStyleFor(activeLocale) == NumeralStyle.arabicIndic
                  ? l10n.settingsNumeralsArabic
                  : l10n.settingsNumeralsLatin,
            ),
            onTap: () => _pickNumerals(context, ref),
          ),

          const Divider(),
          _SectionHeader(l10n.settingsDataTitle),
          SwitchListTile(
            secondary: const Icon(Icons.data_saver_on_outlined),
            title: Text(l10n.settingsDataSaver),
            subtitle: Text(l10n.settingsDataSaverHelp),
            value: settings.dataSaver,
            onChanged: (value) =>
                ref.read(settingsProvider.notifier).setDataSaver(value),
          ),

          if (!isGuest && profile != null) ...[
            const Divider(),
            _SectionHeader(l10n.settingsPrivacyTitle),

            // Counts are public, names are not — and anyone can leave the
            // viewer lists entirely. Being seen browsing is not neutral here.
            SwitchListTile(
              secondary: const Icon(Icons.visibility_off_outlined),
              title: Text(l10n.settingsIncognito),
              subtitle: Text(l10n.settingsIncognitoHelp),
              value: profile.privacy.incognito,
              onChanged: (value) => _updatePrivacy(
                ref,
                profile,
                profile.privacy.copyWith(incognito: value),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.search_off_outlined),
              title: Text(l10n.settingsDiscoverable),
              subtitle: Text(l10n.settingsDiscoverableHelp),
              value: profile.privacy.discoverable,
              onChanged: (value) => _updatePrivacy(
                ref,
                profile,
                profile.privacy.copyWith(discoverable: value),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: Text(l10n.settingsWhoCanMessage),
              subtitle: Text(_dmLabel(l10n, profile.privacy.dmMode)),
              onTap: () => _pickDmMode(context, ref, profile),
            ),
          ],

          const Divider(),
          _SectionHeader(l10n.settingsAccountTitle),
          if (isGuest)
            ListTile(
              leading: const Icon(Icons.login),
              title: Text(l10n.signInWithPhone),
              onTap: () => context.go('/me'),
            )
          else ...[
            // Debug builds only. Granting the first moderator claim needs this
            // uid on the command line, and hunting for it in the Firebase
            // console is a worse first five minutes than a tap to copy.
            if (kDebugMode && uid != null)
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(l10n.settingsUserId),
                subtitle: Text(
                  uid,
                  style: const TextStyle(fontSize: 11),
                  textDirection: TextDirection.ltr,
                ),
                trailing: const Icon(Icons.copy, size: 18),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: uid));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.settingsUserIdCopied)),
                    );
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(l10n.settingsSignOut),
              onTap: () => _signOut(context, ref),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_forever_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l10n.settingsDeleteAccount,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => _deleteAccount(context, ref),
            ),
          ],
          const SizedBox(height: Gap.xxl),
        ],
      ),
    );
  }

  void _updatePrivacy(WidgetRef ref, UserProfile profile, UserPrivacy privacy) {
    ref.read(userRepositoryProvider).updateProfile(
      uid: profile.uid,
      privacy: privacy,
    );
  }

  /// Single-choice sheet. Shares the scrollable, height-capped sheet with the
  /// rest of the app so no list of options can outgrow its container.
  static Future<T?> _pickOne<T>(
    BuildContext context, {
    required T? selected,
    required List<(T value, String label)> options,
  }) {
    return showOptionSheet<T>(
      context,
      selected: selected,
      options: [
        for (final (value, label) in options)
          SheetOption(value: value, label: label),
      ],
    );
  }

  Future<void> _pickLanguage(
    BuildContext context,
    WidgetRef ref,
    AppLocale active,
  ) async {
    final chosen = await _pickOne<AppLocale>(
      context,
      selected: active,
      // Each language is written in itself. A list of language names translated
      // into the language you can't read is useless.
      options: [for (final l in AppLocale.values) (l, l.nativeName)],
    );
    if (chosen != null) {
      await ref.read(settingsProvider.notifier).setLocale(chosen);
    }
  }

  Future<void> _pickNumerals(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final chosen = await _pickOne<NumeralStyle>(
      context,
      selected: ref.read(settingsProvider).numeralStyleOverride,
      options: [
        (NumeralStyle.arabicIndic, l10n.settingsNumeralsArabic),
        (NumeralStyle.latin, l10n.settingsNumeralsLatin),
      ],
    );
    if (chosen != null) {
      await ref.read(settingsProvider.notifier).setNumeralStyle(chosen);
    }
  }

  Future<void> _pickDmMode(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
  ) async {
    final l10n = AppLocalizations.of(context);
    final chosen = await _pickOne<DmMode>(
      context,
      selected: profile.privacy.dmMode,
      options: [for (final m in DmMode.values) (m, _dmLabel(l10n, m))],
    );
    if (chosen != null) {
      _updatePrivacy(ref, profile, profile.privacy.copyWith(dmMode: chosen));
    }
  }

  static String _dmLabel(AppLocalizations l10n, DmMode mode) => switch (mode) {
    DmMode.everyone => l10n.settingsDmEveryone,
    DmMode.following => l10n.settingsDmFollowing,
    DmMode.none => l10n.settingsDmNone,
  };

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirm(
      context,
      title: l10n.settingsSignOut,
      body: l10n.settingsSignOutConfirm,
      action: l10n.settingsSignOut,
    );
    if (!confirmed) return;

    await ref.read(authRepositoryProvider).signOut();
    if (context.mounted) context.go('/');
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirm(
      context,
      title: l10n.settingsDeleteAccount,
      body: l10n.settingsDeleteConfirm,
      action: l10n.settingsDeleteAccount,
      destructive: true,
    );
    if (!confirmed) return;

    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      if (context.mounted) context.go('/');
    } on AuthException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            // Firebase refuses to delete an account whose sign-in is old, and
            // the fix is entirely on the person's side, so say so plainly.
            error.raw.toString().contains('requires-recent-login')
                ? l10n.settingsDeleteNeedsRecentLogin
                : l10n.errorGeneric,
          ),
        ),
      );
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: destructive
                ? TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.sm),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
