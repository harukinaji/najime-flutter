import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class LinkPreview {
  const LinkPreview({
    required this.url,
    required this.domain,
    this.title,
    this.description,
    this.image,
  });

  final Uri url;
  final String domain;
  final String? title;
  final String? description;
  final Uint8List? image;
}

/// Fetches Open Graph/title metadata directly from the device. Requests never
/// go through the Najime backend and never carry Najime authentication.
class LinkPreviewService {
  LinkPreviewService._();

  static final Map<String, Future<LinkPreview?>> _cache = {};
  static final RegExp _urlPattern = RegExp(
    r'https?://[^\s<>"\u0000-\u001f]+',
    caseSensitive: false,
  );

  static Uri? firstUrl(String text) {
    final match = _urlPattern.firstMatch(text);
    if (match == null) return null;
    var candidate = match.group(0)!;
    while (candidate.isNotEmpty &&
        '.,!?;:)\]}'.contains(candidate[candidate.length - 1])) {
      candidate = candidate.substring(0, candidate.length - 1);
    }
    final uri = Uri.tryParse(candidate);
    if (uri == null || !_hasAllowedScheme(uri)) return null;
    return uri;
  }

  static Future<LinkPreview?> fetch(Uri uri) {
    final key = uri.toString();
    final cached = _cache[key];
    if (cached != null) return cached;

    final request = _fetch(uri);
    _cache[key] = request;
    request.then((preview) {
      if (preview == null && identical(_cache[key], request)) {
        _cache.remove(key);
      }
    });
    return request;
  }

  static Future<LinkPreview?> _fetch(Uri initialUri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..idleTimeout = const Duration(seconds: 5)
      ..userAgent =
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
    try {
      final youtubePreview = await _fetchYoutubePreview(client, initialUri);
      if (youtubePreview != null) return youtubePreview;
      final spotifyPreview = await _fetchSpotifyPreview(client, initialUri);
      if (spotifyPreview != null) return spotifyPreview;

      final page = await _getPublicResponse(
        client,
        initialUri,
        maxBytes: 512 * 1024,
        redirectsLeft: 4,
      );
      if (page == null ||
          !(page.contentType?.mimeType.toLowerCase() == 'text/html' ||
              page.contentType?.mimeType.toLowerCase() ==
                  'application/xhtml+xml')) {
        return null;
      }

      final html = utf8.decode(page.bytes, allowMalformed: true);
      final metadata = _metadata(html);
      final title = _clean(metadata['og:title'] ?? metadata['title']);
      final description = _clean(
        metadata['og:description'] ?? metadata['description'],
      );
      final rawImageUri = Uri.tryParse(metadata['og:image'] ?? '');
      Uint8List? image;
      if (rawImageUri != null) {
        final imageUri = page.finalUri.resolveUri(rawImageUri);
        if (!_hasAllowedScheme(imageUri)) {
          return LinkPreview(
            url: initialUri,
            domain: initialUri.host,
            title: title,
            description: description,
          );
        }
        final imageResponse = await _getPublicResponse(
          client,
          imageUri,
          maxBytes: 512 * 1024,
          redirectsLeft: 3,
        );
        if (imageResponse != null &&
            (imageResponse.contentType?.mimeType.toLowerCase().startsWith(
                  'image/',
                ) ??
                false)) {
          image = imageResponse.bytes;
        }
      }

      return LinkPreview(
        url: initialUri,
        domain: initialUri.host,
        title: title,
        description: description,
        image: image,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<LinkPreview?> _fetchSpotifyPreview(
    HttpClient client,
    Uri uri,
  ) async {
    final host = uri.host.toLowerCase();
    if (host != 'open.spotify.com' && host != 'spotify.link') return null;

    final segments = uri.pathSegments;
    final normalized = segments.isNotEmpty && segments.first.startsWith('intl-')
        ? segments.skip(1).toList()
        : segments;
    if (normalized.length < 2 ||
        !const {
          'track',
          'album',
          'episode',
          'show',
          'artist',
          'playlist',
        }.contains(normalized[0])) {
      return null;
    }

    final canonicalUrl = Uri.https(
      'open.spotify.com',
      '/${normalized[0]}/${normalized[1]}',
    );
    final oembedUrl = Uri.https('open.spotify.com', '/oembed', {
      'url': canonicalUrl.toString(),
    });
    try {
      final response = await _getPublicResponse(
        client,
        oembedUrl,
        maxBytes: 64 * 1024,
        redirectsLeft: 3,
      );
      if (response == null) return null;

      final metadata = jsonDecode(utf8.decode(response.bytes));
      if (metadata is! Map<String, dynamic>) return null;
      final title = _clean(metadata['title']?.toString());
      final thumbnailUrl = Uri.tryParse(
        metadata['thumbnail_url']?.toString() ?? '',
      );
      Uint8List? image;
      if (thumbnailUrl != null && _hasAllowedScheme(thumbnailUrl)) {
        final thumbnail = await _getPublicResponse(
          client,
          thumbnailUrl,
          maxBytes: 512 * 1024,
          redirectsLeft: 3,
        );
        if (thumbnail != null &&
            (thumbnail.contentType?.mimeType.toLowerCase().startsWith(
                  'image/',
                ) ??
                false)) {
          image = thumbnail.bytes;
        }
      }

      return LinkPreview(
        url: uri,
        domain: 'Spotify',
        title: title,
        image: image,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<LinkPreview?> _fetchYoutubePreview(
    HttpClient client,
    Uri uri,
  ) async {
    final videoId = _youtubeVideoId(uri);
    if (videoId == null) return null;

    final canonicalUrl = Uri.https('www.youtube.com', '/watch', {'v': videoId});
    final oembedUrl = Uri.https('www.youtube.com', '/oembed', {
      'url': canonicalUrl.toString(),
      'format': 'json',
    });
    final response = await _getPublicResponse(
      client,
      oembedUrl,
      maxBytes: 64 * 1024,
      redirectsLeft: 3,
    );
    if (response == null) return null;

    final metadata = jsonDecode(utf8.decode(response.bytes));
    if (metadata is! Map<String, dynamic>) return null;
    final title = _clean(metadata['title']?.toString());
    final author = _clean(metadata['author_name']?.toString());
    final thumbnailUrl = Uri.tryParse(
      metadata['thumbnail_url']?.toString() ?? '',
    );
    Uint8List? image;
    if (thumbnailUrl != null && _hasAllowedScheme(thumbnailUrl)) {
      final thumbnail = await _getPublicResponse(
        client,
        thumbnailUrl,
        maxBytes: 512 * 1024,
        redirectsLeft: 3,
      );
      if (thumbnail != null &&
          (thumbnail.contentType?.mimeType.toLowerCase().startsWith('image/') ??
              false)) {
        image = thumbnail.bytes;
      }
    }

    return LinkPreview(
      url: uri,
      domain: 'YouTube',
      title: title,
      description: author,
      image: image,
    );
  }

  static String? _youtubeVideoId(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host != 'youtube.com' &&
        host != 'www.youtube.com' &&
        host != 'm.youtube.com' &&
        host != 'youtu.be' &&
        host != 'www.youtu.be') {
      return null;
    }

    String? id;
    if (host.endsWith('youtu.be')) {
      id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    } else if (uri.path == '/watch') {
      id = uri.queryParameters['v'];
    } else if (uri.pathSegments.length >= 2 &&
        const {
          'embed',
          'shorts',
          'live',
          'v',
        }.contains(uri.pathSegments.first)) {
      id = uri.pathSegments[1];
    }
    return id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)
        ? id
        : null;
  }

  static Map<String, String> _metadata(String html) {
    final result = <String, String>{};
    for (final match in RegExp(
      r'<meta\b[^>]*>',
      caseSensitive: false,
    ).allMatches(html)) {
      final tag = match.group(0)!;
      final key = _attribute(tag, 'property') ?? _attribute(tag, 'name');
      final value = _attribute(tag, 'content');
      if (key != null && value != null)
        result.putIfAbsent(key.toLowerCase(), () => value);
    }
    final title = RegExp(
      r'<title\b[^>]*>(.*?)</title\s*>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html)?.group(1);
    if (title != null) result['title'] = _decodeEntities(title);
    return result;
  }

  static String? _attribute(String tag, String name) {
    final match = RegExp(
      '\\b${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
      caseSensitive: false,
    ).firstMatch(tag);
    return match?.group(1) ?? match?.group(2) ?? match?.group(3);
  }

  static String? _clean(String? value) {
    if (value == null) return null;
    final cleaned = _decodeEntities(value)
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  static String _decodeEntities(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  static bool _hasAllowedScheme(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      (uri.hasPort
          ? uri.scheme == 'https'
                ? uri.port == 443
                : uri.port == 80
          : true);

  static Future<_FetchedResponse?> _getPublicResponse(
    HttpClient client,
    Uri uri, {
    required int maxBytes,
    required int redirectsLeft,
  }) async {
    if (!_hasAllowedScheme(uri) || !_isPublicHost(uri.host)) return null;
    final addresses = await InternetAddress.lookup(
      uri.host,
    ).timeout(const Duration(seconds: 4));
    if (addresses.isEmpty ||
        addresses.any((address) => !_isPublicAddress(address))) {
      return null;
    }

    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 5));
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'text/html,application/xhtml+xml,image/*;q=0.8',
    );
    final response = await request.close().timeout(const Duration(seconds: 7));
    if (response.isRedirect) {
      if (redirectsLeft <= 0) return null;
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null) return null;
      final target = uri.resolve(location);
      if (uri.scheme == 'https' && target.scheme != 'https') return null;
      return _getPublicResponse(
        client,
        target,
        maxBytes: maxBytes,
        redirectsLeft: redirectsLeft - 1,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    if (response.contentLength > maxBytes) return null;
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in response.timeout(const Duration(seconds: 7))) {
      total += chunk.length;
      if (total > maxBytes) return null;
      builder.add(chunk);
    }
    return _FetchedResponse(
      finalUri: uri,
      contentType: response.headers.contentType,
      bytes: builder.takeBytes(),
    );
  }

  static bool _isPublicHost(String host) {
    final normalized = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (normalized == 'localhost' || normalized.endsWith('.localhost'))
      return false;
    final literal = InternetAddress.tryParse(normalized);
    return literal == null || _isPublicAddress(literal);
  }

  static bool _isPublicAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return _isPublicIpv4(bytes);
    }
    if (bytes.every((byte) => byte == 0)) return false;
    if (bytes.take(15).every((byte) => byte == 0) && bytes.last == 1)
      return false;
    if ((bytes[0] & 0xfe) == 0xfc ||
        (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80)) {
      return false;
    }
    if (bytes[0] == 0xff) return false;
    if (bytes.take(10).every((byte) => byte == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff) {
      return _isPublicIpv4(bytes.sublist(12));
    }
    return true;
  }

  static bool _isPublicIpv4(List<int> bytes) {
    final a = bytes[0], b = bytes[1];
    if (a == 0 || a == 10 || a == 127 || a >= 224) return false;
    if (a == 100 && b >= 64 && b <= 127) return false;
    if (a == 169 && b == 254) return false;
    if (a == 172 && b >= 16 && b <= 31) return false;
    if (a == 192 && (b == 0 || b == 168)) return false;
    if (a == 192 && b == 88 && bytes[2] == 99) return false;
    if (a == 198 && b == 51 && bytes[2] == 100) return false;
    if (a == 198 && (b == 18 || b == 19)) return false;
    if (a == 203 && b == 0 && bytes[2] == 113) return false;
    return true;
  }
}

class _FetchedResponse {
  const _FetchedResponse({
    required this.finalUri,
    required this.bytes,
    this.contentType,
  });

  final Uri finalUri;
  final Uint8List bytes;
  final ContentType? contentType;
}
