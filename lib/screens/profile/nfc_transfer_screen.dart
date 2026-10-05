import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/auth_state.dart';

class NfcTransferScreen extends StatefulWidget {
  const NfcTransferScreen({super.key});

  @override
  State<NfcTransferScreen> createState() => _NfcTransferScreenState();
}

class _NfcTransferScreenState extends State<NfcTransferScreen> {
  static const _nfcChannel = MethodChannel('com.naji.najimessenger/nfc');
  static const _badgeTextPreferenceKey = 'nbadge_custom_text';

  final _badgeTextController = TextEditingController();

  bool _busy = false;
  bool _ready = false;
  String? _statusMessage;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _loadBadgeText();
  }

  Future<void> _loadBadgeText() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    _badgeTextController.text =
        preferences.getString(_badgeTextPreferenceKey) ?? '';
  }

  Future<void> _prepareTransfer() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _ready = false;
      _statusMessage = 'Preparing your profile for NFC...';
      _isError = false;
    });

    try {
      final available =
          await _nfcChannel.invokeMethod<bool>('isNfcAvailable') ?? false;
      if (!available) {
        throw StateError('This device does not support NFC.');
      }

      final enabled =
          await _nfcChannel.invokeMethod<bool>('isNfcEnabled') ?? false;
      if (!enabled) {
        throw StateError('Turn on NFC in your phone settings, then try again.');
      }

      final hceAvailable =
          await _nfcChannel.invokeMethod<bool>('isHceAvailable') ?? false;
      if (!hceAvailable) {
        throw StateError('This device does not support NFC card emulation.');
      }

      final payload = await _buildPayload();
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _badgeTextPreferenceKey,
        _badgeTextController.text.trim(),
      );
      await _nfcChannel.invokeMethod<bool>('setBadgeData', {'data': payload});
      if (!mounted) return;
      setState(() {
        _ready = true;
        _statusMessage =
            'Ready. Keep this screen open and hold the back of your phone near NBadge.';
        _isError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _ready = false;
        _statusMessage = error is PlatformException
            ? (error.message ?? error.code)
            : error.toString().replaceFirst('Bad state: ', '');
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopTransfer() async {
    try {
      await _nfcChannel.invokeMethod<void>('clearBadgeData');
    } on PlatformException catch (error) {
      debugPrint('[NBadge HCE] Failed to clear badge data: ${error.message}');
    }
    if (!mounted) return;
    setState(() {
      _ready = false;
      _statusMessage = 'NFC sharing stopped.';
      _isError = false;
    });
  }

  Future<Uint8List> _buildPayload() async {
    final auth = AuthState.instance;
    final displayName = auth.displayName ?? '';
    final nameParts = displayName.trim().split(RegExp(r'\s+'));
    final firstName = nameParts.first;
    final lastName = nameParts.length > 1 ? nameParts.skip(1).join(' ') : '';
    final avatarBase64 = await _loadAvatar(auth.avatarUrl ?? '');

    // Keep the same payload schema as the existing NBadge firmware protocol.
    final json = jsonEncode({
      'nick': auth.username ?? '',
      'first': firstName,
      'last': lastName,
      'text': _badgeTextController.text.trim(),
      'avatar': avatarBase64,
    });
    return Uint8List.fromList(utf8.encode(json));
  }

  Future<String> _loadAvatar(String avatarUrl) async {
    if (avatarUrl.isEmpty) return '';
    try {
      late final Uint8List bytes;
      if (avatarUrl.startsWith('data:')) {
        bytes = base64Decode(avatarUrl.split(',').last);
      } else {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 5);
        try {
          final request = await client.getUrl(Uri.parse(avatarUrl));
          final response = await request.close().timeout(
            const Duration(seconds: 8),
          );
          if (response.statusCode != HttpStatus.ok) return '';
          final byteList = <int>[];
          await for (final chunk in response.timeout(
            const Duration(seconds: 8),
          )) {
            byteList.addAll(chunk);
          }
          bytes = Uint8List.fromList(byteList);
        } finally {
          client.close(force: true);
        }
      }

      final decoded = img.decodeImage(bytes);
      if (decoded == null) return '';
      // NBadge always receives an exact 256x256 JPEG. Crop from the centre
      // first so portrait and landscape avatars are not stretched.
      final resized = img.copyResizeCropSquare(decoded, size: 256);

      // NFC throughput is limited by APDU round trips. Keep the avatar at the
      // requested 256x256 resolution, but cap its Base64 representation so a
      // badge does not need hundreds of additional READ BINARY commands.
      for (final quality in const [65, 55, 45, 35, 25]) {
        final encoded = base64Encode(img.encodeJpg(resized, quality: quality));
        if (encoded.length <= 12000 || quality == 25) return encoded;
      }
      return '';
    } catch (error) {
      debugPrint('[NBadge HCE] Avatar could not be prepared: $error');
      return '';
    }
  }

  @override
  void dispose() {
    _nfcChannel.invokeMethod<void>('clearBadgeData').catchError((Object error) {
      debugPrint('[NBadge HCE] Failed to clear badge data: $error');
    });
    _badgeTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('NBadge via NFC')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 12),
          Icon(Icons.contactless, size: 72, color: colors.primary),
          const SizedBox(height: 20),
          Text(
            'Share your profile with NBadge',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Text(
            'Your phone emulates an NFC badge. Prepare your profile, then hold the back of your phone against NBadge.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _badgeTextController,
            enabled: !_busy,
            maxLength: 23,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Badge text',
              hintText: 'Your custom text',
              helperText: 'Displayed between your name and username',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          if (_statusMessage != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _isError
                    ? colors.errorContainer
                    : _ready
                    ? Colors.green.withValues(alpha: 0.12)
                    : colors.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    _isError
                        ? Icons.error_outline
                        : _ready
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    color: _isError
                        ? colors.error
                        : _ready
                        ? Colors.green
                        : colors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: TextStyle(
                        color: _isError
                            ? colors.onErrorContainer
                            : _ready
                            ? Colors.green.shade800
                            : colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _busy ? null : _prepareTransfer,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(_ready ? Icons.refresh : Icons.nfc),
              label: Text(
                _busy
                    ? 'Preparing...'
                    : _ready
                    ? 'Refresh profile'
                    : 'Prepare for NBadge',
              ),
            ),
          ),
          if (_ready) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _stopTransfer,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop NFC sharing'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _infoCard(
            colors,
            icon: Icons.nfc,
            title: 'No Bluetooth pairing',
            subtitle:
                'NBadge reads your profile directly over NFC card emulation.',
          ),
          const SizedBox(height: 12),
          _infoCard(
            colors,
            icon: Icons.lock_outline,
            title: 'Only while this screen is open',
            subtitle:
                'The badge data is cleared when you leave this screen or stop sharing.',
          ),
        ],
      ),
    );
  }

  Widget _infoCard(
    ColorScheme colors, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.onSurfaceVariant, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
