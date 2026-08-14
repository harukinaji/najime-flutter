import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/auth_state.dart';
import '../../data/p2p_room_service.dart';
import '../../theme/app_colors.dart';

class P2PRoomScreen extends StatefulWidget {
  const P2PRoomScreen({super.key, this.joinRoomId});

  final String? joinRoomId;

  @override
  State<P2PRoomScreen> createState() => _P2PRoomScreenState();
}

class _ChatEntry {
  final String text;
  final String? from;
  final bool mine;
  final bool system;
  _ChatEntry(this.text, {this.from, this.mine = false, this.system = false});
}

class _P2PRoomScreenState extends State<P2PRoomScreen> {
  final P2PRoomService _svc = P2PRoomService.instance;
  final TextEditingController _roomCtrl = TextEditingController();
  final TextEditingController _draftCtrl = TextEditingController();
  final List<_ChatEntry> _chat = [];
  final ScrollController _scroll = ScrollController();
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _svc.onChanged = _refresh;
    _svc.onEvent = _onEvent;
    if (widget.joinRoomId != null && widget.joinRoomId!.isNotEmpty) {
      _roomCtrl.text = widget.joinRoomId!;
      _join();
    }
  }

  @override
  void dispose() {
    _svc.onChanged = null;
    _svc.onEvent = null;
    _roomCtrl.dispose();
    _draftCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onEvent(String from, String eventName, Map<String, dynamic> payload) {
    if (eventName == 'p2p_chat') {
      _append(_ChatEntry(payload['text'] as String? ?? '', from: from));
    } else if (eventName == 'p2p_joined') {
      _append(_ChatEntry('${payload['name'] ?? from} joined', system: true));
    }
  }

  void _append(_ChatEntry entry) {
    if (!mounted) return;
    setState(() => _chat.add(entry));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Creating room...';
    });
    await _svc.createRoom(maxPlayers: 8);
    setState(() {
      _busy = false;
      _status = null;
    });
    _refresh();
    if (_svc.inRoom) {
      _svc.sendToPeers('p2p_joined', {'name': AuthState.instance.displayName});
    }
  }

  Future<void> _join() async {
    if (_busy) return;
    final roomId = _roomCtrl.text.trim();
    if (roomId.isEmpty) return;
    setState(() {
      _busy = true;
      _status = 'Joining room...';
    });
    await _svc.joinRoom(roomId);
    setState(() {
      _busy = false;
      _status = null;
    });
    _refresh();
    if (_svc.inRoom) {
      _append(_ChatEntry('Joined room', system: true));
    } else {
      _append(_ChatEntry('Room not found or full', system: true));
    }
  }

  Future<void> _leave() async {
    await _svc.leaveRoom();
    _chat.clear();
    _refresh();
  }

  void _send() {
    final text = _draftCtrl.text.trim();
    if (text.isEmpty || !_svc.inRoom) return;
    _draftCtrl.clear();
    _append(_ChatEntry(text, mine: true));
    _svc.sendToPeers('p2p_chat', {'text': text});
  }

  void _ping() {
    _svc.sendPing();
    _append(_ChatEntry('Ping sent to all peers', system: true));
  }

  void _copyRoomId() async {
    await Clipboard.setData(ClipboardData(text: _svc.roomId ?? ''));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Room code copied to clipboard')),
      );
    }
  }

  Future<void> _joinVoice() async {
    final ok = await _svc.joinVoice();
    if (mounted && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone unavailable')),
      );
    }
    _refresh();
  }

  Future<void> _leaveVoice() async {
    await _svc.leaveVoice();
    _refresh();
  }

  Future<void> _toggleMute() async {
    await _svc.setMuted(!_svc.voiceMuted);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inRoom = _svc.inRoom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('P2P Rooms'),
        actions: [
          if (inRoom)
            IconButton(
              tooltip: 'Leave room',
              icon: const Icon(Icons.exit_to_app),
              onPressed: _leave,
            ),
        ],
      ),
      body: inRoom ? _buildRoom(cs) : _buildLobby(cs),
    );
  }

  Widget _buildLobby(ColorScheme cs) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.hub_outlined, size: 56, color: AppColors.primary),
              const SizedBox(height: 12),
              Text(
                'Peer-to-peer multiplayer',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Rooms are created server-side for discovery, but all game '
                'data flows directly between peers over WebRTC DataChannels '
                '— just like PeerJS.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.add_box_outlined),
                label: Text(_busy ? _status ?? '...' : 'Create room'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _roomCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Room code',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _join(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Join',
                    onPressed: _busy ? null : _join,
                    icon: const Icon(Icons.login),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Your ID: ${AuthState.instance.username ?? '-'}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              if (_busy && _status != null) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoom(ColorScheme cs) {
    final state = _svc.multiplayerState;
    final peers = (state['peers'] as List).cast<Map<String, dynamic>>();

    return Column(
      children: [
        _roomHeader(cs, state, peers),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: _chat.length,
            itemBuilder: (context, i) => _chatBubble(cs, _chat[i]),
          ),
        ),
        _composer(cs),
      ],
    );
  }

  Widget _roomHeader(
    ColorScheme cs,
    Map<String, dynamic> state,
    List<Map<String, dynamic>> peers,
  ) {
    final connected =
        peers.where((p) => p['connected'] == true).length;

    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Room ${state['room_id']}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Copy room code',
                icon: const Icon(Icons.copy, size: 20),
                onPressed: _copyRoomId,
              ),
              IconButton(
                tooltip: 'Ping peers (latency)',
                icon: const Icon(Icons.wifi_tethering, size: 20),
                onPressed: _ping,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$connected/${peers.length + 1} connected',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _voiceBar(cs),
          const SizedBox(height: 8),
          if (peers.isEmpty)
            Text(
              'Waiting for players — share the room code above.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            )
          else
            SizedBox(
              height: 96,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: peers.length,
                itemBuilder: (context, i) => _peerCard(cs, peers[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _voiceBar(ColorScheme cs) {
    final inVoice = _svc.voiceActive;
    final muted = _svc.voiceMuted;
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: inVoice ? (muted ? 'Unmute' : 'Mute') : 'Join voice chat',
          onPressed: inVoice ? _toggleMute : _joinVoice,
          icon: Icon(
            inVoice
                ? (muted ? Icons.mic_off : Icons.mic)
                : Icons.mic_none,
            color: inVoice
                ? (muted ? cs.onSurfaceVariant : AppColors.success)
                : cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 4),
        if (inVoice) ...[
          IconButton.filledTonal(
            tooltip: 'Leave voice chat',
            onPressed: _leaveVoice,
            icon: const Icon(Icons.call_end),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              muted ? 'Microphone muted' : 'Speaking to the room',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ] else ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Join voice chat to talk with players',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _peerCard(ColorScheme cs, Map<String, dynamic> peer) {
    final connected = peer['connected'] == true;
    final latency = peer['latency_ms'];
    final inVoice = peer['in_voice'] == true;
    final muted = peer['muted'] == true;
    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: connected ? AppColors.success : cs.outlineVariant,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            connected ? Icons.wifi : Icons.wifi_off,
            color: connected ? AppColors.success : cs.onSurfaceVariant,
          ),
          const SizedBox(height: 6),
          Text(
            peer['id'].toString(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 4),
          Text(
            latency != null
                ? '${latency.round()} ms'
                : connected
                    ? 'connected'
                    : peer['state'].toString(),
            style: TextStyle(
              fontSize: 12,
              color: connected ? AppColors.success : cs.onSurfaceVariant,
            ),
          ),
          if (connected) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  inVoice
                      ? (muted ? Icons.mic_off : Icons.mic)
                      : Icons.mic_off,
                  size: 16,
                  color: inVoice
                      ? (muted ? cs.onSurfaceVariant : AppColors.success)
                      : cs.outlineVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  inVoice ? (muted ? 'muted' : 'talking') : 'no mic',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chatBubble(ColorScheme cs, _ChatEntry entry) {
    if (entry.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 24),
        child: Text(
          entry.text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      );
    }
    final mine = entry.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(
                entry.from ?? 'peer',
                style: TextStyle(
                  fontSize: 11,
                  color: mine ? Colors.white70 : AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            Text(
              entry.text,
              style: TextStyle(
                fontSize: 14,
                color: mine ? Colors.white : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(ColorScheme cs) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _draftCtrl,
                decoration: const InputDecoration(
                  hintText: 'Send a message to all peers...',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
