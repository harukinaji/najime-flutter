import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api_service.dart';
import '../../data/auth_state.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _bioController;
  bool _saving = false;
  static const int _bioMaxLen = 150;
  File? _pickedImage;
  String? _avatarBase64;

  @override
  void initState() {
    super.initState();
    final a = AuthState.instance;
    _nameController = TextEditingController(
      text: a.displayName ?? a.username ?? '',
    );
    _bioController = TextEditingController(text: a.bio ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final file = File(picked.path);
      final bytes = await file.readAsBytes();
      setState(() {
        _pickedImage = file;
        _avatarBase64 = 'data:image/png;base64,${base64Encode(bytes)}';
      });
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);

    final a = AuthState.instance;

    await a.saveSession(
      token: ApiService.accessToken ?? '',
      username: a.username ?? '',
      displayName: name,
      bio: _bioController.text.trim(),
      email: a.email,
      avatarUrl: _avatarBase64 ?? a.avatarUrl,
    );

    final result = await ApiService.updateProfile(
      displayName: name,
      bio: _bioController.text.trim(),
      avatarUrl: _avatarBase64,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.message ??
              (result.success ? 'Profile updated' : 'Failed to update'),
        ),
        backgroundColor: result.success
            ? Colors.green
            : Theme.of(context).colorScheme.error,
      ),
    );
    if (result.success) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Save',
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          children: [
            _buildAvatarSection(cs),
            const SizedBox(height: 28),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildTextField(
                      controller: _nameController,
                      label: 'Display Name',
                      icon: Icons.person_outline,
                      cs: cs,
                    ),
                    const Divider(height: 24, indent: 36),
                    _buildBioField(cs),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ListTile(
                leading: Icon(
                  Icons.alternate_email,
                  color: cs.onSurfaceVariant,
                ),
                title: Text(
                  '@${AuthState.instance.username ?? ''}',
                  style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                ),
                subtitle: Text(
                  'Username cannot be changed',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarSection(ColorScheme cs) {
    final a = AuthState.instance;
    final displayUrl = _avatarBase64 ?? a.avatarUrl;
    final displayName = _nameController.text.isNotEmpty
        ? _nameController.text
        : (a.displayName ?? a.username ?? '?');
    final initial = displayName[0].toUpperCase();

    return Column(
      children: [
        GestureDetector(
          onTap: _pickImage,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: displayUrl == null
                      ? LinearGradient(
                          colors: [
                            cs.primary,
                            cs.primary.withValues(alpha: 0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  border: Border.all(color: cs.primary, width: 2.5),
                ),
                child: displayUrl != null
                    ? ClipOval(child: _avatarWidget(displayUrl, 108, 108))
                    : Center(
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.surface, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _pickedImage != null ? 'Change Avatar' : 'Set Avatar',
              style: TextStyle(
                color: cs.primary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _avatarWidget(String url, double width, double height) {
    if (url.startsWith('data:image')) {
      final base64 = url.split(',').last;
      return Image.memory(
        base64Decode(base64),
        width: width,
        height: height,
        fit: BoxFit.cover,
      );
    }
    return Image.network(url, width: width, height: height, fit: BoxFit.cover);
  }

  Widget _buildBioField(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.info_outline, color: cs.onSurfaceVariant, size: 22),
            const SizedBox(width: 12),
            Text(
              'Bio',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _bioController,
          maxLines: 3,
          maxLength: _bioMaxLen,
          style: TextStyle(fontSize: 15, color: cs.onSurface),
          buildCounter:
              (
                context, {
                required currentLength,
                required isFocused,
                required maxLength,
              }) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$currentLength / $maxLength',
                  style: TextStyle(
                    fontSize: 12,
                    color: currentLength >= _bioMaxLen
                        ? cs.error
                        : cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
          decoration: InputDecoration(
            hintText: 'Tell something about yourself...',
            hintStyle: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              fontSize: 15,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ColorScheme cs,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(fontSize: 15, color: cs.onSurface),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: cs.onSurfaceVariant),
        prefixIcon: Icon(icon, color: cs.onSurfaceVariant, size: 22),
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 0,
          vertical: maxLines > 1 ? 4 : 0,
        ),
      ),
    );
  }
}
