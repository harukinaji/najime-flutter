import "dart:async";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "../../data/p2p_room_service.dart";
class CemuGamepadScreen extends StatefulWidget {
  const CemuGamepadScreen({super.key, this.joinRoomId});
  final String? joinRoomId;
  @override
  State<CemuGamepadScreen> createState() => _CemuGamepadScreenState();
}
class _CemuGamepadScreenState extends State<CemuGamepadScreen> {
  final P2PRoomService _svc = P2PRoomService.instance;
  final TextEditingController _roomCtrl = TextEditingController();
  RTCVideoRenderer _renderer = RTCVideoRenderer();
  MediaStream? _remoteStream;
  String? _cemuPeerId;
  bool _busy = false;
  String? _status;
  Timer? _inputTimer;
  bool _rendererReady = false;
  final Map<String, bool> _buttons = {
    "a": false, "b": false, "x": false, "y": false,
    "l": false, "r": false, "zl": false, "zr": false,
    "plus": false, "minus": false, "home": false, "sync": false,
    "dpad_up": false, "dpad_down": false, "dpad_left": false, "dpad_right": false,
  };
  double _lx = 0, _ly = 0, _rx = 0, _ry = 0;
  double _touchX = 0.5, _touchY = 0.5;
  bool _touchDown = false;
  @override
  void initState() {
    super.initState();
    _renderer.initialize().then((_) { if (mounted) setState(() => _rendererReady = true); });
    _svc.onChanged = _refresh;
    _svc.onRemoteVideo = _onRemoteVideo;
    _svc.onRemoteVideoEnded = _onRemoteVideoEnded;
    _svc.onEvent = _onP2PEvent;
    if (widget.joinRoomId != null && widget.joinRoomId!.isNotEmpty) {
      _roomCtrl.text = widget.joinRoomId!;
      _join();
    }
  }
  @override
  void dispose() {
    _inputTimer?.cancel();
    _svc.onChanged = null;
    _svc.onRemoteVideo = null;
    _svc.onRemoteVideoEnded = null;
    _svc.onEvent = null;
    _renderer.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }
  void _refresh() { if (mounted) setState(() {}); }
  void _onP2PEvent(String from, String eventName, Map<String, dynamic> payload) {}
  void _onRemoteVideo(String peerId, MediaStream stream) {
    if (!mounted) return;
    setState(() { _remoteStream = stream; _cemuPeerId = peerId; _renderer.srcObject = stream; });
    _svc.notifyCemuRole();
    _startInputLoop();
  }
  void _onRemoteVideoEnded(String peerId) {
    if (_cemuPeerId != peerId) return;
    setState(() { _renderer.srcObject = null; _remoteStream = null; _cemuPeerId = null; });
    _inputTimer?.cancel();
  }
  void _startInputLoop() {
    _inputTimer?.cancel();
    _inputTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_svc.inRoom) return;
      _svc.sendCemuInput({
        "type": "frame",
        "buttons": Map<String, bool>.from(_buttons),
        "lx": _lx, "ly": _ly, "rx": _rx, "ry": _ry,
        "touch": {"x": _touchX, "y": _touchY, "down": _touchDown},
        "ts": DateTime.now().millisecondsSinceEpoch,
      }, toPeer: _cemuPeerId);
    });
  }
  Future<void> _create() async {
    if (_busy) return;
    setState(() { _busy = true; _status = "Creating room..."; });
    _svc.setCemuMode(true);
    await _svc.createRoom(maxPlayers: 8);
    setState(() { _busy = false; _status = null; });
    _refresh();
  }
  Future<void> _join() async {
    if (_busy) return;
    final id = _roomCtrl.text.trim();
    if (id.isEmpty) return;
    setState(() { _busy = true; _status = "Joining..."; });
    _svc.setCemuMode(true);
    await _svc.joinRoom(id);
    setState(() { _busy = false; _status = null; });
    if (_svc.inRoom) {
      _svc.notifyCemuRole();
      for (final pid in _svc.cemuPeers) {
        final s = _svc.getCemuStream(pid);
        if (s != null) _onRemoteVideo(pid, s);
      }
      _startInputLoop();
    }
    _refresh();
  }
  Future<void> _leave() async {
    _inputTimer?.cancel();
    await _svc.leaveRoom();
    setState(() { _renderer.srcObject = null; _remoteStream = null; _cemuPeerId = null; });
    _refresh();
  }
  void _handleTouch(Offset localPos, Size size, bool down) {
    final x = (localPos.dx / size.width).clamp(0.0, 1.0);
    final y = (localPos.dy / size.height).clamp(0.0, 1.0);
    setState(() { _touchX = x; _touchY = y; _touchDown = down; });
    _svc.sendCemuTouch(x: x, y: y, down: down);
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
              const Icon(Icons.videogame_asset, size: 56),
              const SizedBox(height: 12),
              Text("Cemu -> Vanilla GamePad", textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text("Run Cemu и bridge на ПК, создай комнату. Видео геймпада придет сюда, тачи и кнопки улетят в Cemu.", textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 24),
              FilledButton.icon(onPressed: _busy ? null : _create, icon: const Icon(Icons.add), label: Text(_busy ? (_status ?? "...") : "Создать комнату")),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: TextField(controller: _roomCtrl, decoration: const InputDecoration(hintText: "Код комнаты", border: OutlineInputBorder(), isDense: true), onSubmitted: (_) => _join())),
                const SizedBox(width: 8),
                IconButton.filledTonal(onPressed: _busy ? null : _join, icon: const Icon(Icons.login), tooltip: "Join"),
              ]),
              if (_busy && _status != null) ...[const SizedBox(height: 12), const LinearProgressIndicator()],
              const SizedBox(height: 16),
              Text("Your ID: ${_svc.selfId}", textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildGamepad(ColorScheme cs) {
    final hasVideo = _renderer.srcObject != null;
    return Column(
      children: [
        Container(
          color: cs.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Expanded(child: Text("Room ${_svc.roomId} peer:${_cemuPeerId ?? "-"} video:${hasVideo ? "OK" : "wait"}", style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
            IconButton(tooltip: "Copy", icon: const Icon(Icons.copy, size: 18), onPressed: () { Clipboard.setData(ClipboardData(text: _svc.roomId ?? "")); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("copied"))); }),
            IconButton(tooltip: "Leave", icon: const Icon(Icons.exit_to_app, size: 18), onPressed: _leave),
          ]),
        ),
        Expanded(
          child: Container(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                aspectRatio: 854 / 480,
                child: hasVideo && _rendererReady
                    ? Stack(children: [
                        RTCVideoView(_renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
                        Positioned.fill(child: LayoutBuilder(builder: (ctx, constraints) {
                          return GestureDetector(
                            onPanDown: (d) => _handleTouch(d.localPosition, constraints.biggest, true),
                            onPanUpdate: (d) => _handleTouch(d.localPosition, constraints.biggest, true),
                            onPanEnd: (d) { setState(() => _touchDown = false); _svc.sendCemuTouch(x: _touchX, y: _touchY, down: false); },
                            onTapDown: (d) => _handleTouch(d.localPosition, constraints.biggest, true),
                            onTapUp: (d) { setState(() => _touchDown = false); _svc.sendCemuTouch(x: _touchX, y: _touchY, down: false); },
                            child: Container(color: Colors.transparent),
                          );
                        })),
                        if (_touchDown) Positioned(left: _touchX * 300, top: _touchY * 200, child: Container(width: 24, height: 24, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.cyan, width: 2)))),
                      ])
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.videogame_asset_off, color: Colors.white54, size: 48),
                        const SizedBox(height: 12),
                        const Text("Waiting for video от Cemu...", style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 8),
                        Text("Убедись что Cemu bridge запущен и в той же комнате", style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: () => _svc.notifyCemuRole(), child: const Text("Запросить видео")),
                      ]),
              ),
            ),
          ),
        ),
        _buildControls(cs),
      ],
    );
  }
  Widget _buildControls(ColorScheme cs) {
    Widget btn(String label, String key, {Color? color}) {
      final pressed = _buttons[key] ?? false;
      return GestureDetector(
        onTapDown: (_) { setState(() => _buttons[key] = true); _svc.sendCemuButtons({key: true}); },
        onTapUp: (_) { setState(() => _buttons[key] = false); _svc.sendCemuButtons({key: false}); },
        onTapCancel: () { setState(() => _buttons[key] = false); _svc.sendCemuButtons({key: false}); },
        child: Container(width: 48, height: 48, decoration: BoxDecoration(color: pressed ? (color ?? cs.primary) : cs.surfaceContainerHighest, shape: BoxShape.circle, border: Border.all(color: cs.outlineVariant)), child: Center(child: Text(label, style: TextStyle(color: pressed ? Colors.white : cs.onSurface, fontWeight: FontWeight.bold)))),
      );
    }
    Widget stick(String label, void Function(double x, double y) onChange) {
      return Column(children: [
        Text(label, style: const TextStyle(fontSize: 10)),
        const SizedBox(height: 4),
        Container(width: 90, height: 90, decoration: BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle, border: Border.all(color: cs.outlineVariant)), child: GestureDetector(onPanUpdate: (d) { final dx = (d.localPosition.dx / 90 * 2 - 1).clamp(-1.0, 1.0); final dy = (d.localPosition.dy / 90 * 2 - 1).clamp(-1.0, 1.0); setState(() { if (label == "L") { _lx = dx; _ly = dy; } else { _rx = dx; _ry = dy; } }); onChange(dx, dy); }, onPanEnd: (_) { setState(() { if (label == "L") { _lx = 0; _ly = 0; } else { _rx = 0; _ry = 0; } }); onChange(0, 0); }, child: Center(child: Container(width: 36, height: 36, decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle), child: Center(child: Text(label, style: const TextStyle(fontSize: 10))))))),
      ]);
    }
    return Container(color: cs.surface, padding: const EdgeInsets.all(8), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [stick("L", (x,y) => _svc.sendCemuSticks(lx: x, ly: y, rx: _rx, ry: _ry)), Column(children: [Row(children: [btn("X", "x", color: Colors.blue), const SizedBox(width: 8), btn("Y", "y", color: Colors.green)]), const SizedBox(height: 8), Row(children: [btn("A", "a", color: Colors.red), const SizedBox(width: 8), btn("B", "b", color: Colors.orange)])]), stick("R", (x,y) => _svc.sendCemuSticks(lx: _lx, ly: _ly, rx: x, ry: y))]), const SizedBox(height: 8), Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [btn("L", "l"), btn("ZL", "zl"), btn("-", "minus"), btn("+", "plus"), btn("ZR", "zr"), btn("R", "r")]), const SizedBox(height: 6), Row(mainAxisAlignment: MainAxisAlignment.center, children: [btn("HOME", "home", color: Colors.teal), const SizedBox(width: 12), btn("SYNC", "sync"), const SizedBox(width: 24), Column(children: [btn("A", "dpad_up"), Row(children: [btn("<", "dpad_left"), const SizedBox(width: 24), btn(">", "dpad_right")]), btn("V", "dpad_down")])]), const SizedBox(height: 4), Text("Тач 854x480  •  Стики -1..1  •  60Hz DataChannel -> Cemu", style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant))]));
  }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inRoom = _svc.inRoom;
    return Scaffold(appBar: AppBar(title: const Text("Vanilla GamePad (Cemu DRC)"), actions: [if (inRoom) IconButton(icon: const Icon(Icons.exit_to_app), onPressed: _leave)]), body: inRoom ? _buildGamepad(cs) : _buildLobby(cs));
  }
}