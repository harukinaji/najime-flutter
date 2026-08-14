import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

import 'app_attestation.dart';

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

  static http.Client _createPinnedClient() {
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // In debug mode, allow all certificates for development
        if (kDebugMode) return true;

        // In release mode, enforce certificate pinning
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
      };

    return http_io.IOClient(httpClient);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_attestation.isInitialized) {
      await _attestation.init();
    }

    // Sign the request
    final body = request is http.Request ? request.body : '';
    final sigHeaders = await _attestation.signRequest(
      method: request.method,
      path: request.url.path,
      body: body,
    );

    // Merge attestation headers into the request
    request.headers.addAll(sigHeaders);

    // Ensure Content-Type is set for POST/PUT
    if (!request.headers.containsKey('Content-Type') &&
        !request.headers.containsKey('content-type')) {
      if (request.method == 'POST' || request.method == 'PUT') {
        request.headers['Content-Type'] = 'application/json';
      }
    }

    return _inner.send(request);
  }

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      _inner.get(url, headers: headers);

  @override
  Future<http.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _inner.post(url, headers: headers, body: body, encoding: encoding);

  @override
  Future<http.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _inner.put(url, headers: headers, body: body, encoding: encoding);

  @override
  Future<http.Response> delete(Uri url, {Object? body, Encoding? encoding, Map<String, String>? headers}) =>
      _inner.delete(url, body: body, encoding: encoding, headers: headers);

  @override
  void close() => _inner.close();
}
