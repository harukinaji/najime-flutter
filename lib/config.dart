/// Central application configuration.
///
/// The backend endpoints can be overridden at build/run time without touching
/// the source code, e.g.:
///
/// ```bash
/// flutter run --dart-define=API_BASE_URL=https://api.example.com
/// ```
class AppConfig {
  AppConfig._();

  /// Base URL of the backend API. Defaults to the public Najime development
  /// server; point it at your own backend for self-hosting.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://najime.org:5000',
  );

  /// Returns true if the API base URL uses HTTPS.
  static bool get isSecure => apiBaseUrl.startsWith('https://');

  /// WebSocket endpoint derived from [apiBaseUrl].
  static String get wsBaseUrl {
    if (apiBaseUrl.startsWith('https://')) {
      return 'wss://${apiBaseUrl.substring('https://'.length)}';
    }
    // Enforce secure WebSocket - never allow plaintext ws://
    assert(false, 'API_BASE_URL must use HTTPS in production');
    return 'wss://${apiBaseUrl.replaceFirst(RegExp(r'^https?://'), '')}';
  }

  /// Host (without scheme/port) used to build STUN/TURN URLs.
  static String get webrtcHost {
    final uri = Uri.tryParse(apiBaseUrl);
    return uri?.host ?? 'najime.org';
  }
}
