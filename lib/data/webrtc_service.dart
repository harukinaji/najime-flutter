import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../config.dart';
import 'api_service.dart';
import 'websocket_service.dart';

class TurnCredential {
  final String username;
  final String credential;
  TurnCredential({required this.username, required this.credential});
}

class IncomingCallData {
  final String contactId;
  final String contactName;
  final bool video;
  final bool isGroupCall;
  final String? conferenceId;
  final Map<String, String> participantNames;
  IncomingCallData({
    required this.contactId,
    required this.contactName,
    required this.video,
    this.isGroupCall = false,
    this.conferenceId,
    this.participantNames = const {},
  });
}

class ParticipantStream {
  final String userId;
  final String displayName;
  final MediaStream? stream;
  ParticipantStream({
    required this.userId,
    required this.displayName,
    this.stream,
  });
}

class WebRTCService {
  static MediaStream? _localStream;
  static bool _isCaller = false;
  static TurnCredential? _turnCredential;
  static void Function(IncomingCallData)? onIncomingCall;
  static Map<String, dynamic>? _pendingOffer;
  static String? _pendingContactId;
  static String? _pendingCallerId;

  static final Map<String, RTCPeerConnection> _peerConnections = {};
  static final Map<String, MediaStream> _remoteStreams = {};
  static final Map<String, String> _participantNames = {};
  static String? _mainContactId;
  static void Function()? _onDisconnect;
  static void Function(String userId)? _onParticipantAdded;
  static void Function(String userId)? _onParticipantRemoved;

  static bool _isGroupCall = false;
  static String? _conferenceId;
  static RTCPeerConnection? _conferencePc;
  static final Map<String, MediaStream> _conferenceRemoteStreams = {};
  static final Map<String, String> _conferenceParticipantNames = {};
  static int _conferenceStreamCounter = 0;

  static Future<void> initAudio() async {
    try {
      await Helper.setAndroidAudioConfiguration(
        AndroidAudioConfiguration.communication,
      );
    } catch (_) {}
    try {
      await Helper.ensureAudioSession();
    } catch (_) {}
    try {
      await Helper.setAppleAudioIOMode(
        AppleAudioIOMode.localAndRemote,
        preferSpeakerOutput: true,
      );
    } catch (_) {}
    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (_) {}
  }

  static List<Map<String, dynamic>> get iceServers {
    final servers = <Map<String, dynamic>>[
      {'urls': 'stun:${AppConfig.webrtcHost}:3478'},
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];
    if (_turnCredential != null) {
      servers.add({
        'urls': 'turn:${AppConfig.webrtcHost}:3478',
        'username': _turnCredential!.username,
        'credential': _turnCredential!.credential,
      });
    }
    return servers;
  }

  static List<ParticipantStream> get participants {
    final list = <ParticipantStream>[];
    for (final entry in _remoteStreams.entries) {
      list.add(
        ParticipantStream(
          userId: entry.key,
          displayName: _participantNames[entry.key] ?? entry.key,
          stream: entry.value,
        ),
      );
    }
    for (final entry in _conferenceRemoteStreams.entries) {
      list.add(
        ParticipantStream(
          userId: entry.key,
          displayName: _conferenceParticipantNames[entry.key] ?? entry.key,
          stream: entry.value,
        ),
      );
    }
    return list;
  }

  static Set<String> get participantIds {
    final ids = <String>{..._peerConnections.keys};
    ids.addAll(_conferenceParticipantNames.keys);
    ids.addAll(_conferenceRemoteStreams.keys);
    return ids;
  }

  static bool get isGroupCall => _isGroupCall;
  static int get conferenceParticipantCount =>
      _conferenceParticipantNames.length;
  static String? get conferenceId => _conferenceId;
  static Map<String, MediaStream> get conferenceRemoteStreams =>
      Map.unmodifiable(_conferenceRemoteStreams);
  static Map<String, String> get conferenceParticipantNames =>
      Map.unmodifiable(_conferenceParticipantNames);

  static Future<void> initTurn() async {
    final creds = await ApiService.fetchTurnCredentials();
    if (creds != null) {
      _turnCredential = TurnCredential(
        username: creds['username']!,
        credential: creds['credential']!,
      );
    } else {
      _turnCredential = null;
    }
  }

  static Future<MediaStream> _getLocalStream(bool video) async {
    return await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video,
    });
  }

  static Future<RTCPeerConnection> _createPeerConnection(
    String peerId, {
    required bool video,
    required void Function(MediaStream) onStream,
    void Function()? onDisconnect,
  }) async {
    final pc = await createPeerConnection({'iceServers': iceServers});

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        pc.addTrack(track, _localStream!);
      }
    }

    pc.onIceCandidate = (candidate) {
      WebSocketService.sendSignal('ice_candidate', {
        'contact_id': peerId,
        'participant_id': peerId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    pc.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        onDisconnect?.call();
      }
    };

    pc.onTrack = (event) {
      if (event.track.kind == 'audio' || event.track.kind == 'video') {
        _remoteStreams[peerId] = event.streams[0];
        onStream(event.streams[0]);
      }
    };

    return pc;
  }

  static Future<void> startCall({
    required String contactId,
    required String callerName,
    required bool video,
    required void Function(MediaStream) onRemoteStream,
    required void Function() onDisconnect,
    void Function(String userId)? onParticipantAdded,
    void Function(String userId)? onParticipantRemoved,
  }) async {
    await _cleanup();
    await initTurn();
    await initAudio();
    _isCaller = true;
    _mainContactId = contactId;
    _participantNames[contactId] = callerName;
    _onDisconnect = onDisconnect;
    _onParticipantAdded = onParticipantAdded;
    _onParticipantRemoved = onParticipantRemoved;

    _localStream = await _getLocalStream(video);

    final pc = await _createPeerConnection(
      contactId,
      video: video,
      onStream: (stream) {
        _remoteStreams[contactId] = stream;
        onRemoteStream(stream);
      },
      onDisconnect: onDisconnect,
    );
    _peerConnections[contactId] = pc;

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    if (!WebSocketService.sendSignal('offer', {
      'contact_id': contactId,
      'caller_name': callerName,
      'sdp': {'sdp': offer.sdp, 'type': offer.type},
      'video': video,
    })) {
      throw Exception('WebSocket not connected');
    }
  }

  static Future<void> _createConferencePc({required bool video}) async {
    if (_conferencePc != null) {
      await _conferencePc!.close();
      _conferencePc = null;
    }

    _conferencePc = await createPeerConnection({'iceServers': iceServers});

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        _conferencePc!.addTrack(track, _localStream!);
      }
    }

    _conferencePc!.onIceCandidate = (candidate) {
      if (_conferenceId == null) return;
      WebSocketService.sendSignal('conference_ice_candidate', {
        'conference_id': _conferenceId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    _conferencePc!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _onDisconnect?.call();
      }
    };

    _conferencePc!.onTrack = (event) {
      final stream = event.streams[0];
      String? userId;
      for (final uid in _conferenceParticipantNames.keys) {
        if (!_conferenceRemoteStreams.containsKey(uid)) {
          userId = uid;
          break;
        }
      }
      userId ??= 'p${_conferenceStreamCounter++}';
      _conferenceRemoteStreams[userId!] = stream;
      _onParticipantAdded?.call(userId);
    };
  }

  static Future<void> handleInvitedToConference(
    Map<String, dynamic> data,
  ) async {
    final conferenceId = data['conference_id'] as String;
    final video = data['video'] as bool? ?? false;
    final hostId = data['host_id'] as String?;
    final participantNames =
        (data['participant_names'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as String),
        ) ??
        <String, String>{};

    await _cleanup();
    await initAudio();

    _isGroupCall = true;
    _conferenceId = conferenceId;
    _isCaller = false;

    if (hostId != null) {
      _conferenceParticipantNames[hostId] = participantNames[hostId] ?? hostId;
    }
    _conferenceParticipantNames.addAll(participantNames);

    _localStream = await _getLocalStream(video);

    await _createConferencePc(video: video);

    WebSocketService.sendSignal('join_conference', {
      'conference_id': conferenceId,
    });

    final hostName = participantNames[hostId] ?? hostId ?? 'Unknown';
    onIncomingCall?.call(
      IncomingCallData(
        contactId: hostId ?? '',
        contactName: hostName,
        video: video,
        isGroupCall: true,
        conferenceId: conferenceId,
        participantNames: participantNames,
      ),
    );
  }

  static Future<void> handleConferenceCreated(Map<String, dynamic> data) async {
    _conferenceId = data['conference_id'] as String;
    final video = data['video'] as bool? ?? false;

    for (final pc in _peerConnections.values) {
      await pc.close();
    }
    _peerConnections.clear();
    _remoteStreams.clear();

    await _createConferencePc(video: video);

    WebSocketService.sendSignal('join_conference', {
      'conference_id': _conferenceId,
    });
  }

  static Future<void> handleConferenceOffer(Map<String, dynamic> data) async {
    if (_conferencePc == null) return;
    final sdp = RTCSessionDescription(
      data['sdp']['sdp'] as String,
      data['sdp']['type'] as String,
    );
    await _conferencePc!.setRemoteDescription(sdp);
    final answer = await _conferencePc!.createAnswer();
    await _conferencePc!.setLocalDescription(answer);
    WebSocketService.sendSignal('conference_answer', {
      'conference_id': _conferenceId,
      'sdp': {'sdp': answer.sdp, 'type': answer.type},
    });
  }

  static Future<void> handleConferenceIceCandidate(
    Map<String, dynamic> data,
  ) async {
    if (_conferencePc == null) return;
    final c = data['candidate'] as Map<String, dynamic>;
    await _conferencePc!.addCandidate(
      RTCIceCandidate(
        c['candidate'] as String,
        c['sdpMid'] as String?,
        (c['sdpMLineIndex'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  static void handleConferenceUserJoined(Map<String, dynamic> data) {
    final userId = data['user_id'] as String;
    final displayName = data['display_name'] as String? ?? userId;
    _conferenceParticipantNames[userId] = displayName;
    _onParticipantAdded?.call(userId);
  }

  static void handleConferenceUserLeft(Map<String, dynamic> data) {
    final userId = data['user_id'] as String;
    _conferenceRemoteStreams.remove(userId);
    _conferenceParticipantNames.remove(userId);
    _onParticipantRemoved?.call(userId);
    if (_conferenceParticipantNames.isEmpty) {
      _onDisconnect?.call();
      _cleanup();
    }
  }

  static Future<void> addParticipant({
    required String contactId,
    required String displayName,
    required bool video,
  }) async {
    if (_isGroupCall) {
      _conferenceParticipantNames[contactId] = displayName;
      WebSocketService.sendSignal('invite_to_conference', {
        'conference_id': _conferenceId,
        'user_id': contactId,
        'display_name': displayName,
        'video': video,
      });
      _onParticipantAdded?.call(contactId);
      return;
    }

    if (_peerConnections.containsKey(contactId)) return;

    _participantNames[contactId] = displayName;

    if (_peerConnections.length >= 1) {
      return;
    }

    final pc = await _createPeerConnection(
      contactId,
      video: video,
      onStream: (stream) {
        _remoteStreams[contactId] = stream;
        _onParticipantAdded?.call(contactId);
      },
      onDisconnect: () {
        removeParticipant(contactId);
      },
    );
    _peerConnections[contactId] = pc;

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    WebSocketService.sendSignal('offer', {
      'contact_id': contactId,
      'caller_name': _participantNames[_mainContactId] ?? 'Unknown',
      'sdp': {'sdp': offer.sdp, 'type': offer.type},
      'video': video,
    });
  }

  static Future<void> handleOffer(Map<String, dynamic> data) async {
    if (data['is_group_call'] == true) {
      await handleInvitedToConference(data);
      return;
    }
    await _cleanup();
    _pendingOffer = data;
    _pendingContactId = data['contact_id'] as String?;
    _pendingCallerId = data['caller_id'] as String?;
    onIncomingCall?.call(
      IncomingCallData(
        contactId: _pendingContactId ?? '',
        contactName:
            (data['caller_name'] as String?) ?? _pendingContactId ?? 'Unknown',
        video: data['video'] as bool? ?? false,
      ),
    );
  }

  static Future<void> acceptIncomingCall({
    required void Function(MediaStream) onRemoteStream,
    required void Function() onDisconnect,
    void Function(String userId)? onParticipantAdded,
    void Function(String userId)? onParticipantRemoved,
  }) async {
    if (_pendingOffer == null) return;
    final savedOffer = _pendingOffer!;
    final savedCallerId = _pendingCallerId;
    final savedMyId = _pendingContactId;

    await _cleanup();
    await initAudio();

    _onDisconnect = onDisconnect;
    _onParticipantAdded = onParticipantAdded;
    _onParticipantRemoved = onParticipantRemoved;
    _isCaller = false;

    final data = savedOffer;
    final callerId = savedCallerId ?? data['contact_id'] as String;
    _mainContactId = callerId;

    _localStream = await _getLocalStream(data['video'] as bool? ?? false);

    final pc = await _createPeerConnection(
      callerId,
      video: data['video'] as bool? ?? false,
      onStream: (stream) {
        _remoteStreams[callerId] = stream;
        onRemoteStream(stream);
      },
      onDisconnect: onDisconnect,
    );
    _peerConnections[callerId] = pc;

    final sdp = RTCSessionDescription(
      data['sdp']['sdp'] as String,
      data['sdp']['type'] as String,
    );
    await pc.setRemoteDescription(sdp);
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    if (!WebSocketService.sendSignal('answer', {
      'contact_id': callerId,
      'participant_id': savedMyId ?? callerId,
      'sdp': {'sdp': answer.sdp, 'type': answer.type},
    })) {
      throw Exception('WebSocket not connected');
    }
  }

  static Future<void> declineIncomingCall() async {
    if (_pendingCallerId != null) {
      WebSocketService.sendSignal('call_end', {'contact_id': _pendingCallerId});
    }
    _pendingOffer = null;
    _pendingContactId = null;
    _pendingCallerId = null;
    await _cleanup();
  }

  static Future<void> handleAnswer(Map<String, dynamic> data) async {
    final pid =
        data['participant_id'] as String? ?? data['contact_id'] as String?;
    final pc = pid != null ? _peerConnections[pid] : null;
    if (pc == null) return;
    final sdp = RTCSessionDescription(
      data['sdp']['sdp'] as String,
      data['sdp']['type'] as String,
    );
    await pc.setRemoteDescription(sdp);
  }

  static Future<void> handleIceCandidate(Map<String, dynamic> data) async {
    final pid =
        data['sender_id'] as String? ??
        data['participant_id'] as String? ??
        data['contact_id'] as String?;
    final pc = pid != null ? _peerConnections[pid] : null;
    if (pc == null) return;
    final c = data['candidate'] as Map<String, dynamic>;
    await pc.addCandidate(
      RTCIceCandidate(
        c['candidate'] as String,
        c['sdpMid'] as String?,
        (c['sdpMLineIndex'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  static Future<void> endCall() async {
    if (_isGroupCall && _conferenceId != null) {
      WebSocketService.sendSignal('leave_conference', {
        'conference_id': _conferenceId,
      });
    } else {
      for (final pid in _peerConnections.keys) {
        WebSocketService.sendSignal('call_end', {'contact_id': pid});
      }
    }
    _onDisconnect?.call();
    await _cleanup();
  }

  static void removeParticipant(String userId) {
    if (_isGroupCall) {
      _conferenceRemoteStreams.remove(userId);
      _conferenceParticipantNames.remove(userId);
      _onParticipantRemoved?.call(userId);
      return;
    }
    WebSocketService.sendSignal('call_end', {'contact_id': userId});
    final pc = _peerConnections.remove(userId);
    if (pc != null) {
      pc.close();
    }
    _remoteStreams.remove(userId);
    _participantNames.remove(userId);
    _onParticipantRemoved?.call(userId);
  }

  static Future<void> _cleanup() async {
    _onDisconnect = null;
    _mainContactId = null;
    _isCaller = false;
    _pendingOffer = null;
    _pendingContactId = null;
    _pendingCallerId = null;
    _onParticipantAdded = null;
    _onParticipantRemoved = null;

    _isGroupCall = false;
    _conferenceId = null;
    _conferenceStreamCounter = 0;

    if (_conferencePc != null) {
      await _conferencePc!.close();
      _conferencePc = null;
    }
    _conferenceRemoteStreams.clear();
    _conferenceParticipantNames.clear();

    for (final pc in _peerConnections.values) {
      await pc.close();
    }
    _peerConnections.clear();
    _remoteStreams.clear();
    _participantNames.clear();

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      _localStream = null;
    }
  }

  static Future<void> handleRemoteEnd([Map<String, dynamic>? data]) async {
    if (_isGroupCall) {
      await _cleanup();
      _onDisconnect?.call();
      return;
    }
    final pid = data != null ? data['contact_id'] as String? : null;
    if (pid != null && _peerConnections.containsKey(pid)) {
      removeParticipant(pid);
      if (_peerConnections.isEmpty) {
        _onDisconnect?.call();
        await _cleanup();
      }
      return;
    }
    await _cleanup();
    _onDisconnect?.call();
  }

  static Future<void> handleAccept({
    required void Function(MediaStream) onRemoteStream,
    required void Function() onDisconnect,
  }) async {
    _onDisconnect = onDisconnect;
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
    }
    final anyPc = _peerConnections.values.firstOrNull;
    final transceivers = await anyPc?.getTransceivers() ?? [];
    _localStream = await _getLocalStream(
      transceivers.any((t) => t.receiver.track?.kind == 'video'),
    );
  }

  static MediaStream? get localStream => _localStream;
  static bool get isCaller => _isCaller;

  static void setDisconnectHandler(void Function() handler) {
    _onDisconnect = handler;
  }

  static void handleConferenceError(String message) {
    if (_isGroupCall && _conferenceId == 'pending') {
      _isGroupCall = false;
      _conferenceId = null;
      _conferenceParticipantNames.clear();
      _conferenceRemoteStreams.clear();
      _conferenceStreamCounter = 0;
      if (_conferencePc != null) {
        _conferencePc!.close();
        _conferencePc = null;
      }
      return;
    }
    _onDisconnect?.call();
    _cleanup();
  }
}
