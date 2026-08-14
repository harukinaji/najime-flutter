import 'package:app_links/app_links.dart';

import '../state/app_state.dart';

/// Global bridge that feeds wallet deep-link returns (custom scheme `najime://`
/// on Android/iOS, app links on desktop) into AppKit so Phantom/Solflare
/// connect/sign requests complete after the wallet redirects back to the app.
class WalletDeepLinks {
  WalletDeepLinks._();

  static final WalletDeepLinks instance = WalletDeepLinks._();

  AppLinks? _appLinks;
  Object? _lastError;

  /// Last error surfaced to the UI (e.g. app_links missing on this platform).
  Object? get lastError => _lastError;

  /// Starts listening for incoming links. Safe to call more than once and on
  /// platforms without app_links support (it simply becomes a no-op).
  void init() {
    if (_appLinks != null) return;
    try {
      final appLinks = AppLinks();
      _appLinks = appLinks;
      appLinks.uriLinkStream.listen((Uri? uri) {
        if (uri == null) return;
        // Only accept najime:// scheme or https links from trusted domains
        final scheme = uri.scheme.toLowerCase();
        if (scheme != 'najime' && scheme != 'https') return;
        if (scheme == 'https' && uri.host != 'najime.app') return;
        AppState.instance.dispatchWalletLink(uri.toString());
      }, onError: (Object e) {
        _lastError = e;
      });
    } catch (e) {
      _lastError = e;
    }
    _checkInitialLink();
  }

  Future<void> _checkInitialLink() async {
    final appLinks = _appLinks;
    if (appLinks == null) return;
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) {
        final scheme = initial.scheme.toLowerCase();
        if (scheme != 'najime' && scheme != 'https') return;
        if (scheme == 'https' && initial.host != 'najime.app') return;
        AppState.instance.dispatchWalletLink(initial.toString());
      }
    } catch (e) {
      _lastError = e;
    }
  }
}