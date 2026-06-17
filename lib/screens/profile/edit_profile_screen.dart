import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../backendless_client.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _bioCtrl   = TextEditingController();
  final _phoneCtrl = TextEditingController();

  late UserRole _role;
  XFile?  _newPhoto;          // locally picked, not yet uploaded
  String? _existingPhotoUrl;  // current remote avatar
  bool    _isSaving = false;

  // Snapshot of the initial values — used to detect unsaved changes.
  late String   _initialName;
  late String   _initialBio;
  late String   _initialPhone;
  late UserRole _initialRole;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _nameCtrl.text    = user?.name        ?? '';
    _bioCtrl.text     = user?.bio         ?? '';
    _phoneCtrl.text   = user?.phoneNumber ?? '';
    _role             = user?.role        ?? UserRole.sitter;
    _existingPhotoUrl = user?.profilePhotoUrl;

    _initialName  = _nameCtrl.text;
    _initialBio   = _bioCtrl.text;
    _initialPhone = _phoneCtrl.text;
    _initialRole  = _role;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  bool get _isDirty =>
      _nameCtrl.text.trim()  != _initialName.trim()  ||
      _bioCtrl.text.trim()   != _initialBio.trim()   ||
      _phoneCtrl.text.trim() != _initialPhone.trim() ||
      _role != _initialRole ||
      _newPhoto != null;

  // ── Photo ───────────────────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source:       ImageSource.gallery,
      imageQuality: 80,
      maxWidth:     800,
    );
    if (picked != null) setState(() => _newPhoto = picked);
  }

  Future<String?> _uploadPhoto(XFile file) async {
    final ext      = file.path.split('.').last.toLowerCase();
    final filename = 'avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
    return BackendlessClient.instance.uploadFile(
      path:     'avatars',
      filename: filename,
      filePath: file.path,
    );
  }

  // ── Save ─────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final auth      = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      String? photoUrl = _existingPhotoUrl;
      if (_newPhoto != null) {
        final uploaded = await _uploadPhoto(_newPhoto!);
        if (uploaded == null) {
          throw Exception('Photo upload failed. Please try again.');
        }
        photoUrl = uploaded;
      }

      final bio   = _bioCtrl.text.trim();
      final phone = _phoneCtrl.text.trim();
      await auth.updateProfile(
        name:            _nameCtrl.text.trim(),
        bio:             bio.isEmpty   ? null : bio,
        phoneNumber:     phone.isEmpty ? null : phone,
        role:            _role,
        profilePhotoUrl: photoUrl,
      );

      messenger.showSnackBar(
        const SnackBar(content: Text('Profile updated ✓')),
      );
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Discard guard ─────────────────────────────────────────────────────────────

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Discard changes?'),
        content: const Text('Your unsaved changes will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:     const Text('Keep editing'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child:     const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit Profile')),
        body: Column(
          children: [
            if (_isSaving) const LinearProgressIndicator(),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(child: _buildAvatar(scheme)),
                    const SizedBox(height: 28),

                    TextFormField(
                      controller:         _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText:  'Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Name is required'
                          : null,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller:         _bioCtrl,
                      maxLines:           3,
                      maxLength:          200,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText:          'Bio',
                        hintText:           'Tell others a bit about yourself',
                        alignLabelWithHint: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller:   _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText:  'Phone number',
                        hintText:   'Optional',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 20),

                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Role',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildRolePicker(),
                    const SizedBox(height: 32),

                    FilledButton(
                      onPressed: (_isSaving || !_isDirty) ? null : _save,
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width:  20,
                              child:  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save changes'),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(ColorScheme scheme) {
    final hasNew      = _newPhoto != null;
    final hasExisting =
        _existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty;

    ImageProvider? image;
    if (hasNew) {
      image = FileImage(File(_newPhoto!.path));
    } else if (hasExisting) {
      image = CachedNetworkImageProvider(_existingPhotoUrl!);
    }

    return Stack(
      children: [
        CircleAvatar(
          radius:          52,
          backgroundColor: scheme.primaryContainer,
          backgroundImage: image,
          child: image == null
              ? Text(
                  _initials(_nameCtrl.text),
                  style: TextStyle(
                    fontSize:   34,
                    fontWeight: FontWeight.w600,
                    color:      scheme.onPrimaryContainer,
                  ),
                )
              : null,
        ),
        Positioned(
          bottom: 0,
          right:  0,
          child: Material(
            color:        scheme.primary,
            shape:        const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _isSaving ? null : _pickPhoto,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.camera_alt,
                    size: 18, color: scheme.onPrimary),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRolePicker() => SegmentedButton<UserRole>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: UserRole.owner,  label: Text('Owner')),
          ButtonSegment(value: UserRole.sitter, label: Text('Sitter')),
          ButtonSegment(value: UserRole.both,   label: Text('Both')),
        ],
        selected: {_role},
        onSelectionChanged: (selection) =>
            setState(() => _role = selection.first),
      );

  static String _initials(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    final parts = t.split(RegExp(r'\s+'));
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last  =
        parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    final res = (first + last).toUpperCase();
    return res.isEmpty ? '?' : res;
  }
}
