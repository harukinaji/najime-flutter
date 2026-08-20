import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

import 'app_attestation.dart';

/// Name of the header carrying the shared application key on every request.
const appKeyHeaderName = 'X-App-Key';

const _appKeyDefine = String.fromEnvironment('APP_KEY');

/// Resolves the shared application key from the frontend `.env` (APP_KEY) or a
/// compile-time `--dart-define=APP_KEY`. Returns `''` when unset; in that case
/// no header is attached (self-hosting without the app key).
String appKeyValue() {
  final fromEnv = dotenv.env['APP_KEY']?.trim() ?? '';
  if (fromEnv.isNotEmpty) return fromEnv;
  return _appKeyDefine;
}

/// Wraps [inner] and injects the shared `X-App-Key` header into every request
/// when an application key is configured. Used for clients that bypass the
/// per-device attestation signer (auth endpoints).
class AppKeyClient extends http.BaseClient {
  AppKeyClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final key = appKeyValue();
    if (key.isNotEmpty) {
      request.headers[appKeyHeaderName] = key;
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Certificate SHA-256 fingerprint pin for the backend server.
/// Extract with: openssl s_client -connect najime.org:5000 < /dev/null 2>/dev/null | openssl x509 -fingerprint -sha256 -noout
/// Format: "AA:BB:CC:..." (uppercase hex, colon-separated)
const _kCertPin = String.fromEnvironment(
  'CERT_PIN',
  defaultValue: '',
);

/// HTTP client that automatically signs every request with per-device
/// attestation headers (HMAC-SHA256 signature, timestamp, nonce).
class SignedHttpClient extends http.BaseClient {
  SignedHttpClient({http.Client? inner}) : _inner = inner ?? _createPinnedClient();

  final http.Client _inner;
  final _attestation = AppAttestation.instance;

  /// Whether a custom `badCertificateCallback` should be installed. When no
  /// pin is configured (and we are not in debug), we leave Dart's default
  /// system certificate verification in place instead of overriding it.
  static bool get shouldOverrideCertificateVerification =>
      kDebugMode || _kCertPin.isNotEmpty;

  /// Shared certificate validation used by both the HTTP and WebSocket
  /// transports. Returns true when the presented certificate is acceptable.
  static bool verifyServerCertificate(X509Certificate cert, String host, int port) {
    // In debug mode, allow all certificates for development.
    if (kDebugMode) return true;

    // No pin configured: never accept here. The caller only installs this
    // callback when a pin is set (or in debug), so reaching this branch with
    // an empty pin is a misconfiguration and must fail closed.
    if (_kCertPin.isEmpty) return false;

    // Compute SHA-256 of the certificate's DER encoding
    // dart:io X509Certificate exposes PEM; extract and hash
    try {
      final pem = cert.pem;
      // Extract DER from PEM (strip headers and newlines)
      final derBase64 = pem
          .replaceAll(RegExp(r'-----BEGIN CERTIFICATE-----'), '')
          .replaceAll(RegExp(r'-----END CERTIFICATE-----'), '')
          .replaceAll(RegExp(r'\s'), '');
      final derBytes = base64Decode(derBase64);

      // Compute SHA-256
      final digest = sha256.convert(derBytes);
      final fingerprint = digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(':');

      return fingerprint == _kCertPin;
    } catch (_) {
      return false;
    }
  }

  static http.Client _createPinnedClient() {
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    if (shouldOverrideCertificateVerification) {
      httpClient.badCertificateCallback = (cert, host, port) =>
          verifyServerCertificate(cert, host, port);
    }

    return http_io.IOClient(httpClient);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_attestation.isInitialized) {
      await _attestation.init();
    }

    // Sign the request.
    // Include the query string in the canonical path to match the backend's
    // attestation verification (backend appends ?query to the path).
    final fullPath = request.url.path +
        (request.url.query.isNotEmpty ? '?${request.url.query}' : '');

    // For multipart requests the body is streamed and cannot be read
    // beforehand, so we sign with an empty body hash. The backend skips
    // body hashing for multipart/ content types.
    String body = '';
    if (request is http.Request) {
      body = request.body;
    }
    final sigHeaders = await _attestation.signRequest(
      method: request.method,
      path: fullPath,
      body: body,
    );

    // Merge attestation headers into the request
    request.headers.addAll(sigHeaders);

    // Attach the shared application key (alongside the account token and the
    // per-device attestation signature).
    final appKey = appKeyValue();
    if (appKey.isNotEmpty) {
      request.headers[appKeyHeaderName] = appKey;
    }

    // Ensure Content-Type is set for POST/PUT
    if (!request.headers.containsKey('Content-Type') &&
        !request.headers.containsKey('content-type')) {
      if (request.method == 'POST' || request.method == 'PUT') {
        request.headers['Content-Type'] = 'application/json';
      }
    }

    if (kDebugMode) {
      debugPrint('[HTTP] ${request.method} ${request.url.path}'
          ' (device_id: ${sigHeaders['X-App-Device-Id'] ?? 'none'})');
    }

    final response = await _inner.send(request);

    if (response.statusCode == 403 && !_retried) {
      debugPrint('[HTTP] 403 on ${request.method} ${request.url.path}'
          ' — re-registering attestation key and retrying');
      _attestation.invalidateRegistration();
      _retried = true;
      try {
        final token = _attestation.authToken;
        if (token != null) {
          await _attestation.ensureRegistered(token);
          final retryHeaders = await _attestation.signRequest(
            method: request.method,
            path: fullPath,
            body: body,
          );
          request.headers.addAll(retryHeaders);
          final retryResponse = await _inner.send(request);
          _retried = false;
          return retryResponse;
        }
      } catch (e) {
        debugPrint('[HTTP] Re-registration retry failed: $e');
      }
      _retried = false;
    }

    return response;
  }

  bool _retried = false;

  @override
  void close() => _inner.close();
}
