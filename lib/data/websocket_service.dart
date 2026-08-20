import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

import '../config.dart';
import 'app_attestation.dart';
import 'api_service.dart';
import 'secure_http_client.dart';
import 'webrtc_service.dart';

class WebSocketService {
  static WebSocket? _socket;
  static bool _connecting = false;
  static final _listeners = <String, List<Function(dynamic)>>{};
  static String? _token;
  static final List<Map<String, dynamic>> _pending = [];
  static Timer? _reconnectTimer;
  static int _reconnectDelay = 1;
  static const int _maxReconnectDelay = 30;
  static final String _deviceId = _generateDeviceId();
  static bool _skipAttestation = false;

  static String _generateDeviceId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
    return '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}-'
        '${hex(bytes[4])}${hex(bytes[5])}-'
        '${hex(bytes[6])}${hex(bytes[7])}-'
        '${hex(bytes[8])}${hex(bytes[9])}-'
        '${hex(bytes[10])}${hex(bytes[11])}${hex(bytes[12])}${hex(bytes[13])}${hex(bytes[14])}${hex(bytes[15])}';
  }
  static VoidCallback? onConnected;
  static VoidCallback? onAuthExpired;

  static bool get isConnected => _socket != null;

  static void connect(String token) {
    _token = token;
    _reconnectDelay = 1;
    _skipAttestation = false;
    _connect();
  }

  static void _handleAuthExpired() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connecting = false;
    _socket?.close();
    _socket = null;
    // Don't log the user out on the first transient 401. The WS handshake can
    // fail with 401 while the backend is mid-restart or the network blipped
    // even though the JWT stored on-device is still perfectly valid. Recheck
    // the token against a normal REST endpoint first: if `/api/me` still
    // succeeds, the session is alive — just reconnect WS. Only when the REST
    // call also rejects (token truly expired/revoked) do we treat it as
    // session-expired and force re-login via [onAuthExpired].
    _verifyTokenBeforeLogout();
  }

  static Future<void> _verifyTokenBeforeLogout() async {
    final user = await ApiService.getCurrentUser();
    if (user != null) {
      debugPrint('[WS] 401 false alarm — REST token is still valid; '
          'reconnecting WS without logout');
      _reconnectDelay = 1;
      _connect();
      return;
    }
    debugPrint('[WS] Session really expired (REST also unauthorized) — '
        'forcing re-login');
    onAuthExpired?.call();
  }

  static Future<void> _connect() async {
    if (_socket != null || _connecting || _token == null) return;
    _connecting = true;

    final uri = Uri.parse(
        '${AppConfig.wsBaseUrl}/ws?device_id=$_deviceId');
    debugPrint('[WS] Connecting to ${AppConfig.wsBaseUrl}/ws');

    // Get attestation headers for the WS handshake (skip if not registered)
    final attestation = AppAttestation.instance;
    final Map<String, String> attestationHeaders;
    if (_skipAttestation || !await attestation.isKeyRegistered()) {
      attestationHeaders = {};
    } else {
      attestationHeaders = await attestation.signRequest(
        method: 'GET',
        path: '/ws',
      );
    }

    final httpClient = HttpClient();
    if (SignedHttpClient.shouldOverrideCertificateVerification) {
      httpClient.badCertificateCallback = (cert, host, port) =>
          SignedHttpClient.verifyServerCertificate(cert, host, port);
    }

    final appKey = appKeyValue();
    WebSocket.connect(
      uri.toString(),
      headers: {
        'X-WS-Token': _token!,
        if (appKey.isNotEmpty) appKeyHeaderName: appKey,
        ...attestationHeaders,
      },
      customClient: httpClient,
    ).then((ws) {
      _socket = ws;
      _connecting = false;
      _reconnectDelay = 1;
      debugPrint('[WS] Connected');

      sendStatus(true);
      for (final p in _pending) {
        _send(p);
      }
      _pending.clear();
      onConnected?.call();

      ws.listen((data) {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          final event = msg['event'] as String?;
          final msgData = msg['data'] as Map<String, dynamic>? ?? {};

          if (event == null) return;

          if (event == 'new_message') {
            final ev = _listeners[event];
            if (ev != null) {
              for (final cb in ev) {
                cb(msgData);
              }
            }
            return;
          }

          if (event == 'offer') {
            WebRTCService.handleOffer(msgData);
            return;
          }

          if (event == 'answer') {
            WebRTCService.handleAnswer(msgData);
            return;
          }

          if (event == 'ice_candidate') {
            WebRTCService.handleIceCandidate(msgData);
            return;
          }

          if (event == 'call_end') {
            WebRTCService.handleRemoteEnd(msgData);
            return;
          }

          if (event == 'reaction_added' || event == 'reaction_removed') {
            final ev = _listeners[event];
            if (ev != null) {
              for (final cb in ev) {
                cb(msgData);
              }
            }
            return;
          }

          if (event.startsWith('sfu_')) {
            final ev = _listeners[event];
            if (ev != null) {
              for (final cb in ev) {
                cb(msgData);
              }
            }
            return;
          }

          final ev = _listeners[event];
          if (ev != null) {
            for (final cb in ev) {
              cb(msgData);
            }
          }
        } catch (_) {}
      }, onDone: () {
        debugPrint('[WS] Disconnected, reconnecting in ${_reconnectDelay}s...');
        _socket = null;
        _scheduleReconnect();
      }, onError: (e) {
        debugPrint('[WS] Error: $e, reconnecting in ${_reconnectDelay}s...');
        _socket = null;
        _scheduleReconnect();
      });
    }).catchError((e) {
      _connecting = false;
      _socket = null;
      final msg = e.toString();
      if (msg.contains('401')) {
        debugPrint('[WS] Handshake 401 -> session expired');
        _handleAuthExpired();
        return;
      }
      if (msg.contains('403')) {
        debugPrint('[WS] Handshake 403 -> attestation failed, retrying without');
        _skipAttestation = true;
        _scheduleReconnect();
        return;
      }
      debugPrint('[WS] Connect error: $e, retrying in ${_reconnectDelay}s...');
      _scheduleReconnect();
    });
  }
  static void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelay), () {
      _reconnectDelay = (_reconnectDelay * 2).clamp(1, _maxReconnectDelay);
      _connect();
    });
  }

  static void reconnect() {
    _reconnectTimer?.cancel();
    _socket?.close();
    _socket = null;
    _connecting = false;
    _reconnectDelay = 1;
    _skipAttestation = false;
    _connect();
  }

  static void _send(Map<String, dynamic> msg) {
    if (_socket != null) {
      _socket!.add(jsonEncode(msg));
    }
  }

  static bool sendSignal(String event, Map<String, dynamic> data) {
    final msg = {'event': event, 'to': data['contact_id'], 'data': data};
    if (_socket != null) {
      _send(msg);
      return true;
    }
    _pending.add(msg);
    return true;
  }

  static void on(String event, Function(dynamic) callback) {
    _listeners.putIfAbsent(event, () => []).add(callback);
  }

  static void off(String event, Function(dynamic) callback) {
    _listeners[event]?.remove(callback);
  }

  static void sendStatus(bool isOnline) {
    final msg = {'event': 'status', 'data': {'is_online': isOnline}};
    if (_socket != null) {
      _send(msg);
    } else {
      _pending.add(msg);
    }
  }

  static void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    sendStatus(false);
    _socket?.close();
    _socket = null;
    _listeners.clear();
    _pending.clear();
    _connecting = false;
    _token = null;
  }
}
