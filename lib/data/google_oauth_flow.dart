import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

class GoogleOAuthResult {
  final String idToken;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  GoogleOAuthResult({
    required this.idToken,
    this.email,
    this.displayName,
    this.photoUrl,
  });
}

class GoogleOAuthFlow {
  GoogleOAuthFlow._();

  static String get _clientId =>
      (dotenv.env['GOOGLE_OAUTH_CLIENT_ID'] ?? '').trim();
  static const String _exchangeEndpoint =
      '${AppConfig.apiBaseUrl}/api/oauth/google/exchange';
  static const String _authEndpoint =
      'https://accounts.google.com/o/oauth2/v2/auth';

  static final Random _random = Random.secure();

  static String _base64UrlNoPadding(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _generateCodeVerifier() {
    final bytes = List<int>.generate(48, (_) => _random.nextInt(256));
    return _base64UrlNoPadding(bytes);
  }

  static Future<GoogleOAuthResult?> signIn() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    final redirectUri = 'http://127.0.0.1:$port/oauth2callback';

    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _base64UrlNoPadding(
      sha256.convert(utf8.encode(codeVerifier)).bytes,
    );
    final state = _generateCodeVerifier();

    final authUrl = Uri.parse(_authEndpoint).replace(
      queryParameters: {
        'client_id': _clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'openid email profile',
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'state': state,
        'prompt': 'select_account',
      },
    );

    final callback = Completer<HttpRequest>();

    final sub = server.listen((request) {
      if (request.uri.path == '/oauth2callback') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(
            '<html><body style="font-family:sans-serif;text-align:center;'
            'padding-top:40vh"><h2>You can close this window and '
            'return to NajiMe.</h2></body></html>',
          );
        request.response.close();
        if (!callback.isCompleted) callback.complete(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.close();
      }
    });

    try {
      final launched = await launchUrl(
        authUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return null;
      }

      final request = await callback.future.timeout(const Duration(minutes: 5));
      final params = request.uri.queryParameters;

      if (params['state'] != state) return null;
      final code = params['code'];
      if (code == null) return null;

      final tokenResp = await http.post(
        Uri.parse(_exchangeEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'redirect_uri': redirectUri,
          'code_verifier': codeVerifier,
        }),
      );

      if (tokenResp.statusCode != 200) {
        debugPrint(
          'Google token exchange failed: ${tokenResp.statusCode} '
          '${tokenResp.body}',
        );
        return null;
      }

      final tokenBody = jsonDecode(tokenResp.body) as Map<String, dynamic>;
      final idToken = tokenBody['id_token'] as String?;
      if (idToken == null) return null;

      final claims = _decodeIdToken(idToken);
      return GoogleOAuthResult(
        idToken: idToken,
        email: claims?['email'] as String?,
        displayName: claims?['name'] as String?,
        photoUrl: claims?['picture'] as String?,
      );
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    } finally {
      await sub.cancel();
      await server.close(force: true);
    }
  }

  static Map<String, dynamic>? _decodeIdToken(String idToken) {
    try {
      final parts = idToken.split('.');
      if (parts.length < 2) return null;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
