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

  /// Validates an incoming deep link before it is dispatched to the wallet.
  /// Accepts:
  ///   - `https://najime.app/...` (universal links from our own domain)
  ///   - `najime://?<param>=...` (native redirect with an empty host; the
  ///     Phantom/Solflare protocol redirects to `najime://` with query params)
  ///
  /// Any other host/authority is rejected so a hostile app or page cannot
  /// inject arbitrary `najime://` links with a forged authority.
  bool _isTrustedLink(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') {
      return uri.host.toLowerCase() == 'najime.app';
    }
    if (scheme == 'najime') {
      return uri.host.isEmpty && uri.path.isEmpty;
    }
    return false;
  }

  /// Starts listening for incoming links. Safe to call more than once and on
  /// platforms without app_links support (it simply becomes a no-op).
  void init() {
    if (_appLinks != null) return;
    try {
      final appLinks = AppLinks();
      _appLinks = appLinks;
      appLinks.uriLinkStream.listen(
        (Uri? uri) {
          if (uri == null) return;
          if (!_isTrustedLink(uri)) return;
          AppState.instance.dispatchWalletLink(uri.toString());
        },
        onError: (Object e) {
          _lastError = e;
        },
      );
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
      if (initial != null && _isTrustedLink(initial)) {
        AppState.instance.dispatchWalletLink(initial.toString());
      }
    } catch (e) {
      _lastError = e;
    }
  }
}
