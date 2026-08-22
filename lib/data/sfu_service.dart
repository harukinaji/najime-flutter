import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../config.dart';
import 'api_service.dart';
import 'websocket_service.dart';

class SFUParticipantInfo {
  final String userId;
  final String displayName;
  MediaStream? stream;

  SFUParticipantInfo({
    required this.userId,
    required this.displayName,
    this.stream,
  });
}

class SFUService {
  static String? _currentRoomId;
  static RTCPeerConnection? _peerConnection;
  static MediaStream? _localStream;
  static bool _isInitialized = false;
  static bool _isMuted = false;
  static bool _isVideoOff = false;

  static final Map<String, SFUParticipantInfo> _participants = {};
  static final Map<String, MediaStream> _remoteStreams = {};
  static final Map<String, RTCVideoRenderer> _remoteRenderers = {};

  static final _onParticipantJoinedController =
      StreamController<SFUParticipantInfo>.broadcast();
  static final _onParticipantLeftController =
      StreamController<String>.broadcast();
  static final _onStreamAddedController =
      StreamController<MapEntry<String, MediaStream>>.broadcast();
  static final _onStreamRemovedController =
      StreamController<String>.broadcast();
  static final _onConnectedController = StreamController<void>.broadcast();
  static final _onDisconnectedController = StreamController<void>.broadcast();
  static final _onErrorController = StreamController<String>.broadcast();

  static Stream<SFUParticipantInfo> get onParticipantJoined =>
      _onParticipantJoinedController.stream;
  static Stream<String> get onParticipantLeft =>
      _onParticipantLeftController.stream;
  static Stream<MapEntry<String, MediaStream>> get onStreamAdded =>
      _onStreamAddedController.stream;
  static Stream<String> get onStreamRemoved =>
      _onStreamRemovedController.stream;
  static Stream<void> get onConnected => _onConnectedController.stream;
  static Stream<void> get onDisconnected => _onDisconnectedController.stream;
  static Stream<String> get onError => _onErrorController.stream;

  static String? get currentRoomId => _currentRoomId;
  static bool get isInitialized => _isInitialized;
  static bool get isMuted => _isMuted;
  static bool get isVideoOff => _isVideoOff;
  static MediaStream? get localStream => _localStream;
  static Map<String, SFUParticipantInfo> get participants =>
      Map.unmodifiable(_participants);
  static Map<String, MediaStream> get remoteStreams =>
      Map.unmodifiable(_remoteStreams);

  static Future<void> initialize() async {
    if (_isInitialized) return;

    WebSocketService.on('sfu_room_joined', _onRoomJoined);
    WebSocketService.on('sfu_participant_joined', _onParticipantJoined);
    WebSocketService.on('sfu_participant_left', _onParticipantLeft);
    WebSocketService.on('sfu_transport_created', _onTransportCreated);
    WebSocketService.on('sfu_ice_candidate', _onIceCandidate);
    WebSocketService.on('sfu_producer_created', _onProducerCreated);
    WebSocketService.on('sfu_consumer_created', _onConsumerCreated);
    WebSocketService.on('sfu_producer_paused', _onProducerPaused);
    WebSocketService.on('sfu_producer_resumed', _onProducerResumed);
    WebSocketService.on('sfu_connection_issue', _onConnectionIssue);
    WebSocketService.on('sfu_error', _onSFUError);

    _isInitialized = true;
  }

  static Future<void> joinRoom({
    required String roomId,
    required bool video,
  }) async {
    await initialize();

    _currentRoomId = roomId;
    _localStream = await _getLocalStream(video);

    await _createPeerConnection();

    final displayName = ApiService.username ?? 'Unknown';

    WebSocketService.sendSignal('sfu_join_room', {
      'contact_id': '',
      'room_id': roomId,
      'display_name': displayName,
      'video': video,
    });
  }

  static Future<MediaStream> _getLocalStream(bool video) async {
    return await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video,
    });
  }

  static Future<void> createTransport({
    required String transportId,
    required String direction,
  }) async {
    WebSocketService.sendSignal('sfu_create_transport', {
      'contact_id': '',
      'room_id': _currentRoomId,
      'transport_id': transportId,
      'direction': direction,
    });
  }

  static void _onRoomJoined(dynamic data) {
    if (data is! Map) return;
    final roomId = data['room_id'] as String?;
    final participants = data['participants'] as List?;

    if (roomId != _currentRoomId) return;

    if (participants != null) {
      for (final p in participants) {
        if (p is Map) {
          final uid = p['user_id'] as String?;
          final name = p['display_name'] as String?;
          if (uid != null && name != null) {
            _participants[uid] = SFUParticipantInfo(
              userId: uid,
              displayName: name,
            );
            _onParticipantJoinedController.add(_participants[uid]!);
          }
        }
      }
    }
  }

  static Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:${AppConfig.webrtcHost}:3478'},
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });

    _peerConnection!.onIceCandidate = (candidate) {
      WebSocketService.sendSignal('sfu_ice_candidate', {
        'contact_id': '',
        'room_id': _currentRoomId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex ?? 0,
        },
      });
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        final stream = event.streams.first;
        String? participantId;
        for (final entry in _participants.entries) {
          if (!_remoteStreams.containsKey(entry.key)) {
            participantId = entry.key;
            break;
          }
        }
        participantId ??= 'stream-${_remoteStreams.length}';

        _remoteStreams[participantId] = stream;
        _onStreamAddedController.add(MapEntry(participantId, stream));

        if (_participants.containsKey(participantId)) {
          _participants[participantId]!.stream = stream;
        }
      }
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _onConnectedController.add(null);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _onDisconnectedController.add(null);
      }
    };
  }

  static void _onTransportCreated(dynamic data) {
    if (data is! Map) return;
    final roomId = data['room_id'] as String?;
    final sdpData = data['sdp'] as Map?;

    if (roomId != _currentRoomId || sdpData == null) return;

    final sdp = sdpData['sdp'] as String?;
    final type = sdpData['type'] as String?;

    if (sdp == null || type == null) return;

    _peerConnection
        ?.setRemoteDescription(RTCSessionDescription(sdp, type))
        .then((_) async {
          if (type == 'offer') {
            if (_localStream != null && _peerConnection != null) {
              final senders = await _peerConnection!.getSenders();
              final existingTrackIds = senders
                  .where((s) => s.track != null)
                  .map((s) => s.track!.id)
                  .toSet();

              for (final track in _localStream!.getTracks()) {
                if (!existingTrackIds.contains(track.id)) {
                  await _peerConnection!.addTrack(track, _localStream!);
                }
              }
            }

            final answer = await _peerConnection!.createAnswer();
            await _peerConnection!.setLocalDescription(answer);

            WebSocketService.sendSignal('sfu_connect_transport', {
              'contact_id': '',
              'room_id': _currentRoomId,
              'transport_id': 'main',
              'sdp': {'sdp': answer.sdp, 'type': 'answer'},
            });
          }
        });
  }

  static void _onIceCandidate(dynamic data) {
    if (data is! Map) return;
    final candidateData = data['candidate'] as Map?;
    if (candidateData == null) return;

    final candidate = candidateData['candidate'] as String?;
    final sdpMid = candidateData['sdpMid'] as String?;
    final sdpMLineIndex = candidateData['sdpMLineIndex'] as int?;

    if (candidate != null) {
      _peerConnection?.addCandidate(
        RTCIceCandidate(candidate, sdpMid, sdpMLineIndex ?? 0),
      );
    }
  }

  static void _onParticipantJoined(dynamic data) {
    if (data is! Map) return;
    final roomId = data['room_id'] as String?;
    final userId = data['user_id'] as String?;
    final displayName = data['display_name'] as String?;

    if (roomId != _currentRoomId || userId == null) return;

    final info = SFUParticipantInfo(
      userId: userId,
      displayName: displayName ?? userId,
    );
    _participants[userId] = info;
    _onParticipantJoinedController.add(info);
  }

  static void _onParticipantLeft(dynamic data) {
    if (data is! Map) return;
    final roomId = data['room_id'] as String?;
    final userId = data['user_id'] as String?;

    if (roomId != _currentRoomId || userId == null) return;

    _participants.remove(userId);
    final stream = _remoteStreams.remove(userId);
    stream?.dispose();
    _remoteRenderers[userId]?.dispose();
    _remoteRenderers.remove(userId);

    _onParticipantLeftController.add(userId);
    _onStreamRemovedController.add(userId);
  }

  static void _onProducerCreated(dynamic data) {
    if (data is! Map) return;
    final producerId = data['producer_id'] as String?;
    final kind = data['kind'] as String?;
    if (kDebugMode) debugPrint('[SFU] Producer created: $producerId ($kind)');
  }

  static void _onConsumerCreated(dynamic data) {
    if (data is! Map) return;
    final producerId = data['producer_id'] as String?;
    final producerUid = data['producer_uid'] as String?;
    if (kDebugMode)
      debugPrint(
        '[SFU] Consumer created for producer: $producerId from $producerUid',
      );
  }

  static void _onProducerPaused(dynamic data) {
    if (data is! Map) return;
    final producerId = data['producer_id'] as String?;
    if (kDebugMode) debugPrint('[SFU] Producer paused: $producerId');
  }

  static void _onProducerResumed(dynamic data) {
    if (data is! Map) return;
    final producerId = data['producer_id'] as String?;
    if (kDebugMode) debugPrint('[SFU] Producer resumed: $producerId');
  }

  static void _onConnectionIssue(dynamic data) {
    if (data is! Map) return;
    final roomId = data['room_id'] as String?;
    if (roomId == _currentRoomId) {
      if (kDebugMode) debugPrint('[SFU] Connection issue in room $roomId');
    }
  }

  static void _onSFUError(dynamic data) {
    if (data is! Map) return;
    final message = data['message'] as String? ?? 'Unknown error';
    _onErrorController.add(message);
  }

  static Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !_isMuted;
      }
    }

    WebSocketService.sendSignal('sfu_pause_producer', {
      'contact_id': '',
      'room_id': _currentRoomId,
      'producer_id': '${ApiService.username}-audio',
    });
  }

  static Future<void> toggleVideo() async {
    _isVideoOff = !_isVideoOff;
    if (_localStream != null) {
      for (final track in _localStream!.getVideoTracks()) {
        track.enabled = !_isVideoOff;
      }
    }

    WebSocketService.sendSignal('sfu_pause_producer', {
      'contact_id': '',
      'room_id': _currentRoomId,
      'producer_id': '${ApiService.username}-video',
    });
  }

  static RTCVideoRenderer getOrCreateRenderer(String peerId) {
    if (!_remoteRenderers.containsKey(peerId)) {
      final renderer = RTCVideoRenderer();
      renderer.initialize();
      _remoteRenderers[peerId] = renderer;
    }
    return _remoteRenderers[peerId]!;
  }

  static void updateRendererSource(String peerId, MediaStream stream) {
    final renderer = _remoteRenderers[peerId];
    if (renderer != null) {
      renderer.srcObject = stream;
    }
  }

  static Future<void> leaveRoom() async {
    if (_currentRoomId != null) {
      WebSocketService.sendSignal('sfu_leave_room', {
        'contact_id': '',
        'room_id': _currentRoomId,
      });
    }

    _currentRoomId = null;

    if (_peerConnection != null) {
      await _peerConnection!.close();
      _peerConnection = null;
    }

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      _localStream = null;
    }

    for (final renderer in _remoteRenderers.values) {
      await renderer.dispose();
    }
    _remoteRenderers.clear();

    for (final stream in _remoteStreams.values) {
      await stream.dispose();
    }
    _remoteStreams.clear();

    for (final participant in _participants.values) {
      participant.stream?.dispose();
    }
    _participants.clear();

    _isMuted = false;
    _isVideoOff = false;

    _onDisconnectedController.add(null);
  }

  static void dispose() {
    leaveRoom();
    _onParticipantJoinedController.close();
    _onParticipantLeftController.close();
    _onStreamAddedController.close();
    _onStreamRemovedController.close();
    _onConnectedController.close();
    _onDisconnectedController.close();
    _onErrorController.close();
  }

  static MediaStream? getRemoteStream(String peerId) {
    return _remoteStreams[peerId];
  }

  static List<SFUParticipantInfo> get participantList {
    return _participants.values.toList();
  }
}
