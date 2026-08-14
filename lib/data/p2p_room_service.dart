import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import 'api_service.dart';
import 'auth_state.dart';
import 'websocket_service.dart';

class _P2PPeer {
  final String peerId;
  RTCPeerConnection? pc;
  RTCDataChannel? dc;
  MediaStream? remoteStream;
  bool inVoice = false;
  bool muted = false;
  String state;
  double? latencyMs;
  int _pingSeq = 0;
  final Map<int, int> _pendingPings = {};
  Timer? removalTimer;

  _P2PPeer({required this.peerId, this.state = 'connecting'});

  bool get connected =>
      state == 'connected' &&
      dc != null &&
      dc!.state == RTCDataChannelState.RTCDataChannelOpen;

  void handlePong(int seq, int sentAt) {
    final pending = _pendingPings.remove(seq);
    if (pending == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    latencyMs = (now - sentAt).toDouble();
  }
}

class P2PRoomService {
  P2PRoomService._();
  static final P2PRoomService instance = P2PRoomService._();

  String? _roomId;
  Map<String, dynamic>? _room;
  final Map<String, _P2PPeer> _peers = {};
  bool _listening = false;
  MediaStream? _localAudioStream;
  bool _voiceActive = false;
  bool _voiceMuted = false;

  void Function()? onChanged;
  void Function(String from, String eventName, Map<String, dynamic> payload)?
      onEvent;

  String get selfId => AuthState.instance.username ?? 'anonymous';

  String? get roomId => _roomId;

  bool get inRoom => _roomId != null;

  Map<String, dynamic> get multiplayerState {
    final peers = _peers.values
        .map((p) => {
              'id': p.peerId,
              'state': p.state,
              'connected': p.connected,
              'latency_ms': p.latencyMs,
              'in_voice': p.inVoice || p.remoteStream != null,
              'muted': p.muted,
            })
        .toList();
    return {
      'room': _room,
      'room_id': _roomId,
      'player_count': _peers.length + 1,
      'connected_count': _peers.values.where((p) => p.connected).length,
      'peers': peers,
    };
  }

  Map<String, dynamic> get voiceState {
    final participants = _peers.values
        .map((p) => {
              'user_id': p.peerId,
              'in_voice': p.inVoice || p.remoteStream != null,
              'muted': p.muted,
            })
        .toList();
    return {
      'connected': _voiceActive,
      'muted': _voiceMuted,
      'participants': participants,
    };
  }

  void _notify() {
    onChanged?.call();
  }

  Future<List<Map<String, dynamic>>> _iceServers() async {
    final servers = <Map<String, dynamic>>[
      {'urls': 'stun:${AppConfig.webrtcHost}:3478'},
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];
    try {
      final creds = await ApiService.fetchTurnCredentials();
      if (creds != null) {
        servers.add({
          'urls': 'turn:${AppConfig.webrtcHost}:3478',
          'username': creds['username'],
          'credential': creds['credential'],
        });
      }
    } catch (_) {}
    return servers;
  }

  void _startListening() {
    if (_listening) return;
    _listening = true;
    WebSocketService.on('p2p_signal', _onWsSignal);
    WebSocketService.on('p2p_peer_join', _onWsPeerJoin);
  }

  void _stopListening() {
    if (!_listening) return;
    _listening = false;
    WebSocketService.off('p2p_signal', _onWsSignal);
    WebSocketService.off('p2p_peer_join', _onWsPeerJoin);
  }

  Future<void> createRoom({int maxPlayers = 8}) async {
    await leaveRoom();
    final room = await ApiService.createMultiplayerRoom(maxPlayers: maxPlayers);
    if (room == null) return;
    _roomId = room['id'] as String?;
    _room = room;
    _startListening();
    _notify();
  }

  Future<void> joinRoom(String roomId) async {
    await leaveRoom();
    final room = await ApiService.joinMultiplayerRoom(roomId);
    if (room == null) return;
    _roomId = room['id'] as String?;
    _room = room;
    _startListening();
    _notify();
    final players = (room['players'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    for (final pid in players) {
      if (pid != selfId && pid.isNotEmpty) {
        unawaited(_connectTo(pid));
      }
    }
  }

  Future<bool> joinMatchmaking() async {
    await leaveRoom();
    final result = await ApiService.joinMatchmaking();
    if (result == null) return false;
    final room = result['room'] as Map<String, dynamic>?;
    final roomId = room?['id'] as String?;
    if (roomId == null || roomId.isEmpty) return false;
    _roomId = roomId;
    _room = room;
    _startListening();
    _notify();
    final players = (room?['players'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    if (kDebugMode) debugPrint('[P2P] matchmaking ok room=$roomId players=$players selfId=$selfId');
    for (final pid in players) {
      if (pid != selfId && pid.isNotEmpty) {
        unawaited(_connectTo(pid));
      }
    }
    return true;
  }

  Future<void> leaveRoom() async {
    final roomId = _roomId;
    if (roomId != null) {
      ApiService.leaveMultiplayerRoom(roomId);
    }
    if (_localAudioStream != null) {
      for (final track in _localAudioStream!.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      _localAudioStream = null;
    }
    _voiceActive = false;
    _voiceMuted = false;
    for (final peer in _peers.values) {
      try {
        if (peer.dc != null) {
          await peer.dc!.close();
        }
        await peer.pc?.close();
      } catch (_) {}
    }
    _peers.clear();
    _room = null;
    _roomId = null;
    _stopListening();
    _notify();
  }

  void dispose() {
    _stopListening();
    for (final peer in _peers.values) {
      try {
        peer.dc?.close();
        peer.pc?.close();
      } catch (_) {}
    }
    _peers.clear();
    _roomId = null;
    _room = null;
  }

  void sendToPeers(String eventName, Map<String, dynamic> payload,
      {String? except, bool transient = false}) {
    final msg = {
      'kind': 'event',
      'eventName': eventName,
      'payload': payload,
      'transient': transient,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    for (final peer in _peers.values) {
      if (peer.peerId == except) continue;
      _sendRaw(peer, msg);
    }
  }

  void _sendRaw(_P2PPeer peer, Map<String, dynamic> msg) {
    final dc = peer.dc;
    if (dc == null ||
        dc.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    try {
      dc.send(RTCDataChannelMessage(jsonEncode(msg)));
    } catch (_) {}
  }

  void _sendSignal(String to, String type,
      {Map<String, dynamic>? sdp,
      Map<String, dynamic>? candidate}) {
    WebSocketService.sendSignal('p2p_signal', {
      'contact_id': to,
      'type': type,
      'room_id': _roomId,
      if (sdp != null) 'sdp': sdp,
      if (candidate != null) 'candidate': candidate,
    });
  }

  Future<void> _connectTo(String peerId) async {
    _P2PPeer peer;
    try {
      final servers = await _iceServers();
      final pc = await createPeerConnection({'iceServers': servers});
      peer = _ensurePeer(peerId);
      peer.pc = pc;
      _wirePc(peerId, pc);

      final dc = await pc.createDataChannel('naji', RTCDataChannelInit()..ordered = true);
      _wireDc(peerId, dc);

      if (_voiceActive && _localAudioStream != null) {
        await _ensureAudioSender(peer);
      }

      final offer = await pc.createOffer({'offerToReceiveAudio': true});
      await pc.setLocalDescription(offer);
      _sendSignal(peerId, 'offer', sdp: _sdpMap(offer));
    } catch (e) {
      if (kDebugMode) debugPrint('[P2P] connectTo($peerId) failed: $e');
      _removePeer(peerId, reason: 'connect_failed');
    }
  }

  _P2PPeer _ensurePeer(String peerId) {
    final existing = _peers[peerId];
    if (existing != null) return existing;
    final peer = _P2PPeer(peerId: peerId, state: 'connecting');
    _peers[peerId] = peer;
    _notify();
    return peer;
  }

  void _wirePc(String peerId, RTCPeerConnection pc) {
    pc.onIceCandidate = (candidate) {
      _sendSignal(peerId, 'ice', candidate: {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    pc.onDataChannel = (dc) {
      _wireDc(peerId, dc);
    };
    pc.onTrack = (event) {
      if (event.track.kind == 'audio' && event.streams.isNotEmpty) {
        final peer = _peers[peerId];
        if (peer != null) {
          peer.remoteStream = event.streams.first;
          peer.inVoice = true;
          _notify();
        }
      }
    };
    pc.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        if (kDebugMode) debugPrint('[P2P] ice state failed/closed for $peerId');
        _removePeer(peerId, reason: 'ice_$state');
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        final peer = _peers[peerId];
        if (peer != null) {
          peer.removalTimer?.cancel();
          peer.removalTimer = null;
          peer.state = 'connected';
          _notify();
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        final peer = _peers[peerId];
        if (peer != null && peer.removalTimer == null) {
          peer.removalTimer = Timer(const Duration(seconds: 8), () {
            final cur = _peers[peerId];
            if (cur != null &&
                cur.pc?.connectionState !=
                    RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
              _removePeer(peerId);
            } else if (cur != null) {
              cur.removalTimer = null;
            }
          });
        }
      }
    };
  }

  void _wireDc(String peerId, RTCDataChannel dc) {
    final peer = _peers[peerId];
    if (peer != null) {
      peer.dc = dc;
    }
    dc.stateChangeStream.listen((state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        final p = _peers[peerId];
        if (p != null) {
          p.state = 'connected';
          p.latencyMs = null;
        }
        _notify();
        if (_voiceActive) {
          _broadcastVoiceState();
        }
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _notify();
      }
    });
    dc.messageStream.listen((message) {
      if (message.isBinary) return;
      _handleData(peerId, message.text);
    });
  }

  void _handleData(String peerId, String text) {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final kind = data['kind'];
    final peer = _peers[peerId];
    if (kind == 'ping') {
      if (peer != null) {
        _sendRaw(peer, {'kind': 'pong', 'seq': data['seq'], 'ts': data['ts']});
      }
    } else if (kind == 'pong') {
      final seq = data['seq'];
      if (seq is int && peer != null) {
        peer.handlePong(seq, (data['ts'] as num?)?.toInt() ?? 0);
      }
      _notify();
    } else if (kind == 'voice_state') {
      final payload =
          (data['payload'] as Map?)?.cast<String, dynamic>() ?? {};
      final p = _peers[peerId];
      if (p != null) {
        p.inVoice = payload['in_voice'] as bool? ?? false;
        p.muted = payload['muted'] as bool? ?? false;
      }
      _notify();
    } else if (kind == 'event') {
      final eventName = data['eventName'] as String? ?? '';
      final payload = (data['payload'] as Map?)?.cast<String, dynamic>() ?? {};
      onEvent?.call(peerId, eventName, payload);
    }
  }

  Future<void> _handleOffer(String from, Map<String, dynamic> data) async {
    final peer = _ensurePeer(from);
    try {
      if (peer.pc == null) {
        final servers = await _iceServers();
        final pc = await createPeerConnection({'iceServers': servers});
        peer.pc = pc;
        _wirePc(from, pc);
      }
      if (peer.pc!.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        try {
          await peer.pc!.setLocalDescription(
            RTCSessionDescription('', 'rollback'),
          );
        } catch (_) {}
      }
      final sdp = (data['sdp'] as Map?);
      await peer.pc!.setRemoteDescription(
        RTCSessionDescription((sdp?['sdp'] as String?) ?? '', 'offer'),
      );
      if (_voiceActive && _localAudioStream != null) {
        await _ensureAudioSender(peer);
      }
      final answer = await peer.pc!.createAnswer({'offerToReceiveAudio': true});
      await peer.pc!.setLocalDescription(answer);
      _sendSignal(from, 'answer', sdp: _sdpMap(answer));
    } catch (e) {
      if (kDebugMode) debugPrint('[P2P] handleOffer($from) failed: $e');
    }
  }

  Future<void> _handleAnswer(String from, Map<String, dynamic> data) async {
    final peer = _peers[from];
    if (peer?.pc == null) return;
    try {
      final sdp = (data['sdp'] as Map?);
      await peer!.pc!.setRemoteDescription(
        RTCSessionDescription((sdp?['sdp'] as String?) ?? '', 'answer'),
      );
    } catch (_) {}
  }

  Future<void> _handleIce(String from, Map<String, dynamic> data) async {
    final peer = _peers[from];
    if (peer?.pc == null) return;
    try {
      final cand = (data['candidate'] as Map?) ?? const {};
      await peer!.pc!.addCandidate(RTCIceCandidate(
        cand['candidate'] as String?,
        cand['sdpMid'] as String?,
        cand['sdpMLineIndex'] as int?,
      ));
    } catch (_) {}
  }

  Map<String, dynamic>? _sdpMap(RTCSessionDescription? desc) {
    if (desc == null) return null;
    return {'sdp': desc.sdp, 'type': desc.type};
  }

  void _onWsSignal(dynamic msg) {
    final data = (msg as Map?)?.cast<String, dynamic>() ?? {};
    final type = data['type'] as String?;
    final from = data['from'] as String?;
    if (kDebugMode) debugPrint('[P2P] ws signal type=$type from=$from');
    if (type == null || from == null || from == selfId) return;
    if (_roomId == null) return;
    final roomId = data['room_id'] as String?;
    if (roomId != null && roomId != _roomId) return;
    switch (type) {
      case 'offer':
        unawaited(_handleOffer(from, data));
        break;
      case 'answer':
        unawaited(_handleAnswer(from, data));
        break;
      case 'ice':
        unawaited(_handleIce(from, data));
        break;
      case 'bye':
        _removePeer(from, reason: 'bye');
        break;
    }
  }

  void _onWsPeerJoin(dynamic msg) {
    final data = (msg as Map?)?.cast<String, dynamic>() ?? {};
    final peerId = data['peer_id'] as String?;
    if (kDebugMode) debugPrint('[P2P] ws peer_join peerId=$peerId room=$_roomId selfId=$selfId');
    if (_roomId == null || peerId == null || peerId == selfId) return;
    if (!_peers.containsKey(peerId)) {
      _ensurePeer(peerId);
      _notify();
    }
  }

  void _removePeer(String peerId, {String reason = 'unknown'}) {
    final peer = _peers.remove(peerId);
    if (kDebugMode) debugPrint('[P2P] removePeer $peerId reason=$reason peersLeft=${_peers.length}');
    if (peer == null) return;
    peer.removalTimer?.cancel();
    peer.removalTimer = null;
    try {
      peer.dc?.close();
      peer.pc?.close();
    } catch (_) {}
    peer.remoteStream = null;
    _notify();
  }

  void sendPing() {
    for (final peer in _peers.values) {
      if (!peer.connected) continue;
      final seq = ++peer._pingSeq;
      final ts = DateTime.now().millisecondsSinceEpoch;
      peer._pendingPings[seq] = ts;
      _sendRaw(peer, {'kind': 'ping', 'seq': seq, 'ts': ts});
    }
  }

  // ── Voice (mesh over existing P2P connections) ────────────────────

  bool get voiceActive => _voiceActive;

  bool get voiceMuted => _voiceMuted;

  MediaStream? get localAudioStream => _localAudioStream;

  Future<bool> joinVoice() async {
    if (_voiceActive) return true;
    if (kDebugMode) debugPrint('[P2P] joinVoice: requesting mic');
    try {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        if (kDebugMode) debugPrint('[P2P] joinVoice: mic permission denied: $mic');
        return false;
      }
      _localAudioStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
      });
      _ensureAudioSession();
    } catch (e) {
      if (kDebugMode) debugPrint('[P2P] joinVoice: getUserMedia error: $e');
      _localAudioStream = null;
      return false;
    }
    _voiceActive = true;
    _voiceMuted = false;
    for (final peer in _peers.values) {
      if (peer.pc != null && peer.connected) {
        await _ensureAudioSender(peer);
        unawaited(_renegotiate(peer));
      }
    }
    _broadcastVoiceState();
    _notify();
    return true;
  }

  Future<void> leaveVoice() async {
    if (!_voiceActive) return;
    _voiceActive = false;
    _voiceMuted = false;
    for (final peer in _peers.values) {
      final pc = peer.pc;
      if (pc == null) continue;
      try {
        final senders = await pc.getSenders();
        for (final s in senders) {
          if (s.track?.kind == 'audio') {
            await pc.removeTrack(s);
          }
        }
      } catch (_) {}
      unawaited(_renegotiate(peer));
    }
    if (_localAudioStream != null) {
      for (final track in _localAudioStream!.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      _localAudioStream = null;
    }
    for (final peer in _peers.values) {
      peer.inVoice = false;
      peer.remoteStream = null;
    }
    _broadcastVoiceState();
    _notify();
  }

  Future<void> setMuted(bool muted) async {
    _voiceMuted = muted;
    final tracks = _localAudioStream?.getAudioTracks() ?? [];
    if (tracks.isNotEmpty) {
      tracks.first.enabled = !muted;
    }
    _broadcastVoiceState();
    _notify();
  }

  void _ensureAudioSession() {
    try {
      Helper.setAndroidAudioConfiguration(
        AndroidAudioConfiguration.communication,
      );
    } catch (_) {}
    try {
      Helper.ensureAudioSession();
    } catch (_) {}
    try {
      Helper.setSpeakerphoneOn(true);
    } catch (_) {}
  }

  Future<void> _ensureAudioSender(_P2PPeer peer) async {
    final pc = peer.pc;
    final tracks = _localAudioStream?.getAudioTracks() ?? [];
    if (pc == null || tracks.isEmpty) return;
    try {
      final senders = await pc.getSenders();
      final hasAudio = senders.any((s) => s.track?.kind == 'audio');
      if (!hasAudio) {
        await pc.addTrack(tracks.first, _localAudioStream!);
      }
    } catch (_) {}
  }

  Future<void> _renegotiate(_P2PPeer peer) async {
    final pc = peer.pc;
    if (pc == null) return;
    try {
      final offer = await pc.createOffer({'offerToReceiveAudio': true});
      await pc.setLocalDescription(offer);
      _sendSignal(peer.peerId, 'offer', sdp: _sdpMap(offer));
    } catch (_) {}
  }

  void _broadcastVoiceState() {
    for (final peer in _peers.values) {
      if (peer.dc != null &&
          peer.dc!.state == RTCDataChannelState.RTCDataChannelOpen) {
        _sendRaw(peer, {
          'kind': 'voice_state',
          'payload': {
            'user_id': selfId,
            'in_voice': _voiceActive,
            'muted': _voiceMuted,
          },
        });
      }
    }
  }
}
