import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../data/api_service.dart';
import '../../data/auth_state.dart';
import '../../data/contacts_service.dart';
import '../../data/sfu_service.dart';
import '../../data/webrtc_service.dart';
import '../../models/call.dart';

class CallScreen extends StatefulWidget {
  final String contactId;
  final String contactName;
  final String? contactAvatar;
  final CallType callType;
  final bool isIncoming;
  final bool autoAccept;
  final bool useSFU;
  final String? roomId;

  const CallScreen({
    super.key,
    required this.contactId,
    required this.contactName,
    this.contactAvatar,
    this.callType = CallType.voice,
    this.isIncoming = false,
    this.autoAccept = false,
    this.useSFU = false,
    this.roomId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  int _elapsed = 0;
  Timer? _timer;
  bool _connecting = true;
  bool _connected = false;
  bool _muted = false;
  bool _speaker = false;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _callEnded = false;
  Set<String> _participantIds = {};
  bool _isGroupCall = false;
  Map<String, String> _participantNames = {};

  late AnimationController _pulseAnim;
  late AnimationController _slideAnim;
  late AnimationController _waveAnim;

  Timer? _connectTimer;
  String? _errMsg;

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _slideAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _waveAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _initRenderers()
        .then((_) {
          if (widget.isIncoming) {
            setState(() => _connecting = false);
            if (widget.autoAccept) {
              _acceptCall().catchError((Object e) {
                if (mounted) {
                  _errMsg = e.toString();
                  _endCall();
                }
              });
            }
          } else {
            _startCall().catchError((Object e) {
              if (mounted) {
                _errMsg = e.toString();
                _endCall();
              }
            });
          }
        })
        .catchError((_) {});
    _slideAnim.forward();
    _connectTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _connecting && !_callEnded) {
        _errMsg = 'Connection timed out';
        _endCall();
      }
    });
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  void _onParticipantAdded(String userId) {
    if (mounted) {
      setState(() {
        _participantIds = WebRTCService.participantIds;
        _isGroupCall = WebRTCService.isGroupCall;
        _participantNames = WebRTCService.conferenceParticipantNames;
        if (_remoteStream == null || _isGroupCall) {
          for (final p in WebRTCService.participants) {
            if (p.stream != null) {
              _remoteStream = p.stream;
              _remoteRenderer.srcObject = p.stream;
              break;
            }
          }
        }
        if (_localStream == null) {
          _localStream = WebRTCService.localStream;
          if (_localStream != null) {
            _localRenderer.srcObject = _localStream;
          }
        }
        if (!_connected && _remoteStream != null) {
          _connecting = false;
          _connected = true;
          _connectTimer?.cancel();
          _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() => _elapsed++);
          });
        }
      });
    }
  }

  void _onParticipantRemoved(String userId) {
    if (mounted) {
      setState(() {
        _participantIds = WebRTCService.participantIds;
        _isGroupCall = WebRTCService.isGroupCall;
        _participantNames = WebRTCService.conferenceParticipantNames;
        if (_remoteStream != null) {
          final found = WebRTCService.participants
              .where((p) => p.stream != null)
              .firstOrNull;
          if (found != null) {
            _remoteStream = found.stream;
            _remoteRenderer.srcObject = found.stream;
          } else {
            _remoteStream = null;
            _remoteRenderer.srcObject = null;
          }
        }
      });
    }
  }

  void _onRemoteStreamArrived(MediaStream stream) async {
    if (mounted) {
      await WebRTCService.initAudio();
      for (final track in stream.getAudioTracks()) {
        track.enabled = true;
      }
      setState(() {
        if (_remoteStream == null) {
          _remoteStream = stream;
          _remoteRenderer.srcObject = stream;
        } else if (_isGroupCall) {
          for (final p in WebRTCService.participants) {
            if (p.stream != null && p.stream != _remoteStream) {
              _remoteRenderer.srcObject = p.stream;
              _remoteStream = p.stream;
              break;
            }
          }
        }
        _connecting = false;
        _connected = true;
        _connectTimer?.cancel();
        _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _elapsed++);
        });
      });
    }
  }

  Future<void> _startCall() async {
    if (widget.useSFU) {
      await _startSFUCall();
      return;
    }
    if (WebRTCService.isGroupCall) {
      WebRTCService.setDisconnectHandler(() {
        if (mounted && !_callEnded) _endCall();
      });
      if (mounted) {
        _localStream = WebRTCService.localStream;
        _localRenderer.srcObject = _localStream;
      }
      _onParticipantAdded('');
      return;
    }
    await WebRTCService.startCall(
      contactId: widget.contactId,
      callerName: AuthState.instance.displayName ?? 'Unknown',
      video: widget.callType == CallType.video,
      onRemoteStream: _onRemoteStreamArrived,
      onDisconnect: () {
        if (mounted && !_callEnded && !WebRTCService.isGroupCall) _endCall();
      },
      onParticipantAdded: _onParticipantAdded,
      onParticipantRemoved: _onParticipantRemoved,
    );
    if (mounted) {
      _localStream = WebRTCService.localStream;
      _localRenderer.srcObject = _localStream;
    }
  }

  Future<void> _acceptCall() async {
    if (widget.useSFU) {
      await _acceptSFUCall();
      return;
    }
    if (WebRTCService.isGroupCall) {
      WebRTCService.setDisconnectHandler(() {
        if (mounted && !_callEnded) _endCall();
      });
      if (mounted) {
        _localStream = WebRTCService.localStream;
        _localRenderer.srcObject = _localStream;
      }
      _onParticipantAdded('');
      return;
    }
    setState(() => _connecting = true);
    await WebRTCService.acceptIncomingCall(
      onRemoteStream: _onRemoteStreamArrived,
      onDisconnect: () {
        if (mounted && !_callEnded && !WebRTCService.isGroupCall) _endCall();
      },
      onParticipantAdded: _onParticipantAdded,
      onParticipantRemoved: _onParticipantRemoved,
    );
    if (mounted) {
      _localStream = WebRTCService.localStream;
      _localRenderer.srcObject = _localStream;
    }
  }

  Future<void> _startSFUCall() async {
    await SFUService.initialize();
    final roomId = widget.roomId ?? 'room-${widget.contactId}';

    SFUService.onParticipantJoined.listen((participant) {
      if (mounted) {
        setState(() {
          _participantIds = SFUService.participants.keys.toSet();
          _participantNames = {
            for (var p in SFUService.participants.values)
              p.userId: p.displayName,
          };
          _isGroupCall = true;
        });
      }
    });

    SFUService.onParticipantLeft.listen((userId) {
      if (mounted) {
        setState(() {
          _participantIds = SFUService.participants.keys.toSet();
          _participantNames = {
            for (var p in SFUService.participants.values)
              p.userId: p.displayName,
          };
        });
      }
    });

    SFUService.onStreamAdded.listen((entry) {
      if (mounted) {
        final renderer = SFUService.getOrCreateRenderer(entry.key);
        renderer.srcObject = entry.value;
        setState(() {
          _remoteStream = entry.value;
          _remoteRenderer.srcObject = entry.value;
          _connecting = false;
          _connected = true;
          _connectTimer?.cancel();
          _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() => _elapsed++);
          });
        });
      }
    });

    SFUService.onDisconnected.listen((_) {
      if (mounted && !_callEnded) _endCall();
    });

    SFUService.onConnected.listen((_) {
      if (mounted && _connecting) {
        setState(() {
          _connecting = false;
          _connected = true;
          _connectTimer?.cancel();
          _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() => _elapsed++);
          });
        });
      }
    });

    SFUService.onError.listen((message) {
      if (mounted) {
        _errMsg = message;
        _endCall();
      }
    });

    await SFUService.joinRoom(
      roomId: roomId,
      video: widget.callType == CallType.video,
    );
    _localStream = SFUService.localStream;
    if (_localStream != null) {
      _localRenderer.srcObject = _localStream;
    }
  }

  Future<void> _acceptSFUCall() async {
    setState(() => _connecting = true);
    await _startSFUCall();
  }

  Future<void> _endCall() async {
    if (_callEnded) return;
    _callEnded = true;
    _connectTimer?.cancel();
    _timer?.cancel();
    final errMsg = _errMsg;

    if (widget.useSFU) {
      await SFUService.leaveRoom();
    } else {
      await WebRTCService.endCall();
    }

    final secs = _elapsed;
    if (secs > 0) {
      ApiService.saveCall(
        contactId: widget.contactId,
        type: widget.callType.name,
        status: 'answered',
        durationSeconds: secs,
      );
    }
    if (mounted) {
      if (errMsg != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errMsg), duration: const Duration(seconds: 3)),
        );
      }
      Navigator.pop(context);
    }
  }

  Future<void> _declineCall() async {
    await _endCall();
  }

  Future<void> _showAddPeopleSheet() async {
    if (NajiContactsService.cachedContacts.isEmpty) {
      await NajiContactsService.fetchAndCheck();
    }

    final contacts = NajiContactsService.cachedContacts
        .where(
          (c) =>
              c.isOnNajiMe &&
              c.najiMeUserId != null &&
              c.najiMeUserId != widget.contactId &&
              !_participantIds.contains(c.najiMeUserId),
        )
        .toList();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Add People',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            if (contacts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 48,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No contacts available',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Only NajiMe users can be added',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: contacts.length,
                  itemBuilder: (context, index) {
                    final contact = contacts[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text(
                          contact.name.isNotEmpty
                              ? contact.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(contact.name),
                      subtitle: contact.najiMeUsername != null
                          ? Text('@${contact.najiMeUsername}')
                          : null,
                      trailing: IconButton(
                        icon: Icon(
                          Icons.person_add_alt_1,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          WebRTCService.addParticipant(
                            contactId: contact.najiMeUserId!,
                            displayName: contact.name,
                            video: widget.callType == CallType.video,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _connectTimer?.cancel();
    _timer?.cancel();
    _pulseAnim.dispose();
    _slideAnim.dispose();
    _waveAnim.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  String get _formatted {
    final m = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsed % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _statusText {
    if (_isGroupCall) {
      final count = _participantIds.length + 1;
      if (_connecting) return 'Connecting...';
      return '$count participants';
    }
    if (_connecting) return 'Connecting...';
    if (_connected) return _formatted;
    return 'Incoming...';
  }

  Widget _buildAvatar() {
    final hasAvatar =
        widget.contactAvatar != null && widget.contactAvatar!.isNotEmpty;
    Widget? avatarImage;

    if (hasAvatar) {
      if (widget.contactAvatar!.startsWith('data:image')) {
        try {
          final base64Data = widget.contactAvatar!.split(',').last;
          final bytes = base64.decode(base64Data);
          avatarImage = ClipOval(
            child: Image.memory(
              bytes,
              width: 120,
              height: 120,
              fit: BoxFit.cover,
            ),
          );
        } catch (_) {}
      } else {
        avatarImage = ClipOval(
          child: Image.network(
            widget.contactAvatar!,
            width: 120,
            height: 120,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        );
      }
    }

    final initials = widget.contactName.isNotEmpty
        ? widget.contactName[0].toUpperCase()
        : '?';

    return Stack(
      alignment: Alignment.center,
      children: [
        if (!_connected && !_callEnded)
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) {
              final scale = 1.0 + _pulseAnim.value * 0.12;
              return Container(
                width: 140 * scale,
                height: 140 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.callType == CallType.video
                      ? Colors.blue.withValues(
                          alpha: 0.15 - _pulseAnim.value * 0.1,
                        )
                      : Colors.green.withValues(
                          alpha: 0.15 - _pulseAnim.value * 0.1,
                        ),
                ),
              );
            },
          ),
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: avatarImage != null ? null : Colors.transparent,
            gradient: avatarImage != null
                ? null
                : LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.3),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child:
              avatarImage ??
              Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildParticipantChips() {
    if (_participantIds.isEmpty && !_isGroupCall)
      return const SizedBox.shrink();

    final names = _participantNames.entries.toList();
    final count = names.length + 1;

    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.group,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '$count participants',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          for (final entry in names)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person, size: 14, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(
                      entry.value,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatus() {
    return Text(
      _statusText,
      style: TextStyle(
        color: Colors.white.withValues(alpha: _connected ? 0.9 : 0.6),
        fontSize: _connected && !_isGroupCall ? 40 : 16,
        fontWeight: _connected && !_isGroupCall
            ? FontWeight.w300
            : FontWeight.w400,
        letterSpacing: _connected && !_isGroupCall ? 2 : 0,
      ),
    );
  }

  Widget _buildWaveAnimation() {
    if (widget.callType == CallType.video) return const SizedBox.shrink();
    if (!_connected) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: AnimatedBuilder(
        animation: _waveAnim,
        builder: (context, child) {
          return CustomPaint(
            size: const Size(double.infinity, 40),
            painter: _WavePainter(
              value: _waveAnim.value,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.4),
              muted: _muted,
            ),
          );
        },
      ),
    );
  }

  Widget _buildGlassButton({
    required IconData icon,
    required String label,
    Color? color,
    double size = 56,
    double iconSize = 26,
    required VoidCallback onPressed,
  }) {
    final effectiveColor = color ?? Colors.white;
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: effectiveColor.withValues(alpha: 0.2),
              border: Border.all(
                color: effectiveColor.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
            child: Icon(icon, color: effectiveColor, size: iconSize),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callType == CallType.video;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFF0D1B2A), const Color(0xFF000000)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Spacer(),
                      if (_connected)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isGroupCall
                                    ? Icons.group
                                    : (widget.callType == CallType.video
                                          ? Icons.videocam
                                          : Icons.phone),
                                size: 14,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isGroupCall
                                    ? 'Group Call'
                                    : (widget.callType == CallType.video
                                          ? 'Video Call'
                                          : 'Voice Call'),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Spacer(),
                    ],
                  ),
                  const Spacer(flex: 2),
                  if (isVideo && _remoteStream != null) ...[
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: RTCVideoView(_remoteRenderer, mirror: false),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else if (isVideo) ...[
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.videocam,
                                size: 56,
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Camera not available',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    _buildAvatar(),
                    const SizedBox(height: 24),
                    Text(
                      _isGroupCall ? _statusText : widget.contactName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: _isGroupCall ? 18 : 28,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    if (!_isGroupCall) ...[
                      const SizedBox(height: 12),
                      _buildStatus(),
                      const SizedBox(height: 20),
                      _buildWaveAnimation(),
                    ],
                    if (_isGroupCall) ...[
                      const SizedBox(height: 8),
                      _buildParticipantChips(),
                    ],
                  ],
                  if (isVideo || _isGroupCall) _buildParticipantChips(),
                  const Spacer(flex: 2),
                  if (widget.isIncoming && !_connected && !widget.autoAccept)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildGlassButton(
                            icon: Icons.call_end,
                            label: 'Decline',
                            color: Colors.red,
                            size: 72,
                            iconSize: 36,
                            onPressed: _declineCall,
                          ),
                          const SizedBox(width: 64),
                          _buildGlassButton(
                            icon: Icons.call,
                            label: 'Accept',
                            color: Colors.green,
                            size: 72,
                            iconSize: 36,
                            onPressed: _acceptCall,
                          ),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_connected) ...[
                            _buildGlassButton(
                              icon: _muted ? Icons.mic_off : Icons.mic,
                              label: _muted ? 'Unmute' : 'Mute',
                              color: _muted ? Colors.amber : Colors.white,
                              onPressed: () {
                                _localStream?.getAudioTracks().forEach((t) {
                                  t.enabled = _muted;
                                });
                                setState(() => _muted = !_muted);
                              },
                            ),
                            const SizedBox(width: 24),
                            _buildGlassButton(
                              icon: Icons.person_add_alt_1,
                              label: 'Add',
                              color: cs.primary,
                              onPressed: _showAddPeopleSheet,
                            ),
                            const SizedBox(width: 24),
                          ],
                          _buildGlassButton(
                            icon: Icons.call_end,
                            label: 'End',
                            color: Colors.red,
                            size: 72,
                            iconSize: 36,
                            onPressed: _endCall,
                          ),
                          if (_connected) ...[
                            const SizedBox(width: 24),
                            _buildGlassButton(
                              icon: _speaker
                                  ? Icons.volume_up
                                  : Icons.volume_up_outlined,
                              label: 'Speaker',
                              color: _speaker ? cs.primary : Colors.white,
                              onPressed: () {
                                setState(() => _speaker = !_speaker);
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
              if (isVideo && _localStream != null)
                Positioned(
                  right: 16,
                  top: 16,
                  child: AnimatedBuilder(
                    animation: _slideAnim,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, (1 - _slideAnim.value) * -100),
                        child: child,
                      );
                    },
                    child: Container(
                      width: 100,
                      height: 160,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: RTCVideoView(_localRenderer, mirror: true),
                      ),
                    ),
                  ),
                ),
              if (!isVideo && _remoteStream != null)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Visibility(
                    visible: false,
                    maintainState: true,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainInteractivity: true,
                    child: SizedBox(
                      width: 1,
                      height: 1,
                      child: RTCVideoView(_remoteRenderer, mirror: false),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double value;
  final Color color;
  final bool muted;

  _WavePainter({required this.value, required this.color, required this.muted});

  @override
  void paint(Canvas canvas, Size size) {
    if (muted) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final halfH = size.height / 2;
    final w = size.width;

    for (double x = 0; x < w; x += 1) {
      final freq = (x / w) * math.pi * 4;
      final amp = math.sin(value * math.pi * 2 + x / 30) * 8 + 10;
      final y = halfH + math.sin(freq + value * math.pi * 2) * amp;
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.value != value;
}
