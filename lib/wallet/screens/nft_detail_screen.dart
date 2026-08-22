import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:solana/solana.dart';
import 'package:video_player/video_player.dart';

import '../wallet_media.dart';
import '../models/nft.dart';
import '../services/nft_media_handler.dart';
import '../state/app_state.dart';
import 'nft_screen.dart';

class NftDetailScreen extends StatefulWidget {
  const NftDetailScreen({super.key, required this.nft});

  final Nft nft;

  @override
  State<NftDetailScreen> createState() => _NftDetailScreenState();
}

class _NftDetailScreenState extends State<NftDetailScreen> {
  bool _transferring = false;
  String? _error;

  // Audio NFT playback state (driven by the media-session handler).
  bool _isPlaying = false;
  bool _loadingMedia = false;

  // Video player (video NFTs).
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;

  NftMediaHandler? get _handler => nftMediaHandler;

  @override
  void initState() {
    super.initState();
    _syncFromHandler();
    _initMedia();
    _handler?.playbackState.listen((state) {
      if (!mounted) return;
      if (!widget.nft.isAudio) return;
      final current = _handler?.mediaItem.value;
      final uri = widget.nft.mediaFile?.uri;
      if (current?.id == uri) {
        setState(() => _isPlaying = state.playing);
      } else if (current == null && _isPlaying) {
        // Our audio completed or was stopped from the notification.
        setState(() => _isPlaying = false);
      }
    });
  }

  /// Reflects the handler state (audio may still be playing from a previous
  /// visit to this screen).
  void _syncFromHandler() {
    final handler = _handler;
    final uri = widget.nft.mediaFile?.uri;
    if (handler == null || uri == null) return;
    if (widget.nft.isAudio && handler.mediaItem.value?.id == uri) {
      _isPlaying = handler.playbackState.value.playing;
    }
  }

  Future<void> _initMedia() async {
    final nft = widget.nft;
    if (!nft.hasMedia || nft.mediaFile == null) return;
    final uri = nft.mediaFile!.uri;

    if (nft.isVideo) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(uri));
      await _videoController!.initialize();
      if (mounted) {
        setState(() => _videoInitialized = true);
        await _videoController!.setLooping(true);
        await _videoController!.play();
        _registerVideoSession(playing: true);
      }
    }
  }

  /// Publishes the video NFT metadata to the media session and installs the
  /// hooks that route lock-screen / notification commands to the video player.
  void _registerVideoSession({required bool playing}) {
    final handler = _handler;
    final nft = widget.nft;
    if (handler == null || nft.mediaFile == null) return;
    handler.onVideoPlay = () => _videoController?.play();
    handler.onVideoPause = () => _videoController?.pause();
    handler.onVideoStop = () {
      _videoController?.pause();
      _videoController?.seekTo(Duration.zero);
    };
    handler.onVideoSeek = (position) => _videoController?.seekTo(position);
    handler.setVideoSession(
      uri: nft.mediaFile!.uri,
      title: nft.name,
      artist: nft.symbol.isEmpty ? null : nft.symbol,
      artUri: nft.imageUrl.isEmpty ? null : Uri.tryParse(nft.imageUrl),
    );
    handler.updateVideoState(playing: playing);
  }

  Future<void> _toggleAudio() async {
    final handler = _handler;
    final nft = widget.nft;
    if (handler == null || !nft.isAudio || nft.mediaFile == null) return;
    if (_isPlaying) {
      await handler.stop();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }
    setState(() => _loadingMedia = true);
    try {
      await handler.playAudioNft(
        uri: nft.mediaFile!.uri,
        title: nft.name,
        artist: nft.symbol.isEmpty ? null : nft.symbol,
        artUri: nft.imageUrl.isEmpty ? null : Uri.tryParse(nft.imageUrl),
      );
      if (mounted) {
        setState(() {
          _isPlaying = true;
          _loadingMedia = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingMedia = false;
          _error = 'Failed to play: ${e.toString().split('\n').first}';
        });
      }
    }
  }

  Future<void> _toggleVideo() async {
    final controller = _videoController;
    final handler = _handler;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    handler?.updateVideoState(playing: controller.value.isPlaying);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (widget.nft.isVideo) {
      _handler?.clearVideoSession();
    }
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label copied')));
    }
  }

  Future<void> _transfer() async {
    final controller = TextEditingController();

    final confirmed = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Transfer NFT'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Recipient address',
            hintText: 'Solana address (base58)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final address = controller.text.trim();
              if (address.length < 32 ||
                  !RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$').hasMatch(address)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Invalid Solana address')),
                );
                return;
              }
              Navigator.of(dialogContext).pop(address);
            },
            child: const Text('Transfer'),
          ),
        ],
      ),
    );

    if (confirmed == null || !mounted) return;
    controller.dispose();

    setState(() {
      _transferring = true;
      _error = null;
    });
    try {
      final state = context.read<AppState>();
      final wallet = state.wallet!;
      final signature = await state.solana.transferToken(
        wallet: wallet,
        mint: widget.nft.mint,
        destination: confirmed,
        amount: 1,
        programId: widget.nft.programId,
      );
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
            title: const Text('NFT transferred!'),
            content: SelectableText(
              signature,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.of(context).pop(true);
      }
    } on NoAssociatedTokenAccountException {
      if (mounted) {
        setState(() {
          _transferring = false;
          _error =
              'Recipient doesn\'t have an account for this NFT. Send them some SOL first.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _transferring = false;
          _error = 'Send error: ${e.toString().split('\n').first}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NFT')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 820;
                  return wide ? buildDesktop(context) : buildMobile(context);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildMobile(BuildContext context) {
    final nft = widget.nft;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMedia(context),
        const SizedBox(height: 20),
        Text(
          nft.name,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        if (nft.symbol.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            nft.symbol,
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
          ),
        ],
        if (nft.description.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            nft.description,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
        ],
        const SizedBox(height: 20),
        if (nft.attributes.isNotEmpty) ...[
          const Text(
            'Attributes',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final attr in nft.attributes)
                _AttributeChip(traitType: attr.traitType, value: attr.value),
            ],
          ),
          const SizedBox(height: 20),
        ],
        _DetailRow(
          label: 'Mint',
          value: nft.mint,
          onCopy: () => _copy(nft.mint, 'Mint address'),
        ),
        _DetailRow(
          label: 'Token Account',
          value: nft.tokenAccount,
          onCopy: () => _copy(nft.tokenAccount, 'Account address'),
        ),
        if (nft.hasMedia && nft.mediaFile != null)
          _DetailRow(
            label: 'Category',
            value:
                '${nft.isAudio
                    ? 'Audio'
                    : nft.isVideo
                    ? 'Video'
                    : '—'} · ${nft.mediaFile!.type}',
            onCopy: () => _copy(nft.mediaFile!.uri, 'Media URI'),
          ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: cs.error)),
        ],
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: _transferring ? null : _transfer,
          child: _transferring
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Transfer NFT', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  /// Desktop layout: image on the left, details on the right.
  Widget buildDesktop(BuildContext context) {
    final nft = widget.nft;
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: _buildMedia(context)),
        const SizedBox(width: 24),
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                nft.name,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (nft.symbol.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  nft.symbol,
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                ),
              ],
              if (nft.description.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  nft.description,
                  style: const TextStyle(fontSize: 15, height: 1.45),
                ),
              ],
              const SizedBox(height: 20),
              if (nft.attributes.isNotEmpty) ...[
                const Text(
                  'Attributes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final attr in nft.attributes)
                      _AttributeChip(
                        traitType: attr.traitType,
                        value: attr.value,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              _DetailRow(
                label: 'Mint',
                value: nft.mint,
                onCopy: () => _copy(nft.mint, 'Mint address'),
              ),
              _DetailRow(
                label: 'Token Account',
                value: nft.tokenAccount,
                onCopy: () => _copy(nft.tokenAccount, 'Account address'),
              ),
              if (nft.hasMedia && nft.mediaFile != null)
                _DetailRow(
                  label: 'Category',
                  value:
                      '${nft.isAudio
                          ? 'Audio'
                          : nft.isVideo
                          ? 'Video'
                          : '—'} · ${nft.mediaFile!.type}',
                  onCopy: () => _copy(nft.mediaFile!.uri, 'Media URI'),
                ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: cs.error)),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _transferring ? null : _transfer,
                icon: _transferring
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text(
                  'Transfer NFT',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMedia(BuildContext context) {
    final nft = widget.nft;

    // Video: play inline.
    if (nft.isVideo && _videoController != null) {
      return _buildVideo();
    }

    // Full image (image NFTs, and the poster/backdrop for audio NFTs).
    final image = SizedBox(
      width: double.infinity,
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: NftImage(nft: nft),
        ),
      ),
    );

    if (nft.isAudio) {
      // Audio: poster image + play control.
      return Column(
        children: [
          image,
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _loadingMedia ? null : _toggleAudio,
                icon: _loadingMedia
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                label: Text(_isPlaying ? 'Stop' : 'Play'),
              ),
            ],
          ),
        ],
      );
    }

    return image;
  }

  Widget _buildVideo() {
    final controller = _videoController!;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio == 0
                ? 1
                : controller.value.aspectRatio,
            child: _videoInitialized
                ? VideoPlayer(controller)
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                controller.value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
              iconSize: 40,
              onPressed: _toggleVideo,
            ),
          ],
        ),
      ],
    );
  }
}

class _AttributeChip extends StatelessWidget {
  const _AttributeChip({required this.traitType, required this.value});

  final String traitType;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            traitType,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy, size: 16, color: cs.onSurfaceVariant),
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}
