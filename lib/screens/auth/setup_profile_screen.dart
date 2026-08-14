import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/api_service.dart';
import '../../data/auth_state.dart';

class SetupProfileScreen extends StatefulWidget {
  final String email;
  final String idToken;
  final String suggestedNickname;
  final String? displayName;
  final String? avatarUrl;

  const SetupProfileScreen({
    super.key,
    required this.email,
    required this.idToken,
    required this.suggestedNickname,
    this.displayName,
    this.avatarUrl,
  });

  @override
  State<SetupProfileScreen> createState() => _SetupProfileScreenState();
}

class _SetupProfileScreenState extends State<SetupProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _usernameController;
  int _selectedColorIndex = 0;
  bool _loading = false;
  bool _generatingNickname = false;
  bool _checkingUsername = false;
  bool? _usernameAvailable;
  Timer? _debounceTimer;
  bool _settingUsernameProgrammatically = false;
  File? _pickedImage;

  static const List<Color> _avatarColors = [
    Color(0xFF18A7B5),
    Color(0xFFE53935),
    Color(0xFF43A047),
    Color(0xFFFB8C00),
    Color(0xFF8E24AA),
    Color(0xFF3949AB),
    Color(0xFF00ACC1),
    Color(0xFFF4511E),
    Color(0xFF6D4C41),
    Color(0xFF546E7A),
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.displayName ?? widget.suggestedNickname,
    );
    _usernameController = TextEditingController(
      text: widget.suggestedNickname,
    );
    _usernameController.addListener(_onUsernameChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateAndCheckUsername();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _usernameController.removeListener(_onUsernameChanged);
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  String get _displayName => _nameController.text.trim();
  String get _username => _usernameController.text.trim();

  void _onUsernameChanged() {
    if (_settingUsernameProgrammatically) return;
    _debounceTimer?.cancel();
    _usernameAvailable = null;
    if (_username.isEmpty || _username.length < 3) return;
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _checkUsernameAvailability();
    });
  }

  Future<void> _checkUsernameAvailability() async {
    if (_username.isEmpty || _username.length < 3) return;
    setState(() => _checkingUsername = true);
    final available = await ApiService.checkUsername(_username);
    if (!mounted) return;
    setState(() {
      _checkingUsername = false;
      _usernameAvailable = available;
    });
  }

  String _nicknameWithDigits(int digitCount, Random rng) {
    final suffix = List.generate(digitCount, (_) => rng.nextInt(10)).join();
    return '${widget.suggestedNickname}$suffix';
  }

  Future<void> _generateAndCheckUsername() async {
    setState(() => _generatingNickname = true);

    final rng = Random();

    for (final digitCount in [4, 5, 6]) {
      for (int attempt = 0; attempt < 20; attempt++) {
        final candidate = _nicknameWithDigits(digitCount, rng);
        final available = await ApiService.checkUsername(candidate);

        if (!mounted) {
          setState(() => _generatingNickname = false);
          return;
        }

        if (available) {
          _settingUsernameProgrammatically = true;
          _usernameController.text = candidate;
          _settingUsernameProgrammatically = false;
          _usernameAvailable = true;
          setState(() => _generatingNickname = false);
          return;
        }
      }
    }

    setState(() => _generatingNickname = false);
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  Future<void> _continue() async {
    if (_displayName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }
    if (_username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a nickname')),
      );
      return;
    }
    if (_username.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nickname must be at least 3 characters')),
      );
      return;
    }

    setState(() => _loading = true);

    String? avatarBase64;
    if (_pickedImage != null) {
      final bytes = await _pickedImage!.readAsBytes();
      avatarBase64 = 'data:image/png;base64,${base64Encode(bytes)}';
    }

    final result = await ApiService.registerWithGoogle(
      idToken: widget.idToken,
      username: _username,
      displayName: _displayName,
      email: widget.email,
      avatarUrl: avatarBase64,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      AuthState.instance.saveSession(
        token: result.token ?? '',
        username: result.username ?? _username,
        displayName: result.displayName ?? _displayName,
        email: result.email ?? widget.email,
        avatarUrl: avatarBase64,
      );
      context.go('/home/chats');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Registration failed'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              _buildHeader(cs),
              const SizedBox(height: 32),
              _buildAvatarSection(cs),
              const SizedBox(height: 32),
              _buildForm(cs),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading || _checkingUsername || _usernameAvailable == false || _username.length < 3 ? null : _continue,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF18A7B5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.person_add, size: 32, color: cs.primary),
        ),
        const SizedBox(height: 16),
        Text(
          'Create Your Profile',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.email,
          style: TextStyle(
            fontSize: 14,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose your display name, nickname, and avatar',
          style: TextStyle(
            fontSize: 13,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarSection(ColorScheme cs) {
    final avatarText = _displayName.isNotEmpty
        ? _displayName[0].toUpperCase()
        : '?';

    return Column(
      children: [
        GestureDetector(
          onTap: _pickImage,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _pickedImage == null
                      ? LinearGradient(
                          colors: [
                            _avatarColors[_selectedColorIndex],
                            _avatarColors[_selectedColorIndex].withValues(alpha: 0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                ),
                child: _pickedImage != null
                    ? ClipOval(
                        child: Image.file(
                          _pickedImage!,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Center(
                        child: Text(
                          avatarText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.surface, width: 3),
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _pickImage,
          child: Text(
            _pickedImage != null ? 'Change Avatar' : 'Set Avatar',
            style: TextStyle(
              color: cs.primary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (_pickedImage == null) ...[
          const SizedBox(height: 12),
          Text(
            'Avatar Color',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(_avatarColors.length, (index) {
              final isSelected = index == _selectedColorIndex;
              return GestureDetector(
                onTap: () => setState(() => _selectedColorIndex = index),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _avatarColors[index],
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: cs.onSurface, width: 3)
                        : null,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: _avatarColors[index].withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildForm(ColorScheme cs) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              style: TextStyle(fontSize: 15, color: cs.onSurface),
              decoration: InputDecoration(
                labelText: 'Display Name',
                labelStyle: TextStyle(color: cs.onSurfaceVariant),
                prefixIcon: Icon(
                  Icons.person_outline,
                  color: cs.onSurfaceVariant,
                  size: 22,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              style: TextStyle(fontSize: 15, color: cs.onSurface),
              decoration: InputDecoration(
                labelText: 'Nickname',
                labelStyle: TextStyle(color: cs.onSurfaceVariant),
                prefixText: '@',
                prefixIcon: Icon(
                  Icons.alternate_email,
                  color: cs.onSurfaceVariant,
                  size: 22,
                ),
                suffixIcon: _username.isEmpty || _username.length < 3
                    ? null
                    : _checkingUsername
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          )
                        : _usernameAvailable == true
                            ? Icon(Icons.check_circle, color: Colors.green)
                            : _usernameAvailable == false
                                ? Icon(Icons.cancel, color: Colors.red)
                                : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    _generatingNickname ? null : _generateAndCheckUsername,
                icon: _generatingNickname
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.shuffle, size: 18),
                label: Text(
                  _generatingNickname
                      ? 'Generating...'
                      : 'Generate Random Nickname',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.primary,
                  side: BorderSide(color: cs.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
