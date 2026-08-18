import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/brnj_theme.dart';
import '../../data/models/user_profile.dart';
import '../../data/providers.dart';
import '../../data/repositories/user_repository.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/profile_avatar.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _bio = TextEditingController();
  final _city = TextEditingController();

  UserProfile? _loaded;
  bool _saving = false;
  bool _uploadingAvatar = false;
  HandleStatus? _handleStatus;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    _city.dispose();
    super.dispose();
  }

  /// Fills the fields once, on first load. Rebinding on every snapshot would
  /// overwrite what the person is currently typing.
  void _hydrate(UserProfile profile) {
    if (_loaded != null) return;
    _loaded = profile;
    _name.text = profile.displayName;
    _handle.text = profile.handle ?? '';
    _bio.text = profile.bio ?? '';
    _city.text = profile.city ?? '';
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // A first pass at the source, before the real compression in the
      // repository — this keeps a 48MP photo from being decoded in full.
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (picked == null || _loaded == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      await ref
          .read(userRepositoryProvider)
          .uploadAvatar(uid: _loaded!.uid, filePath: picked.path);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _checkHandle(String value) async {
    if (value.trim().isEmpty) {
      setState(() => _handleStatus = null);
      return;
    }
    final status = await ref
        .read(userRepositoryProvider)
        .checkHandle(value, currentHandle: _loaded?.handle);
    if (mounted) setState(() => _handleStatus = status);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final profile = _loaded;
    if (profile == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final repository = ref.read(userRepositoryProvider);
    try {
      // The handle goes first: it can fail on a race, and there is no point
      // writing the rest if the name someone chose has just been taken.
      if (_handle.text.trim().isNotEmpty) {
        final status = await repository.claimHandle(
          uid: profile.uid,
          handle: _handle.text,
          currentHandle: profile.handle,
        );
        if (status == HandleStatus.taken || status == HandleStatus.invalid) {
          if (mounted) {
            setState(() {
              _handleStatus = status;
              _saving = false;
            });
          }
          return;
        }
      }

      await repository.updateProfile(
        uid: profile.uid,
        displayName: _name.text,
        bio: _bio.text,
        city: _city.text,
      );

      if (mounted) context.go('/me');
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final profileAsync = ref.watch(myProfileProvider);
    final profile = profileAsync.value;

    if (profile != null) _hydrate(profile);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileEdit),
        actions: [
          TextButton(
            onPressed: _saving || profile == null ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.actionSave),
          ),
        ],
      ),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(Gap.xl),
                children: [
                  Center(
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        ProfileAvatar(
                          photoUrl: profile.photoUrl,
                          name: profile.displayName,
                        ),
                        if (_uploadingAvatar)
                          const Positioned.fill(
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else
                          IconButton.filled(
                            onPressed: _pickAvatar,
                            icon: const Icon(
                              Icons.photo_camera_outlined,
                              size: 18,
                            ),
                            tooltip: l10n.profileChangePhoto,
                          ),
                      ],
                    ),
                  ),
                  if (profile.photoUrl != null)
                    Center(
                      child: TextButton(
                        onPressed: () => ref
                            .read(userRepositoryProvider)
                            .removeAvatar(profile.uid),
                        child: Text(l10n.profileRemovePhoto),
                      ),
                    ),
                  const SizedBox(height: Gap.xl),

                  TextFormField(
                    controller: _name,
                    maxLength: 40,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.profileDisplayName,
                      helperText: l10n.profileDisplayNameHelp,
                      helperMaxLines: 3,
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? l10n.profileNameRequired
                        : null,
                  ),
                  const SizedBox(height: Gap.lg),

                  TextFormField(
                    controller: _handle,
                    maxLength: 20,
                    // Handles live in URLs and get typed by other people, so
                    // they stay Latin and left-to-right even in an RTL layout.
                    textDirection: TextDirection.ltr,
                    onChanged: _checkHandle,
                    decoration: InputDecoration(
                      labelText: l10n.profileHandle,
                      prefixText: '@',
                      helperText: _handleHelper(l10n),
                      helperStyle: TextStyle(
                        color:
                            _handleStatus == HandleStatus.taken ||
                                _handleStatus == HandleStatus.invalid
                            ? theme.colorScheme.error
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.lg),

                  TextFormField(
                    controller: _bio,
                    maxLength: 160,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: l10n.profileBio),
                  ),
                  const SizedBox(height: Gap.lg),

                  TextFormField(
                    controller: _city,
                    maxLength: 40,
                    decoration: InputDecoration(
                      labelText: l10n.profileCity,
                      // City, never anything finer. The app does not ask for
                      // location and there is no reason it should.
                      helperText: l10n.profileCityHelp,
                      helperMaxLines: 2,
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: Gap.lg),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  String _handleHelper(AppLocalizations l10n) => switch (_handleStatus) {
    HandleStatus.taken => l10n.profileHandleTaken,
    HandleStatus.invalid => l10n.profileHandleInvalid,
    HandleStatus.available => l10n.profileHandleAvailable,
    _ => l10n.profileHandleHelp,
  };
}
