import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';

class StickerCache {
  StickerCache._();
  static final instance = StickerCache._();

  final Map<String, Uint8List> _memCache = {};
  final Map<String, String> _fileCache = {};
  bool _loading = false;
  Directory? _cacheDir;

  bool get isLoaded => _memCache.isNotEmpty;

  Future<void> init() async {
    _cacheDir = await getTemporaryDirectory();
  }

  Future<void> preload(List<String> urls) async {
    if (_loading) return;
    _loading = true;

    final tasks = <Future>[];
    for (final url in urls) {
      if (_memCache.containsKey(url)) continue;
      final fullUrl = url.startsWith('/uploads')
          ? '${AppConfig.apiBaseUrl}$url'
          : url;
      if (fullUrl.endsWith('.json') || fullUrl.endsWith('.tgs')) {
        tasks.add(_loadOne(fullUrl, url));
      } else if (fullUrl.endsWith('.webm') || fullUrl.endsWith('.mp4')) {
        tasks.add(_loadVideo(fullUrl, url));
      }
    }

    await Future.wait(tasks, eagerError: false);
    _loading = false;
    debugPrint(
      '[StickerCache] Preloaded ${_memCache.length} mem + ${_fileCache.length} files',
    );
  }

  Future<void> _loadOne(String fullUrl, String originalUrl) async {
    try {
      final file = await DefaultCacheManager().getSingleFile(fullUrl);
      final bytes = file.readAsBytesSync();
      _memCache[originalUrl] = bytes;
      _memCache[fullUrl] = bytes;
    } catch (_) {}
  }

  Future<void> _loadVideo(String fullUrl, String originalUrl) async {
    try {
      final file = await DefaultCacheManager().getSingleFile(fullUrl);
      final bytes = file.readAsBytesSync();
      _memCache[originalUrl] = bytes;
      _memCache[fullUrl] = bytes;
      // Write to temp file for VideoPlayerController
      final localPath = await _writeTempFile(fullUrl, bytes);
      if (localPath != null) {
        _fileCache[originalUrl] = localPath;
        _fileCache[fullUrl] = localPath;
      }
    } catch (_) {}
  }

  Future<String?> _writeTempFile(String url, Uint8List bytes) async {
    if (_cacheDir == null) return null;
    try {
      final fileName = 'video_${url.hashCode}.dat';
      final file = File('${_cacheDir!.path}/$fileName');
      if (!await file.exists()) {
        await file.writeAsBytes(bytes, flush: true);
      }
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Uint8List? get(String url) => _memCache[url];

  String? getFilePath(String url) => _fileCache[url];

  Future<String> getOrDownloadVideo(String url) async {
    final cached = _fileCache[url];
    if (cached != null && await File(cached).exists()) return cached;

    final fullUrl = url.startsWith('/uploads')
        ? '${AppConfig.apiBaseUrl}$url'
        : url;
    try {
      final res = await http.get(Uri.parse(fullUrl));
      if (res.statusCode == 200) {
        final path = await _writeTempFile(fullUrl, res.bodyBytes);
        if (path != null) {
          _fileCache[url] = path;
          _fileCache[fullUrl] = path;
          return path;
        }
      }
    } catch (_) {}
    return '';
  }

  void put(String url, Uint8List bytes) {
    _memCache[url] = bytes;
    final fullUrl = url.startsWith('/uploads')
        ? '${AppConfig.apiBaseUrl}$url'
        : url;
    _memCache[fullUrl] = bytes;
  }
}
