import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../data/sticker_cache.dart';

String _resolveUrl(String url) {
  return url.startsWith('/uploads') ? '${AppConfig.apiBaseUrl}$url' : url;
}

bool _isLottieUrl(String url) => url.endsWith('.tgs') || url.endsWith('.json');
bool _isVideoUrl(String url) => url.endsWith('.webm') || url.endsWith('.mp4');

/// Lightweight sticker for grids — cache-first, auto-rebuilds when loaded.
class StickerThumb extends StatefulWidget {
  final String url;
  final double? size;
  final BoxFit fit;

  const StickerThumb({
    super.key,
    required this.url,
    this.size,
    this.fit = BoxFit.cover,
  });

  @override
  State<StickerThumb> createState() => _StickerThumbState();
}

class _StickerThumbState extends State<StickerThumb> {
  Uint8List? _bytes;
  bool _loading = false;

  String get _fullUrl => _resolveUrl(widget.url);
  bool get _isLottie => _isLottieUrl(_fullUrl);
  bool get _isVideo => _isVideoUrl(_fullUrl);

  @override
  void initState() {
    super.initState();
    _bytes = StickerCache.instance.get(widget.url);
    if (_bytes == null && _isLottie) _load();
  }

  @override
  void didUpdateWidget(covariant StickerThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = StickerCache.instance.get(widget.url);
      if (_bytes == null && _isLottie) _load();
    }
  }

  Future<void> _load() async {
    if (_loading || _bytes != null) return;
    _loading = true;
    try {
      final res = await http.get(Uri.parse(_fullUrl));
      if (res.statusCode == 200 && mounted) {
        final data = res.bodyBytes;
        StickerCache.instance.put(widget.url, data);
        setState(() {
          _bytes = data;
          _loading = false;
        });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isVideo) {
      return Container(
        color: Colors.blue.withValues(alpha: 0.08),
        child: Center(
          child: Icon(
            Icons.play_circle_outline,
            size: widget.size != null ? widget.size! * 0.5 : 24,
            color: Colors.blue,
          ),
        ),
      );
    }

    if (_isLottie) {
      if (_bytes != null) {
        return Lottie.memory(
          _bytes!,
          fit: BoxFit.contain,
          repeat: true,
          errorBuilder: (_, __, ___) => _ph(),
        );
      }
      if (_loading) {
        return _ph();
      }
      return _ph();
    }

    return _buildImage(_fullUrl);
  }

  Widget _buildImage(String url) {
    if (url.startsWith('data:image')) {
      try {
        final bytes = base64Decode(url.split(',').last);
        return Image.memory(
          bytes,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _broken(),
        );
      } catch (_) {}
      return _broken();
    }
    return Image.network(
      url,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _broken(),
    );
  }

  Widget _ph() => Container(
    color: Colors.purple.withValues(alpha: 0.08),
    child: Center(
      child: Icon(
        Icons.animation,
        size: widget.size != null ? widget.size! * 0.5 : 24,
        color: Colors.purple,
      ),
    ),
  );

  Widget _broken() => Container(
    color: Colors.grey[200],
    child: Center(
      child: Icon(
        Icons.broken_image,
        size: widget.size != null ? widget.size! * 0.5 : 24,
        color: Colors.grey,
      ),
    ),
  );
}

/// Full-featured sticker — for chat messages.
class StickerWidget extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  const StickerWidget({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  State<StickerWidget> createState() => _StickerWidgetState();
}

class _StickerWidgetState extends State<StickerWidget> {
  Uint8List? _lottieBytes;
  bool _loadingLottie = false;

  String get _fullUrl => _resolveUrl(widget.url);
  bool get _isLottie => _isLottieUrl(_fullUrl);
  bool get _isVideo => _isVideoUrl(_fullUrl);

  @override
  void initState() {
    super.initState();
    if (_isLottie) {
      _lottieBytes = StickerCache.instance.get(widget.url);
      if (_lottieBytes == null) _loadLottie();
    }
  }

  @override
  void didUpdateWidget(covariant StickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url && _isLottie) {
      _lottieBytes = StickerCache.instance.get(widget.url);
      if (_lottieBytes == null) _loadLottie();
    }
  }

  Future<void> _loadLottie() async {
    if (_lottieBytes != null || _loadingLottie) return;
    _loadingLottie = true;
    try {
      final res = await http.get(Uri.parse(_fullUrl));
      if (res.statusCode == 200) {
        final data = res.bodyBytes;
        StickerCache.instance.put(widget.url, data);
        if (mounted)
          setState(() {
            _lottieBytes = data;
            _loadingLottie = false;
          });
      } else {
        if (mounted) setState(() => _loadingLottie = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingLottie = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLottie) return _buildLottie();
    if (_isVideo)
      return _VideoSticker(
        url: _fullUrl,
        width: widget.width,
        height: widget.height,
      );
    return _buildImage();
  }

  Widget _buildLottie() {
    if (_lottieBytes == null) {
      return SizedBox(
        width: widget.width ?? 160,
        height: widget.height ?? 160,
        child: _loadingLottie
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _brokenIcon(),
      );
    }
    return SizedBox(
      width: widget.width ?? 160,
      height: widget.height ?? 160,
      child: Lottie.memory(
        _lottieBytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        repeat: true,
        errorBuilder: (_, __, ___) => _brokenIcon(),
      ),
    );
  }

  Widget _buildImage() {
    final url = _fullUrl;
    if (url.startsWith('data:image')) {
      try {
        final bytes = base64Decode(url.split(',').last);
        return Image.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _brokenIcon(),
        );
      } catch (_) {}
      return _brokenIcon();
    }
    return Image.network(
      url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      loadingBuilder: (ctx, child, progress) {
        if (progress == null) return child;
        return SizedBox(
          width: widget.width ?? 160,
          height: widget.height ?? 160,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => _brokenIcon(),
    );
  }

  Widget _brokenIcon() {
    return Container(
      width: widget.width ?? 160,
      height: widget.height ?? 160,
      color: Colors.grey[200],
      child: const Center(
        child: Icon(Icons.broken_image, size: 32, color: Colors.grey),
      ),
    );
  }
}

class _VideoSticker extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  const _VideoSticker({required this.url, this.width, this.height});
  @override
  State<_VideoSticker> createState() => _VideoStickerState();
}

class _VideoStickerState extends State<_VideoSticker> {
  VideoPlayerController? _controller;
  bool _ok = false;
  bool _err = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // Try cached file first
      final cachedPath = StickerCache.instance.getFilePath(widget.url);
      if (cachedPath != null && await File(cachedPath).exists()) {
        _controller = VideoPlayerController.file(File(cachedPath));
      } else {
        // Download and cache
        final path = await StickerCache.instance.getOrDownloadVideo(widget.url);
        if (path.isNotEmpty) {
          _controller = VideoPlayerController.file(File(path));
        } else {
          _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
        }
      }
      _controller!
        ..setLooping(true)
        ..setVolume(0)
        ..initialize()
            .then((_) {
              if (mounted)
                setState(() {
                  _ok = true;
                  _loading = false;
                  _controller!.play();
                });
            })
            .catchError((_) {
              if (mounted)
                setState(() {
                  _err = true;
                  _loading = false;
                });
            });
    } catch (_) {
      if (mounted)
        setState(() {
          _err = true;
          _loading = false;
        });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_err)
      return Container(
        width: widget.width ?? 160,
        height: widget.height ?? 160,
        color: Colors.grey[200],
        child: const Center(
          child: Icon(Icons.broken_image, size: 32, color: Colors.grey),
        ),
      );
    if (!_ok)
      return SizedBox(
        width: widget.width ?? 160,
        height: widget.height ?? 160,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    return SizedBox(
      width: widget.width ?? 160,
      height: widget.height ?? 160,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
          ),
        ),
      ),
    );
  }
}
