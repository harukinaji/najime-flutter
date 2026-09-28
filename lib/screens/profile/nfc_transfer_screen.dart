import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../data/auth_state.dart';

class NfcTransferScreen extends StatefulWidget {
  const NfcTransferScreen({super.key});

  @override
  State<NfcTransferScreen> createState() => _NfcTransferScreenState();
}

class _NfcTransferScreenState extends State<NfcTransferScreen> {
  static const _bleChannel = MethodChannel('com.naji.najimessenger/bluetooth');
  static const _bleEventChannel = EventChannel(
    'com.naji.najimessenger/bluetooth_events',
  );

  BleDevice? _connectedDevice;
  bool _transferring = false;
  bool _scanning = false;
  List<Map<String, dynamic>> _results = [];
  String? _statusMessage;
  bool _isError = false;
  bool _done = false;
  bool _disposed = false;
  StreamSubscription<dynamic>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _eventSubscription = _bleEventChannel.receiveBroadcastStream().listen((
      dynamic event,
    ) {
      if (_disposed) return;
      final map = event is Map ? Map<String, dynamic>.from(event as Map) : null;
      if (map == null) return;
      switch (map['type'] ?? '') {
        case 'onDeviceFound':
          setState(() => _results.add(map));
          break;
        case 'onConnectionStateChanged':
          final connected = map['connected'] ?? false;
          if (!connected && _connectedDevice?.remoteId == map['deviceId']) {
            setState(() {
              _connectedDevice = null;
              _statusMessage = 'Disconnected';
              _isError = false;
            });
          }
          break;
        case 'onDataReceived':
          setState(() {
            _statusMessage = 'Received: ${map['data']}';
            _isError = false;
          });
          break;
        case 'onBluetoothError':
          setState(() {
            _statusMessage = map['error'] ?? 'BLE error';
            _isError = true;
          });
          break;
      }
    });
  }

  Future<void> _startScan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _results = [];
      _statusMessage = 'Scanning...';
      _isError = false;
      _done = false;
    });
    try {
      await _bleChannel.invokeMethod('startScan', {'services': []});
      if (!_disposed) setState(() => _scanning = false);
    } catch (e) {
      if (!_disposed)
        setState(() {
          _scanning = false;
          _statusMessage = 'Scan failed: $e';
          _isError = true;
        });
    }
  }

  Future<void> _connectToDevice(String address) async {
    if (_transferring) return;
    setState(() {
      _transferring = true;
      _statusMessage = 'Connecting...';
      _isError = false;
    });
    try {
      await _bleChannel.invokeMethod('connect', {'deviceId': address});
      if (!_disposed)
        setState(() {
          _connectedDevice = BleDevice._(address);
          _transferring = false;
          _statusMessage = 'Connected! Tap "Send Profile".';
          _done = false;
        });
    } catch (e) {
      if (!_disposed)
        setState(() {
          _transferring = false;
          _statusMessage = 'Error: ${e.toString()}';
          _isError = true;
        });
    }
  }

  Future<void> _sendProfile() async {
    if (_transferring || _connectedDevice == null) return;
    final payload = await _buildPayload();
    final json = utf8.decode(payload);
    setState(() {
      _transferring = true;
      _statusMessage = 'Sending...';
      _isError = false;
      _done = false;
    });
    try {
      await _bleChannel.invokeMethod('sendRaw', {
        'deviceId': _connectedDevice!.remoteId,
        'data': json,
      });
      if (!mounted) return;
      setState(() {
        _transferring = false;
        _statusMessage = 'Profile sent! Check the badge screen.';
        _isError = false;
        _done = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _transferring = false;
        _statusMessage = 'Error: ${e.toString()}';
        _isError = true;
      });
    }
  }

  Future<Uint8List> _buildPayload() async {
    final a = AuthState.instance;
    final nickname = a.username ?? '';
    final displayName = a.displayName ?? '';
    final parts = displayName.split(' ');
    final firstName = parts.first;
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final avatarUrl = a.avatarUrl ?? '';
    String avatarBase64 = '';
    if (avatarUrl.isNotEmpty) {
      debugPrint('[BLE] avatarUrl: $avatarUrl');
      try {
        if (avatarUrl.startsWith('data:')) {
          final base64Data = avatarUrl.split(',').last;
          final bytes = base64Decode(base64Data);
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            final resized = img.copyResize(decoded, width: 100, height: 100);
            final jpgBytes = img.encodeJpg(resized, quality: 80);
            avatarBase64 = base64Encode(jpgBytes);
            debugPrint('[BLE] avatar base64 len: ${avatarBase64.length}');
          }
        } else {
          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 5);
          final request = await client.getUrl(Uri.parse(avatarUrl));
          final response = await request.close();
          debugPrint('[BLE] avatar HTTP status: ${response.statusCode}');
          if (response.statusCode == 200) {
            final byteList = <int>[];
            await for (final chunk in response) {
              byteList.addAll(chunk);
            }
            final bytes = Uint8List.fromList(byteList);
            debugPrint('[BLE] avatar bytes: ${bytes.length}');
            if (bytes.isNotEmpty) {
              final decoded = img.decodeImage(bytes);
              debugPrint('[BLE] avatar decoded: ${decoded != null}');
              if (decoded != null) {
                final resized = img.copyResize(decoded, width: 32, height: 32);
                final jpgBytes = img.encodeJpg(resized, quality: 80);
                avatarBase64 = base64Encode(jpgBytes);
                debugPrint('[BLE] avatar base64 len: ${avatarBase64.length}');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[BLE] avatar fetch failed: $e');
      }
    } else {
      debugPrint('[BLE] avatarUrl is empty');
    }
    final json = jsonEncode({
      'nick': nickname,
      'first': firstName,
      'last': lastName,
      'avatar': avatarBase64,
    });
    return Uint8List.fromList(json.codeUnits);
  }

  void _disconnect() {
    _bleChannel.invokeMethod('disconnect', {});
    if (!_disposed) {
      setState(() {
        _connectedDevice = null;
        _statusMessage = null;
        _isError = false;
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _eventSubscription?.cancel();
    _disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('NBadge BLE')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            if (_connectedDevice == null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _transferring ? null : _startScan,
                  icon: const Icon(Icons.search),
                  label: const Text(
                    'Scan for NBadge',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              if (_scanning)
                const SizedBox(height: 52, child: CircularProgressIndicator()),
              if (_results.isNotEmpty) ...[
                Text(
                  'Found ${_results.length} device(s)',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                ..._results.map((r) {
                  final name = r['name'] ?? '';
                  final address = r['address'] ?? '';
                  final isConnecting =
                      _connectedDevice?.remoteId == address && _transferring;
                  return ListTile(
                    title: Text(name),
                    subtitle: Text(address),
                    trailing: _connectedDevice?.remoteId == address
                        ? const Icon(
                            Icons.bluetooth_connected,
                            color: Colors.green,
                          )
                        : ElevatedButton(
                            onPressed: isConnecting
                                ? null
                                : () => _connectToDevice(address),
                            child: const Text('Connect'),
                          ),
                  );
                }),
                const SizedBox(height: 16),
              ],
            ],
            if (_connectedDevice != null && !_done) ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _transferring ? null : _sendProfile,
                  icon: _transferring
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.bluetooth),
                  label: Text(
                    _transferring ? 'Sending...' : 'Send Profile',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    disabledBackgroundColor: cs.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.bluetooth_disabled),
                  label: const Text('Disconnect'),
                ),
              ),
            ],
            if (_statusMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isError
                      ? cs.errorContainer
                      : _done
                      ? Colors.green.withValues(alpha: 0.1)
                      : cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isError
                          ? Icons.error_outline
                          : _done
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      color: _isError
                          ? cs.error
                          : _done
                          ? Colors.green
                          : cs.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontSize: 14,
                          color: _isError
                              ? cs.onErrorContainer
                              : _done
                              ? Colors.green.shade800
                              : cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(
    ColorScheme cs, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.onSurfaceVariant, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BleDevice {
  final String remoteId;
  BleDevice._(this.remoteId);
}
