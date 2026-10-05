import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/api_service.dart';
import '../data/link_preview_service.dart';
import '../models/message.dart';
import '../wallet/services/wallet_access_proxy.dart';
import '../wallet/services/check_escrow_service.dart';
import '../wallet/state/app_state.dart';
import 'sticker_widget.dart';

const _sentColor = Color(0xFF18A7B5);

const _audioFileExtensions = <String>{
  'mp3',
  'm4a',
  'mp4',
  'flac',
  'ogg',
  'opus',
  'wav',
  'webm',
  'mkv',
  'aif',
  'aiff',
  'aifc',
  'ape',
  'mov',
};

class _AudioAttachment {
  const _AudioAttachment({
    required this.url,
    required this.title,
    this.artist,
    this.album,
    this.duration,
    this.artwork,
  });

  final String url;
  final String title;
  final String? artist;
  final String? album;
  final Duration? duration;
  final Uint8List? artwork;
}

class _GlobalMusicPlayer {
  _GlobalMusicPlayer._();

  static final instance = _GlobalMusicPlayer._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  AudioPlayer? player;
  _AudioAttachment? track;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool loading = false;

  bool isCurrent(_AudioAttachment audio) => track?.url == audio.url;
  bool get playing => player?.playing ?? false;

  Future<void> toggle(_AudioAttachment audio) async {
    if (!isCurrent(audio) || player == null) {
      await _load(audio);
      // play() completes when playback ends or pauses; don't wait on it here.
      unawaited(player!.play().catchError((Object _) {}));
      _changed();
      return;
    }
    if (playing) {
      await player!.pause();
    } else {
      unawaited(player!.play().catchError((Object _) {}));
    }
    _changed();
  }

  Future<void> _load(_AudioAttachment audio) async {
    loading = true;
    track = audio;
    position = Duration.zero;
    duration = audio.duration ?? Duration.zero;
    _changed();
    await player?.dispose();
    final next = AudioPlayer();
    player = next;
    try {
      final url = audio.url;
      final localFile = File(url);
      if (!url.startsWith('http://') &&
          !url.startsWith('https://') &&
          !url.startsWith('/uploads') &&
          await localFile.exists()) {
        await next.setFilePath(url);
      } else {
        final fullUrl = url.startsWith('/uploads')
            ? '${AppConfig.apiBaseUrl}$url'
            : url;
        final token = ApiService.accessToken;
        await next.setAudioSource(
          AudioSource.uri(
            Uri.parse(fullUrl),
            headers: token == null || token.isEmpty
                ? null
                : {'Authorization': 'Bearer $token'},
          ),
        );
      }
      duration = next.duration ?? duration;
      next.positionStream.listen((value) {
        position = value;
        _changed();
      });
      next.durationStream.listen((value) {
        if (value != null) duration = value;
        _changed();
      });
      next.playerStateStream.listen((state) async {
        if (state.processingState == ProcessingState.completed) {
          await next.pause();
          await next.seek(Duration.zero);
          position = Duration.zero;
        }
        _changed();
      });
    } catch (_) {
      await next.dispose();
      if (identical(player, next)) {
        player = null;
        track = null;
      }
      rethrow;
    } finally {
      loading = false;
      _changed();
    }
  }

  Future<void> close() async {
    await player?.stop();
    await player?.dispose();
    player = null;
    track = null;
    position = Duration.zero;
    duration = Duration.zero;
    loading = false;
    _changed();
  }

  void _changed() {
    revision.value++;
  }
}

Future<void> playProfileSong({
  required String url,
  required String title,
  required String artist,
  required int durationMs,
  Uint8List? artwork,
}) {
  return _GlobalMusicPlayer.instance.toggle(
    _AudioAttachment(
      url: url,
      title: title,
      artist: artist.isEmpty ? null : artist,
      duration: durationMs > 0 ? Duration(milliseconds: durationMs) : null,
      artwork: artwork,
    ),
  );
}

ValueListenable<int> get musicPlayerRevision =>
    _GlobalMusicPlayer.instance.revision;

bool isProfileSongPlaying(String url) {
  final player = _GlobalMusicPlayer.instance;
  return player.track?.url == url && player.playing;
}

class GlobalMusicMiniPlayer extends StatelessWidget {
  const GlobalMusicMiniPlayer({super.key, this.transparent = false});

  final bool transparent;

  Future<void> _openFullPlayer(
    BuildContext context,
    _GlobalMusicPlayer controller,
    _AudioAttachment audio,
  ) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenMusicPlayer(
          audio: audio,
          player: () => controller.player,
          togglePlayback: () => controller.toggle(audio),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _GlobalMusicPlayer.instance;
    return ValueListenableBuilder<int>(
      valueListenable: controller.revision,
      builder: (context, _, __) {
        final audio = controller.track;
        if (audio == null) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
          child: Material(
            color: transparent ? Colors.transparent : cs.surfaceContainerHigh,
            elevation: transparent ? 0 : 2,
            shadowColor: transparent ? Colors.transparent : Colors.black26,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openFullPlayer(context, controller, audio),
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 58,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: audio.artwork == null
                            ? ColoredBox(
                                color: cs.primaryContainer,
                                child: Icon(
                                  Icons.music_note_rounded,
                                  color: cs.primary,
                                ),
                              )
                            : Image.memory(audio.artwork!, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            audio.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            audio.artist ?? 'Unknown artist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: controller.loading
                          ? null
                          : () => controller.toggle(audio),
                      icon: controller.loading
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              controller.playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                    ),
                    IconButton(
                      tooltip: 'Close player',
                      onPressed: controller.close,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FullScreenMusicPlayer extends StatefulWidget {
  const _FullScreenMusicPlayer({
    required this.audio,
    required this.player,
    required this.togglePlayback,
  });

  final _AudioAttachment audio;
  final AudioPlayer? Function() player;
  final Future<void> Function() togglePlayback;

  @override
  State<_FullScreenMusicPlayer> createState() => _FullScreenMusicPlayerState();
}

class _FullScreenMusicPlayerState extends State<_FullScreenMusicPlayer> {
  Future<void> _toggle() async {
    await widget.togglePlayback();
    if (mounted) setState(() {});
  }

  String _time(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final player = widget.player();
    final fallbackDuration = widget.audio.duration ?? Duration.zero;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Now playing'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 34),
          child: Column(
            children: [
              const Spacer(),
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: widget.audio.artwork != null
                      ? Image.memory(widget.audio.artwork!, fit: BoxFit.cover)
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                cs.primaryContainer,
                                cs.tertiaryContainer,
                              ],
                            ),
                          ),
                          child: Icon(
                            Icons.music_note_rounded,
                            size: 112,
                            color: cs.primary,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 30),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.audio.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  [
                        if (widget.audio.artist != null) widget.audio.artist!,
                        if (widget.audio.album != null) widget.audio.album!,
                      ].join(' • ').isEmpty
                      ? 'Unknown artist'
                      : [
                          if (widget.audio.artist != null) widget.audio.artist!,
                          if (widget.audio.album != null) widget.audio.album!,
                        ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
                ),
              ),
              const SizedBox(height: 24),
              StreamBuilder<Duration>(
                stream: player?.positionStream,
                initialData: player?.position ?? Duration.zero,
                builder: (context, positionSnapshot) {
                  final position = positionSnapshot.data ?? Duration.zero;
                  final duration = player?.duration ?? fallbackDuration;
                  final maxMs = duration.inMilliseconds.toDouble();
                  final value = position.inMilliseconds
                      .clamp(0, duration.inMilliseconds)
                      .toDouble();
                  return Column(
                    children: [
                      Slider(
                        value: maxMs > 0 ? value : 0,
                        max: maxMs > 0 ? maxMs : 1,
                        onChanged: player == null || maxMs <= 0
                            ? null
                            : (next) => player.seek(
                                Duration(milliseconds: next.round()),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_time(position)),
                            Text(_time(duration)),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              StreamBuilder<PlayerState>(
                stream: player?.playerStateStream,
                initialData: player?.playerState,
                builder: (context, stateSnapshot) {
                  final playing = stateSnapshot.data?.playing ?? false;
                  return IconButton.filled(
                    onPressed: _toggle,
                    iconSize: 54,
                    padding: const EdgeInsets.all(16),
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                  );
                },
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class MessageBubble extends StatefulWidget {
  final MessageModel message;
  final String? currentUserId;
  final void Function(String emoji)? onReaction;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onCopy;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onPin;
  final VoidCallback? onUnpin;
  final String? searchQuery;
  final bool isCurrentSearchMatch;
  final void Function(String callbackData)? onKeyboardButton;
  final void Function(String text)? onKeyboardSendMessage;
  final void Function(String messageId, String newContent)? onInvoicePaid;

  const MessageBubble({
    super.key,
    required this.message,
    this.currentUserId,
    this.onReaction,
    this.onEdit,
    this.onDelete,
    this.onCopy,
    this.onReply,
    this.onForward,
    this.onPin,
    this.onUnpin,
    this.searchQuery,
    this.isCurrentSearchMatch = false,
    this.onKeyboardButton,
    this.onKeyboardSendMessage,
    this.onInvoicePaid,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  LinkPreview? _linkPreview;
  final Map<String, TapGestureRecognizer> _linkRecognizers = {};
  AudioPlayer? _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isLoading = false;
  List<double> _waveform = [];
  bool _invoicePaying = false;
  bool _invoicePaid = false;
  bool? _chainCheckActive;
  bool _chainCheckStatusLoaded = false;
  bool _checkStatusRequestInFlight = false;
  bool _addingSongToProfile = false;
  bool _songAddedToProfile = false;

  _AudioAttachment? get _audioAttachment {
    if (widget.message.type != MessageType.file) return null;
    final fileName = widget.message.fileName ?? '';
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(widget.message.content);
      if (decoded is Map && decoded['kind'] == 'audio') {
        payload = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}

    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    if (payload == null && !_audioFileExtensions.contains(extension)) {
      return null;
    }

    final metadata = payload?['metadata'] is Map
        ? Map<String, dynamic>.from(payload!['metadata'] as Map)
        : <String, dynamic>{};
    final url = (payload?['url'] ?? widget.message.content).toString();
    if (url.isEmpty) return null;
    final fallbackTitle = fileName.isEmpty
        ? 'Audio track'
        : fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    Uint8List? artwork;
    final encodedArtwork = metadata['art_base64'];
    if (encodedArtwork is String && encodedArtwork.isNotEmpty) {
      try {
        artwork = base64Decode(encodedArtwork);
      } catch (_) {}
    }
    final durationMs = metadata['duration_ms'];
    return _AudioAttachment(
      url: url,
      title: (metadata['title']?.toString().trim().isNotEmpty ?? false)
          ? metadata['title'].toString().trim()
          : fallbackTitle,
      artist: _nonEmptyString(metadata['artist']),
      album: _nonEmptyString(metadata['album']),
      duration: durationMs is num
          ? Duration(milliseconds: durationMs.round())
          : null,
      artwork: artwork,
    );
  }

  String? _nonEmptyString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  String? get _myWalletAddress {
    final appState = AppState.instance;
    // Built-in wallet — can sign on-chain transactions
    if (appState.wallet != null) return appState.wallet!.address;
    // WalletConnect (Phantom/Solflare) — limited on-chain support
    final wcSession = appState.walletConnectSession;
    if (wcSession != null) return wcSession.primaryAccount;
    return null;
  }

  bool get _hasBuiltInWallet => AppState.instance.wallet != null;

  @override
  void initState() {
    super.initState();
    _initWaveform();
    _loadLinkPreview();
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.voiceWaveform != widget.message.voiceWaveform) {
      _initWaveform();
    }
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.content != widget.message.content ||
        oldWidget.message.type != widget.message.type) {
      _player?.dispose();
      _player = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _isPlaying = false;
      _isLoading = false;
      _chainCheckActive = null;
      _chainCheckStatusLoaded = false;
      _addingSongToProfile = false;
      _songAddedToProfile = false;
      _loadLinkPreview();
    }
  }

  Future<void> _loadLinkPreview() async {
    if (widget.message.type != MessageType.text) {
      _linkPreview = null;
      return;
    }
    final uri = LinkPreviewService.firstUrl(widget.message.content);
    _linkPreview = null;
    if (uri == null) return;
    final content = widget.message.content;
    setState(() {
      _linkPreview = LinkPreview(url: uri, domain: uri.host);
    });
    final preview = await LinkPreviewService.fetch(uri);
    if (!mounted || widget.message.content != content) return;
    if (preview != null) setState(() => _linkPreview = preview);
  }

  void _applyCheckChainStatus(CheckData check, bool? active) {
    if (!mounted) return;
    setState(() {
      _chainCheckActive = active;
      _chainCheckStatusLoaded = true;
    });
    if (active == null) return;
    final storedStatus = active ? 'active' : 'closed';
    if (check.status != storedStatus) {
      widget.onInvoicePaid?.call(
        widget.message.id,
        check.copyWith(status: storedStatus).encode(),
      );
    }
  }

  Future<void> _refreshCheckStatus(CheckData check) async {
    final checkId = check.checkId;
    if (checkId == null || checkId.isEmpty || _checkStatusRequestInFlight) {
      return;
    }
    _checkStatusRequestInFlight = true;
    if (mounted) setState(() {});
    try {
      final active = await CheckEscrowService.isCheckActive(
        AppState.instance.solana.client,
        checkId,
      );
      if (!mounted || widget.message.content != check.encode()) return;
      _applyCheckChainStatus(check, active);
    } finally {
      _checkStatusRequestInFlight = false;
      if (mounted) setState(() {});
    }
  }

  void _initWaveform() {
    final stored = widget.message.voiceWaveform;
    if (stored != null && stored.isNotEmpty) {
      _waveform = stored;
    } else {
      _waveform = _generateWaveform(40, widget.message.id);
    }
  }

  @override
  void dispose() {
    for (final recognizer in _linkRecognizers.values) {
      recognizer.dispose();
    }
    _player?.dispose();
    super.dispose();
  }

  List<double> _generateWaveform(int count, String seed) {
    final hash = seed.hashCode;
    final rng = Random(hash);
    final bars = <double>[];
    for (var i = 0; i < count; i++) {
      bars.add(0.15 + rng.nextDouble() * 0.85);
    }
    return bars;
  }

  Future<void> _togglePlayback() async {
    final attachment = _audioAttachment;
    if (widget.message.type != MessageType.voice && attachment == null) return;

    if (attachment != null) {
      try {
        await _GlobalMusicPlayer.instance.toggle(attachment);
      } catch (e, stackTrace) {
        debugPrint('[Audio] Failed to play ${attachment.url}: $e\n$stackTrace');
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('Could not play this audio file')),
          );
        }
      }
      return;
    }

    final url = widget.message.content;
    if (url.isEmpty) return;

    final fullUrl = url.startsWith('/uploads')
        ? '${AppConfig.apiBaseUrl}$url'
        : url;

    if (_player == null) {
      setState(() => _isLoading = true);
      _player = AudioPlayer();
      try {
        final localFile = File(url);
        if (!url.startsWith('http://') &&
            !url.startsWith('https://') &&
            !url.startsWith('/uploads') &&
            await localFile.exists()) {
          await _player!.setFilePath(url);
        } else {
          final token = ApiService.accessToken;
          await _player!.setAudioSource(
            AudioSource.uri(
              Uri.parse(fullUrl),
              headers: token == null || token.isEmpty
                  ? null
                  : {'Authorization': 'Bearer $token'},
            ),
          );
        }
        _duration = _player!.duration ?? Duration.zero;

        _player!.positionStream.listen((pos) {
          if (mounted) setState(() => _position = pos);
        });

        _player!.playerStateStream.listen((state) {
          if (mounted) {
            setState(() {
              _isPlaying = state.playing;
            });
            if (state.processingState == ProcessingState.completed) {
              setState(() {
                _isPlaying = false;
                _position = Duration.zero;
              });
              _player!.seek(Duration.zero);
            }
          }
        });

        setState(() => _isLoading = false);
      } catch (e, stackTrace) {
        debugPrint('[Audio] Failed to open $fullUrl: $e\n$stackTrace');
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('Could not play this audio file')),
          );
        }
        await _player?.dispose();
        _player = null;
        return;
      }
    }

    if (_isPlaying) {
      await _player!.pause();
    } else {
      await _player!.play();
    }
  }

  void _handleReaction(String emoji) {
    widget.onReaction?.call(emoji);
  }

  void _showContextMenu(BuildContext context) {
    final isMe = widget.message.isMe;
    final isText = widget.message.type == MessageType.text;
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Quick reactions row
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['👍', '❤️', '😂', '😮', '😢', '🔥', '👏', '🎉']
                      .map((emoji) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            _handleReaction(emoji);
                          },
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                        );
                      })
                      .toList(),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.reply, color: cs.onSurface),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onReply?.call();
                },
              ),
              if (isText && isMe)
                ListTile(
                  leading: Icon(Icons.edit, color: cs.onSurface),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onEdit?.call();
                  },
                ),
              if (isMe)
                ListTile(
                  leading: Icon(Icons.delete, color: cs.error),
                  title: Text('Delete', style: TextStyle(color: cs.error)),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onDelete?.call();
                  },
                ),
              if (isText)
                ListTile(
                  leading: Icon(Icons.copy, color: cs.onSurface),
                  title: const Text('Copy'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onCopy?.call();
                  },
                ),
              ListTile(
                leading: Icon(Icons.forward, color: cs.onSurface),
                title: const Text('Forward'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onForward?.call();
                },
              ),
              if (widget.message.isPinned)
                ListTile(
                  leading: Icon(Icons.push_pin, color: cs.onSurface),
                  title: const Text('Unpin'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onUnpin?.call();
                  },
                )
              else
                ListTile(
                  leading: Icon(Icons.push_pin_outlined, color: cs.onSurface),
                  title: const Text('Pin'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onPin?.call();
                  },
                ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMe = widget.message.isMe;
    final hasReactions = widget.message.reactions.isNotEmpty;

    // Stickers: no bubble, just the image + time
    if (widget.message.type == MessageType.sticker) {
      return GestureDetector(
        onLongPressStart: (_) {
          HapticFeedback.mediumImpact();
          _showContextMenu(context);
        },
        child: Padding(
          padding: EdgeInsets.only(
            left: isMe ? 48 : 8,
            right: isMe ? 8 : 48,
            top: 2,
            bottom: 2,
          ),
          child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.message.replyToId != null)
                _buildReplyPreview(cs, isMe),
              if (widget.message.forwardedFrom != null)
                _buildForwardedPreview(cs, isMe),
              _buildStickerContent(cs, isMe),
              if (hasReactions) _buildInlineReactions(cs, isMe),
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(widget.message.timestamp),
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      _buildStatusIcon(widget.message.deliveryStatus, isMe, cs),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onLongPressStart: (_) {
        HapticFeedback.mediumImpact();
        _showContextMenu(context);
      },
      child: Padding(
        padding: EdgeInsets.only(
          left: isMe ? 48 : 8,
          right: isMe ? 8 : 48,
          top: 2,
          bottom: 2,
        ),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Row(
              mainAxisAlignment: isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe) const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: isMe ? _sentColor : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isMe ? 20 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 20),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            if (widget.message.forwardedFrom != null)
                              _buildForwardedPreview(cs, isMe),
                            if (widget.message.replyToId != null)
                              _buildReplyPreview(cs, isMe),
                            Padding(
                              padding:
                                  widget.message.type == MessageType.image ||
                                      widget.message.type == MessageType.sticker
                                  ? const EdgeInsets.all(8)
                                  : EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: widget.message.replyToId != null
                                          ? 6
                                          : 10,
                                    ),
                              child: _buildContent(context, cs, isMe),
                            ),
                            if (hasReactions) _buildInlineReactions(cs, isMe),
                            if (widget.message.keyboard != null)
                              _buildInlineKeyboard(cs),
                            Padding(
                              padding: EdgeInsets.only(
                                left: 10,
                                right: 10,
                                bottom: 6,
                                top: hasReactions ? 0 : 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.message.isPinned) ...[
                                    Icon(
                                      Icons.push_pin,
                                      size: 10,
                                      color:
                                          (isMe
                                                  ? Colors.white54
                                                  : cs.onSurfaceVariant)
                                              .withValues(alpha: 0.5),
                                    ),
                                    const SizedBox(width: 2),
                                  ],
                                  if (widget.message.isEdited) ...[
                                    Text(
                                      'edited ',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontStyle: FontStyle.italic,
                                        color:
                                            (isMe
                                                    ? Colors.white70
                                                    : cs.onSurfaceVariant)
                                                .withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                  Text(
                                    _formatTime(widget.message.timestamp),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color:
                                          (isMe
                                                  ? Colors.white70
                                                  : cs.onSurfaceVariant)
                                              .withValues(alpha: 0.6),
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(width: 4),
                                    _buildStatusIcon(
                                      widget.message.deliveryStatus,
                                      isMe,
                                      cs,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineKeyboard(ColorScheme cs) {
    final keyboard = widget.message.keyboard!;
    if (keyboard.rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in keyboard.rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (final btn in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: SizedBox(
                          height: 36,
                          child: OutlinedButton(
                            onPressed: () => _onButtonPressed(btn),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              side: BorderSide(color: cs.outlineVariant),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (btn.url != null) ...[
                                  Icon(
                                    Icons.open_in_new,
                                    size: 14,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Text(
                                    btn.text,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _onButtonPressed(InlineKeyboardButton btn) {
    if (btn.url != null && btn.url!.isNotEmpty) {
      launchUrl(Uri.parse(btn.url!), mode: LaunchMode.externalApplication);
    } else if (btn.sendMessage != null && btn.sendMessage!.isNotEmpty) {
      widget.onKeyboardSendMessage?.call(btn.sendMessage!);
    } else if (btn.callbackData != null) {
      widget.onKeyboardButton?.call(btn.callbackData!);
    }
  }

  Widget _buildInlineReactions(ColorScheme cs, bool isMe) {
    final reactions = widget.message.reactions;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 3,
        children: reactions.map((r) {
          final hasReacted = r.hasUser(widget.currentUserId);
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _handleReaction(r.emoji);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: hasReacted
                    ? (isMe
                          ? Colors.white.withValues(alpha: 0.2)
                          : cs.primary.withValues(alpha: 0.12))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 3),
                  if (r.count <= 2) ...[
                    ...r.users
                        .take(2)
                        .map(
                          (u) => Padding(
                            padding: const EdgeInsets.only(left: 1),
                            child: _buildReactionAvatar(u, isMe, cs),
                          ),
                        ),
                  ] else ...[
                    _buildReactionAvatar(r.users.first, isMe, cs),
                    const SizedBox(width: 2),
                    Text(
                      '${r.count}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isMe ? Colors.white70 : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildReactionAvatar(ReactionUser user, bool isMe, ColorScheme cs) {
    const size = 14.0;
    final hasAvatar = user.avatarUrl.isNotEmpty;

    Widget avatar;

    if (hasAvatar && user.avatarUrl.startsWith('data:image')) {
      try {
        final base64Data = user.avatarUrl.split(',').last;
        final bytes = base64Decode(base64Data);
        avatar = ClipOval(
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {
        avatar = _reactionInitials(user, size, isMe, cs);
      }
    } else if (hasAvatar) {
      avatar = ClipOval(
        child: Image.network(
          user.avatarUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _reactionInitials(user, size, isMe, cs),
        ),
      );
    } else {
      avatar = _reactionInitials(user, size, isMe, cs);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isMe
              ? _sentColor.withValues(alpha: 0.5)
              : cs.surfaceContainerHighest,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatar,
    );
  }

  Widget _reactionInitials(
    ReactionUser user,
    double size,
    bool isMe,
    ColorScheme cs,
  ) {
    final initial = user.displayName.isNotEmpty
        ? user.displayName[0].toUpperCase()
        : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isMe
            ? Colors.white.withValues(alpha: 0.2)
            : cs.primary.withValues(alpha: 0.15),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.5,
            fontWeight: FontWeight.w600,
            color: isMe ? Colors.white70 : cs.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme cs, bool isMe) {
    switch (widget.message.type) {
      case MessageType.text:
        final textStyle = TextStyle(
          color: isMe ? Colors.white : cs.onSurface,
          fontSize: 15,
          height: 1.35,
        );
        final Widget textContent;
        if (widget.searchQuery != null && widget.searchQuery!.isNotEmpty) {
          textContent = _buildHighlightedText(
            widget.message.content,
            widget.searchQuery!,
            textStyle,
            widget.isCurrentSearchMatch,
          );
        } else {
          textContent = _buildLinkifiedText(widget.message.content, textStyle);
        }
        final preview = _linkPreview;
        if (preview == null ||
            widget.searchQuery != null && widget.searchQuery!.isNotEmpty) {
          return textContent;
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            textContent,
            const SizedBox(height: 9),
            _buildLinkPreviewCard(preview, cs, isMe),
          ],
        );

      case MessageType.image:
        final url = widget.message.content;
        final fullUrl = url.startsWith('/uploads')
            ? '${AppConfig.apiBaseUrl}$url'
            : url;
        return GestureDetector(
          onTap: () => _openFullScreenImage(context, fullUrl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260, maxHeight: 320),
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMe ? 20 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 20),
              ),
              child: Image.network(
                fullUrl,
                fit: BoxFit.cover,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    width: 180,
                    height: 180,
                    color: Colors.grey[300],
                    child: const Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  width: 180,
                  height: 180,
                  color: Colors.grey[300],
                  child: const Center(
                    child: Icon(
                      Icons.broken_image,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

      case MessageType.file:
        final audio = _audioAttachment;
        if (audio != null) return _buildMusicContent(cs, isMe, audio);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white.withValues(alpha: 0.2)
                    : cs.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.attach_file,
                color: isMe ? Colors.white70 : cs.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.message.fileName ?? 'File',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMe ? Colors.white : cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    widget.message.fileSize ?? '',
                    style: TextStyle(
                      color: isMe ? Colors.white70 : cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      case MessageType.premiumMessage:
        return _buildPremiumContent(cs, isMe);

      case MessageType.voice:
        return _buildVoiceContent(cs, isMe);

      case MessageType.sticker:
        return _buildStickerContent(cs, isMe);
      case MessageType.invoice:
        return _buildInvoiceContent(cs, isMe);
      case MessageType.check:
        return _buildCheckContent(cs, isMe);
    }
  }

  Widget _buildLinkPreviewCard(LinkPreview preview, ColorScheme cs, bool isMe) {
    final accent = isMe ? Colors.white : cs.primary;
    return InkWell(
      onTap: () => launchUrl(preview.url, mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.black.withValues(alpha: 0.13)
              : cs.surfaceContainerHighest.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (preview.image != null)
              Image.memory(
                preview.image!,
                width: double.infinity,
                height: 150,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview.domain,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (preview.title != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      preview.title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isMe ? Colors.white : cs.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  if (preview.description != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      preview.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isMe ? Colors.white70 : cs.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                  if (preview.title == null && preview.description == null) ...[
                    const SizedBox(height: 3),
                    Text(
                      preview.url.toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isMe ? Colors.white70 : cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceContent(ColorScheme cs, bool isMe) {
    final invoice = InvoiceData.tryParse(widget.message.content);
    if (invoice == null) {
      return Text(
        'Invalid invoice',
        style: TextStyle(color: cs.error, fontSize: 14),
      );
    }
    final paid = _invoicePaid || invoice.status == 'paid';
    final payable = invoice.lamports != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withValues(alpha: 0.14)
              : cs.primaryContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isMe
                ? Colors.white.withValues(alpha: 0.2)
                : cs.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.receipt_long,
                  size: 18,
                  color: isMe ? Colors.white : cs.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Invoice',
                  style: TextStyle(
                    color: isMe ? Colors.white70 : cs.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${invoice.amount} ${invoice.currency}',
              style: TextStyle(
                color: isMe ? Colors.white : cs.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '→ ${_shortAddr(invoice.recipient)}',
              style: TextStyle(
                color: isMe ? Colors.white70 : cs.onSurfaceVariant,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (invoice.memo != null && invoice.memo!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                invoice.memo!,
                style: TextStyle(
                  color: isMe ? Colors.white60 : cs.onSurfaceVariant,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            if (paid) ...[
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: isMe ? Colors.white : Colors.green,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Paid',
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.green,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (invoice.txSignature != null &&
                  invoice.txSignature!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Tx: ${invoice.txSignature!.length > 16 ? '${invoice.txSignature!.substring(0, 8)}...${invoice.txSignature!.substring(invoice.txSignature!.length - 6)}' : invoice.txSignature}',
                  style: TextStyle(
                    color: isMe ? Colors.white60 : cs.onSurfaceVariant,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 12,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Devnet — tokens have no real value',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_invoicePaying)
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isMe ? Colors.white : cs.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Sending…',
                    style: TextStyle(
                      color: isMe ? Colors.white70 : cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              )
            else if (payable && !isMe)
              FilledButton.icon(
                onPressed: _payInvoice,
                icon: const Icon(Icons.account_balance_wallet, size: 18),
                label: const Text('Pay'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(38),
                ),
              )
            else if (payable)
              Text(
                'Awaiting payment',
                style: TextStyle(
                  color: isMe ? Colors.white70 : cs.onSurfaceVariant,
                  fontSize: 13,
                ),
              )
            else
              Text(
                'Payment in ${invoice.currency} is not supported yet',
                style: TextStyle(
                  color: isMe ? Colors.white60 : cs.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _shortAddr(String a) =>
      a.length <= 10 ? a : '${a.substring(0, 4)}…${a.substring(a.length - 4)}';

  Future<void> _payInvoice() async {
    final invoice = InvoiceData.tryParse(widget.message.content);
    if (invoice == null || invoice.lamports == null) return;
    // Capture IDs before any async gaps — the widget may unmount during
    // the Phantom deep-link handoff.
    final messageId = widget.message.id;
    final invoiceContent = widget.message.content;
    if (!mounted) return;
    setState(() => _invoicePaying = true);
    try {
      final ctx = context;
      const proxy = WalletAccessProxy();
      var binding = await proxy.getBinding();
      if (!binding.bound) {
        if (!mounted) return;
        await AppState.instance.restoreExternalWalletSession(ctx);
        binding = await proxy.getBinding();
      }
      if (!binding.bound) {
        if (!mounted) return;
        await AppState.instance.connectExternalWallet(ctx);
      }
      if (!mounted) return;
      binding = await proxy.getBinding();
      final proof = await ApiService.linkWalletAccount(
        walletAddress: binding.publicKey ?? '',
        signMessage: (message) async =>
            (await proxy.signMessage(
              ctx,
              message: utf8.encode(message),
            )).signature ??
            '',
      );
      if (!proof.success)
        throw StateError(proof.message ?? 'Wallet proof failed');
      if (!mounted) return;
      final res = await proxy.paySolana(
        ctx,
        recipient: invoice.recipient,
        lamports: invoice.lamports!,
        memo: 'najime:invoice:$messageId',
      );
      if (kDebugMode) debugPrint('[invoice] paySolana ok');
      // ── Server sync ── runs even if widget unmounted ──
      final txSig = res.signature ?? '';
      bool synced = false;
      try {
        synced = await ApiService.markInvoicePaid(messageId, txSig);
        if (kDebugMode) debugPrint('[invoice] markInvoicePaid');
      } catch (e) {
        debugPrint('[invoice] markInvoicePaid error: $e');
      }
      _pendingInvoiceSignature = txSig;
      if (!synced) {
        synced = await _syncInvoicePaidWithRetry(messageId, txSig);
      }
      if (!synced)
        throw StateError('Payment submitted; confirmation pending: $txSig');
      // ── Update local UI (only if still mounted) ──
      if (mounted) {
        setState(() {
          _invoicePaid = true;
          _invoicePaying = false;
        });
      }
      // Push content update to parent (survives rebuilds via _messages)
      final parsed = InvoiceData.tryParse(invoiceContent);
      if (parsed != null) {
        final updated = parsed.copyWith(status: 'paid', txSignature: txSig);
        widget.onInvoicePaid?.call(messageId, updated.encode());
      }
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text('Paid: $txSig')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _invoicePaying = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: const Text(
              'Payment error. If you already paid, press \"Sync\"',
            ),
            action: SnackBarAction(
              label: 'Sync',
              onPressed: () => _syncInvoicePaid(),
            ),
            duration: const Duration(seconds: 10),
          ),
        );
      } else {
        // Widget gone — try server sync in background (user may have paid)
        if (_pendingInvoiceSignature != null)
          _syncInvoicePaidWithRetry(messageId, _pendingInvoiceSignature!);
      }
    }
  }

  Future<void> _syncInvoicePaid() async {
    final invoice = InvoiceData.tryParse(widget.message.content);
    if (invoice == null || invoice.lamports == null) return;
    if (!mounted) return;
    setState(() => _invoicePaying = true);
    try {
      final synced = await ApiService.markInvoicePaid(
        widget.message.id,
        _pendingInvoiceSignature ?? invoice.txSignature ?? '',
      );
      if (!mounted) return;
      setState(() {
        _invoicePaid = synced;
        _invoicePaying = false;
      });
      if (synced) {
        final parsed = InvoiceData.tryParse(widget.message.content);
        if (parsed != null) {
          final updated = parsed.copyWith(status: 'paid');
          widget.onInvoicePaid?.call(widget.message.id, updated.encode());
        }
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('Status synced')));
      } else {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Server did not confirm payment. Check the status later.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _invoicePaying = false);
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Sync error: $e')));
    }
  }

  String? _pendingInvoiceSignature;

  Future<bool> _syncInvoicePaidWithRetry(String messageId, String txSig) async {
    if (txSig.isEmpty) return false;
    for (var delay = 2; delay <= 30; delay *= 2) {
      await Future.delayed(Duration(seconds: delay));
      try {
        final synced = await ApiService.markInvoicePaid(messageId, txSig);
        if (synced) return true;
      } catch (_) {}
    }
    return false;
  }

  Widget _buildCheckContent(ColorScheme cs, bool isMe) {
    final check = CheckData.tryParse(widget.message.content);
    if (check == null) {
      return Text(
        'Invalid check',
        style: TextStyle(color: cs.error, fontSize: 14),
      );
    }
    final redeemed = check.status == 'redeemed';
    final closedOnChain =
        check.status == 'closed' || _chainCheckActive == false;
    final chainStatusLabel = redeemed
        ? 'Redeemed'
        : closedOnChain
        ? 'Closed on-chain'
        : !_chainCheckStatusLoaded
        ? 'Not checked on-chain'
        : _chainCheckActive == true
        ? 'Active on-chain'
        : 'Status unavailable';
    final isCreator = check.creatorId == widget.currentUserId;
    final sol = check.lamports != null ? check.lamports! / 1e9 : 0.0;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: (redeemed || closedOnChain)
                ? [Colors.grey.shade600, Colors.grey.shade700]
                : [const Color(0xFFF59E0B), const Color(0xFFD97706)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  (redeemed || closedOnChain)
                      ? Icons.receipt_long
                      : Icons.card_giftcard,
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  redeemed
                      ? 'Check redeemed'
                      : closedOnChain
                      ? 'Check no longer active'
                      : 'Check',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${sol.toStringAsFixed(9)} ${check.currency}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (!redeemed) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      chainStatusLabel,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Check status on-chain',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    onPressed: _checkStatusRequestInFlight
                        ? null
                        : () => _refreshCheckStatus(check),
                    icon: _checkStatusRequestInFlight
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.refresh,
                            size: 18,
                            color: Colors.white,
                          ),
                  ),
                ],
              ),
            ],
            if (redeemed && check.txSignature != null) ...[
              const SizedBox(height: 4),
              Text(
                'Tx: ${check.txSignature!.length > 16 ? '${check.txSignature!.substring(0, 8)}...${check.txSignature!.substring(check.txSignature!.length - 6)}' : check.txSignature}',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            if (redeemed || closedOnChain)
              Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 16,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    redeemed
                        ? (isCreator
                              ? 'Your check has been redeemed'
                              : 'Redeemed')
                        : 'This escrow is already closed',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            else if (!isCreator) ...[
              // Show wallet info
              if (_myWalletAddress != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _hasBuiltInWallet ? Icons.check_circle : Icons.warning,
                        size: 12,
                        color: _hasBuiltInWallet
                            ? Colors.green.shade200
                            : Colors.orange.shade200,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _hasBuiltInWallet
                              ? 'To: ${_myWalletAddress!.substring(0, 4)}...${_myWalletAddress!.substring(_myWalletAddress!.length - 4)}'
                              : 'Phantom — limitations on-chain. Create built-in wallet.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 10,
                            fontFamily: _hasBuiltInWallet ? 'monospace' : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _hasBuiltInWallet
                      ? () => _redeemCheck(check)
                      : null,
                  icon: const Icon(Icons.redeem, size: 18),
                  label: Text(
                    !_hasBuiltInWallet ? 'Built-in wallet required' : 'Redeem',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _hasBuiltInWallet
                        ? const Color(0xFFD97706)
                        : Colors.grey,
                  ),
                ),
              ),
            ] else
              Text(
                _chainCheckStatusLoaded && _chainCheckActive == null
                    ? 'On-chain status unavailable'
                    : 'Awaiting redemption',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 12,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Devnet — tokens have no real value',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 10,
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

  Future<void> _redeemCheck(CheckData check) async {
    if (!mounted) return;

    final appState = AppState.instance;
    final binding = await const WalletAccessProxy().getBinding();
    if (!binding.bound || binding.publicKey == null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Connect a wallet first')));
      return;
    }

    if (!_hasBuiltInWallet) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'On-chain checks require a built-in wallet. Phantom does not support custom programs via deep link.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // Use the built-in wallet address as fee payer since we sign with its
    // keypair.  getBinding() may return a WalletConnect address when Phantom
    // is also connected, which would cause an AccountNotSigner error.
    final walletAddress = appState.wallet!.address;
    final checkAddress = check.checkId ?? widget.message.id;
    final chainActive = await CheckEscrowService.isCheckActive(
      appState.solana.client,
      checkAddress,
    );
    if (chainActive != true) {
      if (!mounted) return;
      _applyCheckChainStatus(check, chainActive);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            chainActive == false
                ? 'This check has already been redeemed or closed.'
                : 'Could not read this check from Solana. Try again shortly.',
          ),
        ),
      );
      return;
    }
    _applyCheckChainStatus(check, true);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redeem Check'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount: ${check.amount} ${check.currency}'),
            const SizedBox(height: 8),
            const Text(
              'Your wallet will receive:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text(
              walletAddress,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _invoicePaying = true);
    try {
      var pdaAddress = check.checkId ?? widget.message.id;
      if (pdaAddress.isEmpty) throw Exception('No PDA address for this check');

      // Older locally saved demo checks accidentally stored their seed as
      // check_id. Seeds may contain underscores; derive the PDA for those
      // legacy payloads before passing it to the Base58 address parser.
      if (pdaAddress.contains('_')) {
        final programId = await CheckEscrowService.getProgramId();
        if (programId == null) throw Exception('Program ID not configured');
        pdaAddress = await CheckEscrowService.deriveCheckPda(
          programId,
          pdaAddress,
        );
      }

      final creatorAddr = check.creatorAddress;
      if (creatorAddr == null || creatorAddr.isEmpty) {
        throw Exception(
          'Creator wallet address unknown — cannot redeem legacy check',
        );
      }

      final escrowService = CheckEscrowService(appState.solana.client);
      final txSig = await escrowService.redeemCheck(
        wallet: appState.wallet,
        wcClient: appState.walletConnectClient,
        feePayerAddress: walletAddress,
        pdaAddress: pdaAddress,
        creatorAddress: creatorAddr,
      );

      if (ApiService.accessToken != 'demo-local-session') {
        Map<String, dynamic>? redemption;
        for (var attempt = 0; attempt < 8; attempt++) {
          redemption = await ApiService.redeemCheck(
            pdaAddress,
            txSignature: txSig,
          );
          if (redemption?['success'] == true) break;
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        if (redemption?['success'] != true) {
          throw StateError(
            'Redemption submitted but not yet confirmed: $txSig',
          );
        }
      }

      if (!mounted) return;
      setState(() => _invoicePaying = false);

      final updated = check.copyWith(
        status: 'redeemed',
        redeemerId: widget.currentUserId,
        txSignature: txSig,
      );
      widget.onInvoicePaid?.call(widget.message.id, updated.encode());
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Check redeemed: $txSig')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _invoicePaying = false);
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildMusicContent(ColorScheme cs, bool isMe, _AudioAttachment audio) {
    return ValueListenableBuilder<int>(
      valueListenable: _GlobalMusicPlayer.instance.revision,
      builder: (_, __, ___) => _buildMusicContentState(cs, isMe, audio),
    );
  }

  Widget _buildMusicContentState(
    ColorScheme cs,
    bool isMe,
    _AudioAttachment audio,
  ) {
    final global = _GlobalMusicPlayer.instance;
    final isCurrent = global.isCurrent(audio);
    final isPlaying = isCurrent && global.playing;
    final isLoading = isCurrent && global.loading;
    final showProgress = isCurrent && global.player != null;
    final position = isCurrent ? global.position : Duration.zero;
    final loadedDuration = isCurrent ? global.duration : Duration.zero;
    final totalDuration = loadedDuration.inMilliseconds > 0
        ? loadedDuration
        : (audio.duration ?? Duration.zero);
    final primary = isMe ? Colors.white : cs.primary;
    final secondary = isMe ? Colors.white70 : cs.onSurfaceVariant;
    final maxMs = totalDuration.inMilliseconds.toDouble();
    final positionMs = position.inMilliseconds
        .clamp(0, totalDuration.inMilliseconds)
        .toDouble();

    return InkWell(
      onTap: () => _openMusicPlayer(audio),
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 230, maxWidth: 300),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: isLoading ? null : _togglePlayback,
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: _buildMusicArtwork(audio, primary, cs, isMe),
                      ),
                      if (isLoading)
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.28),
                          child: const Padding(
                            padding: EdgeInsets.all(15),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      if (!isLoading)
                        Center(
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.48),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    audio.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMe ? Colors.white : cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  if (showProgress)
                    Row(
                      children: [
                        Text(
                          _formatDuration(position),
                          style: TextStyle(color: secondary, fontSize: 11),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: primary,
                              inactiveTrackColor: primary.withValues(
                                alpha: 0.35,
                              ),
                              thumbColor: primary,
                              overlayColor: primary.withValues(alpha: 0.12),
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 4,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 10,
                              ),
                            ),
                            child: Slider(
                              value: maxMs > 0 ? positionMs : 0,
                              max: maxMs > 0 ? maxMs : 1,
                              onChanged: maxMs <= 0 || global.player == null
                                  ? null
                                  : (value) => global.player!.seek(
                                      Duration(milliseconds: value.round()),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      [
                        _formatDuration(totalDuration),
                        if (audio.artist != null) audio.artist!,
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: secondary, fontSize: 12),
                    ),
                ],
              ),
            ),
            if (ApiService.accessToken != null)
              IconButton(
                tooltip: _songAddedToProfile
                    ? 'Added to profile'
                    : 'Add to profile',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 38,
                  height: 42,
                ),
                onPressed: _addingSongToProfile || _songAddedToProfile
                    ? null
                    : () => _addSongToProfile(audio),
                icon: _addingSongToProfile
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _songAddedToProfile
                            ? Icons.check_circle_outline_rounded
                            : Icons.person_add_alt_1_rounded,
                        color: _songAddedToProfile ? Colors.green : secondary,
                        size: 19,
                      ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMusicArtwork(
    _AudioAttachment audio,
    Color foreground,
    ColorScheme cs,
    bool isMe,
  ) {
    if (audio.artwork != null) {
      return Image.memory(
        audio.artwork!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.music_note_rounded, color: foreground),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isMe
              ? [Colors.white30, Colors.white10]
              : [cs.primaryContainer, cs.tertiaryContainer],
        ),
      ),
      child: Icon(Icons.music_note_rounded, size: 26, color: foreground),
    );
  }

  Future<void> _openMusicPlayer(_AudioAttachment audio) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenMusicPlayer(
          audio: audio,
          player: () => _GlobalMusicPlayer.instance.player,
          togglePlayback: _togglePlayback,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _addSongToProfile(_AudioAttachment audio) async {
    if (_addingSongToProfile || _songAddedToProfile) return;
    if (ApiService.accessToken == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Sign in to add songs to your profile')),
      );
      return;
    }
    setState(() => _addingSongToProfile = true);
    final globalPlayer = _GlobalMusicPlayer.instance;
    final duration =
        audio.duration?.inMilliseconds ??
        (globalPlayer.isCurrent(audio)
            ? globalPlayer.duration.inMilliseconds
            : 0);
    final added = await ApiService.addProfileSong(
      sourceUrl: audio.url,
      title: audio.title,
      artist: audio.artist ?? '',
      durationMs: duration,
      artworkBase64: audio.artwork == null ? '' : base64Encode(audio.artwork!),
    );
    if (!mounted) return;
    setState(() {
      _addingSongToProfile = false;
      _songAddedToProfile = added;
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          added ? 'Added to your profile' : 'Could not add song to profile',
        ),
      ),
    );
  }

  Widget _buildVoiceContent(ColorScheme cs, bool isMe) {
    final totalDuration = _duration.inMilliseconds > 0
        ? _duration
        : Duration(milliseconds: widget.message.voiceDurationMs ?? 0);

    final progress = totalDuration.inMilliseconds > 0
        ? (_position.inMilliseconds / totalDuration.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    final displayDuration = _isPlaying || _position.inMilliseconds > 0
        ? _position
        : totalDuration;

    final barCount = _waveform.length;
    final playedIndex = (progress * barCount).floor();

    return Stack(
      children: [
        // Waveform background
        GestureDetector(
          onTapDown: (details) async {
            if (_player == null || _duration.inMilliseconds == 0) return;
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            final localX = details.localPosition.dx;
            final waveformWidth = box.size.width;
            if (waveformWidth <= 0) return;
            final tapProgress = (localX / waveformWidth).clamp(0.0, 1.0);
            final seekMs = (tapProgress * _duration.inMilliseconds).round();
            await _player!.seek(Duration(milliseconds: seekMs));
          },
          child: SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(barCount, (i) {
                final height = _waveform[i] * 44.0 + 4.0;
                final isPlayed = i <= playedIndex;
                final barColor = isPlayed
                    ? (isMe ? Colors.white : cs.primary)
                    : (isMe
                          ? Colors.white.withValues(alpha: 0.3)
                          : cs.onSurfaceVariant.withValues(alpha: 0.3));

                return Expanded(
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: 2.5,
                      height: height,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        // Overlay: play button + duration
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _togglePlayback,
                child: _isLoading
                    ? SizedBox(
                        width: 36,
                        height: 36,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isMe ? Colors.white : cs.primary,
                            ),
                          ),
                        ),
                      )
                    : Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.2)
                              : cs.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: isMe ? Colors.white : cs.primary,
                          size: 22,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDuration(displayDuration),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: (isMe ? Colors.white : cs.onSurface).withValues(
                        alpha: 0.9,
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(totalDuration),
                    style: TextStyle(
                      fontSize: 10,
                      color: (isMe ? Colors.white : cs.onSurfaceVariant)
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openFullScreenImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                },
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(
                    Icons.broken_image,
                    size: 64,
                    color: Colors.white54,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStickerContent(ColorScheme cs, bool isMe) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160, maxHeight: 160),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: StickerWidget(
          url: widget.message.content,
          width: 160,
          height: 160,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildPremiumContent(ColorScheme cs, bool isMe) {
    if (widget.message.premiumInfo != null &&
        widget.message.premiumInfo!.isUnlocked) {
      return Text(
        widget.message.content,
        style: TextStyle(
          color: isMe ? Colors.white : cs.onSurface,
          fontSize: 15,
          height: 1.35,
        ),
      );
    }

    return Column(
      children: [
        Icon(
          Icons.lock_outline,
          color: isMe ? Colors.white70 : cs.onSurfaceVariant,
          size: 28,
        ),
        const SizedBox(height: 8),
        Text(
          'Premium Message',
          style: TextStyle(
            color: isMe ? Colors.white : cs.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap to unlock',
          style: TextStyle(
            color: isMe ? Colors.white70 : cs.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildForwardedPreview(ColorScheme cs, bool isMe) {
    final forwarded = widget.message.forwardedFrom!;
    final barColor = isMe ? Colors.white70 : cs.primary;

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: isMe
          ? const EdgeInsets.only(left: 8, right: 10, top: 3, bottom: 2)
          : const EdgeInsets.only(left: 10, right: 8, top: 3, bottom: 2),
      decoration: BoxDecoration(
        border: isMe
            ? Border(right: BorderSide(color: barColor, width: 3))
            : Border(left: BorderSide(color: barColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forward, size: 14, color: barColor),
              const SizedBox(width: 4),
              Text(
                'Forwarded from',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: barColor,
                  height: 1.2,
                ),
              ),
            ],
          ),
          Text(
            forwarded.originalSenderName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: barColor,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview(ColorScheme cs, bool isMe) {
    final senderName = widget.message.replyToSenderName ?? '';
    final replyContent = widget.message.replyToContent ?? '';
    final displayContent = replyContent.isEmpty ? '📷 Photo' : replyContent;
    final barColor = isMe ? Colors.white70 : cs.primary;

    return GestureDetector(
      onTap: () {
        // TODO: scroll to original message by replyToId
      },
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: isMe
            ? const EdgeInsets.only(left: 8, right: 10, top: 3, bottom: 2)
            : const EdgeInsets.only(left: 10, right: 8, top: 3, bottom: 2),
        decoration: BoxDecoration(
          border: isMe
              ? Border(right: BorderSide(color: barColor, width: 3))
              : Border(left: BorderSide(color: barColor, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              senderName,
              textAlign: isMe ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: barColor,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              displayContent,
              textAlign: isMe ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: (isMe ? Colors.white60 : cs.onSurfaceVariant).withValues(
                  alpha: 0.7,
                ),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildStatusIcon(DeliveryStatus status, bool isMe, ColorScheme cs) {
    final color = (isMe ? Colors.white70 : cs.onSurfaceVariant).withValues(
      alpha: 0.6,
    );
    switch (status) {
      case DeliveryStatus.sending:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
        );
      case DeliveryStatus.sent:
        return Icon(Icons.check, size: 14, color: color);
      case DeliveryStatus.delivered:
        return Icon(Icons.done_all, size: 14, color: color);
      case DeliveryStatus.read:
        return const Icon(Icons.done_all, size: 14, color: Color(0xFF22C55E));
    }
  }

  Widget _buildHighlightedText(
    String text,
    String query,
    TextStyle style,
    bool isCurrent,
  ) {
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start), style: style));
        }
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: style));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: style.copyWith(
            backgroundColor: isCurrent
                ? const Color(0xFFFFEB3B)
                : const Color(0xFFFFEB3B).withValues(alpha: 0.5),
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      start = index + query.length;
    }

    return RichText(text: TextSpan(children: spans));
  }

  Widget _buildLinkifiedText(String text, TextStyle style) {
    final spans = <TextSpan>[];
    final urlPattern = RegExp(
      r'https?://[^\s<>"\u0000-\u001f]+',
      caseSensitive: false,
    );
    var cursor = 0;
    for (final match in urlPattern.allMatches(text)) {
      var end = match.end;
      while (end > match.start && '.,!?;:)\]}'.contains(text[end - 1])) {
        end--;
      }
      if (end <= match.start) continue;
      if (match.start > cursor) {
        spans.add(
          TextSpan(text: text.substring(cursor, match.start), style: style),
        );
      }
      final urlText = text.substring(match.start, end);
      final uri = Uri.tryParse(urlText);
      if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
        spans.add(TextSpan(text: urlText, style: style));
      } else {
        final recognizer = _linkRecognizers.putIfAbsent(
          urlText,
          () => TapGestureRecognizer()
            ..onTap = () async {
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
        );
        spans.add(
          TextSpan(
            text: urlText,
            style: style.copyWith(
              color: style.color == Colors.white ? Colors.white : Colors.blue,
              decoration: TextDecoration.underline,
              decorationColor: style.color == Colors.white
                  ? Colors.white
                  : Colors.blue,
            ),
            recognizer: recognizer,
          ),
        );
      }
      cursor = end;
      if (end < match.end) {
        spans.add(TextSpan(text: text.substring(end, match.end), style: style));
        cursor = match.end;
      }
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
    }
    return RichText(text: TextSpan(children: spans));
  }
}
