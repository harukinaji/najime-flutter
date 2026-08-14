// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pinenacl/x25519.dart' as pncl;
import 'package:solana/base58.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api_service.dart';

/// External wallets supported through the direct E2E-encrypted deep-link
/// protocol (Phantom / Solflare both implement the same `ul/v1` scheme built
/// on NaCl crypto_box: X25519 + XSalsa20-Poly1305).
enum SolanaWalletKind { phantom, solflare }

/// A session established with an external Solana wallet (Phantom/Solflare).
class WalletConnectSession {
  const WalletConnectSession({required this.peerName, this.primaryAccount});

  /// Display name of the connected wallet.
  final String peerName;

  /// Base58 Solana address, or null when not connected.
  final String? primaryAccount;
}

/// Result of a `solana_signMessage` request.
class WalletConnectSignResult {
  WalletConnectSignResult({required this.signature, required this.publicKey});

  /// Raw 64-byte Ed25519 signature.
  final Uint8List signature;

  /// Base58 address that produced the signature.
  final String publicKey;
}

/// Result of a `solana_signTransaction` / `solana_signAndSendTransaction`
/// request.
class WalletConnectTxResult {
  WalletConnectTxResult({required this.signature, required this.publicKey});

  /// Base58 signature/txid, or base58 serialized signed transaction
  /// (signTransaction path).
  final String signature;

  /// Base58 address that produced the signature.
  final String publicKey;
}

/// External-wallet client backed by the direct Phantom/Solflare universal-link
/// protocol (no WalletConnect / Reown dependency).
///
/// Every request is encrypted end-to-end with a shared secret derived from an
/// X25519 key agreement performed during `connect`. The wallet redirects back
/// to the app custom scheme (`najime://`) with the encrypted response, which
/// [dispatchLink] decrypts and routes to the in-flight request.
class WalletConnectClient {
  WalletConnectClient({required this.config});

  final WalletConnectConfig config;

  static const _secureStorage = FlutterSecureStorage();

  final StreamController<WalletConnectSession> _sessionController =
      StreamController.broadcast();
  final StreamController<void> _deletedController =
      StreamController.broadcast();
  final StreamController<Object> _errorController =
      StreamController.broadcast();

  /// Emits a newly established [WalletConnectSession].
  Stream<WalletConnectSession> get onSessionCreated =>
      _sessionController.stream;

  /// Emits when the wallet disconnects.
  Stream<void> get onSessionDeleted => _deletedController.stream;

  /// Emits non-fatal errors for the UI to surface.
  Stream<Object> get onError => _errorController.stream;

  bool _initialized = false;
  SolanaWalletKind? _wallet;

  // Session state.
  pncl.PrivateKey? _keyPair;
  pncl.Box? _box;
  String? _sessionToken;
  String? _address;
  String? _peerName;

  // In-flight request.
  Completer<Map<String, String>>? _pending;

  bool get isInitialized => _initialized;

  /// The active session, if any.
  WalletConnectSession? get session =>
      _address == null
          ? null
          : WalletConnectSession(
              peerName: _peerName ?? 'Wallet',
              primaryAccount: _address,
            );

  // ── Per-wallet protocol constants ───────────────────────────────────

  String get _host =>
      _wallet == SolanaWalletKind.solflare ? 'solflare.com' : 'phantom.app';

  String get _requestParam =>
      _wallet == SolanaWalletKind.solflare
          ? 'solflareRequest'
          : 'phantomRequest';

  String get _encryptionKeyParam =>
      _wallet == SolanaWalletKind.solflare
          ? 'solflare_encryption_public_key'
          : 'phantom_encryption_public_key';

  String _peerNameFor(SolanaWalletKind wallet) =>
      wallet == SolanaWalletKind.solflare ? 'Solflare' : 'Phantom';

  String get _dappPublicKey =>
      base58encode(_keyPair!.publicKey.asTypedList);

  String get _redirectBase =>
      config.metadata.redirectNative.isNotEmpty
          ? config.metadata.redirectNative
          : 'najime://';

  String get _appUrl =>
      config.metadata.url.isNotEmpty ? config.metadata.url : 'https://najime.app';

  // ── Lifecycle ───────────────────────────────────────────────────────

  /// Restores a persisted session (idempotent). No network/relay setup needed.
  Future<void> ensureInitialized(BuildContext context) async {
    if (_initialized) return;
    await restore();
    _initialized = true;
  }

  /// Connects to [wallet] via its encrypted deep-link `connect` request.
  /// Blocks until the wallet redirects back (or the request times out).
  Future<void> connect(SolanaWalletKind wallet) async {
    _wallet = wallet;
    _keyPair = pncl.PrivateKey.generate();

    final uri = _buildUri('/connect', {
      'dapp_encryption_public_key': _dappPublicKey,
      'cluster': 'devnet',
      'app_url': _appUrl,
      'redirect_link': '$_redirectBase?${_requestParam}=connect',
    });

    final params = await _launchAndWait(uri, kind: 'connect');

    final remoteKey = params[_encryptionKeyParam];
    if (remoteKey == null || remoteKey.isEmpty) {
      throw StateError('Wallet did not return an encryption key');
    }
    _box = pncl.Box(
      myPrivateKey: _keyPair!,
      theirPublicKey:
          pncl.PublicKey(Uint8List.fromList(base58decode(remoteKey))),
    );

    final payload = _decrypt(params);
    _sessionToken = payload['session']?.toString();
    _address = payload['public_key']?.toString();
    _peerName = _peerNameFor(wallet);

    if (_sessionToken == null || _sessionToken!.isEmpty) {
      throw StateError('Wallet did not return a session token');
    }
    await _persist(remoteKey: remoteKey);
    _emitSession();
  }

  /// Loads a previously persisted session back into memory.
  Future<bool> restore() async {
    try {
      final walletName = await _secureStorage.read(key: 'naji_dl.wallet');
      if (walletName == null) return false;
      final privateKey = await _secureStorage.read(key: 'naji_dl.private_key');
      final remoteKey = await _secureStorage.read(key: 'naji_dl.remote_key');
      final sessionToken = await _secureStorage.read(key: 'naji_dl.session_token');
      final address = await _secureStorage.read(key: 'naji_dl.address');
      final peerName = await _secureStorage.read(key: 'naji_dl.peer_name');
      if (privateKey == null || remoteKey == null || sessionToken == null || address == null) {
        return false;
      }
      _wallet = walletName == 'solflare' ? SolanaWalletKind.solflare : SolanaWalletKind.phantom;
      _keyPair = pncl.PrivateKey(Uint8List.fromList(base58decode(privateKey)));
      _box = pncl.Box(
        myPrivateKey: _keyPair!,
        theirPublicKey: pncl.PublicKey(Uint8List.fromList(base58decode(remoteKey))),
      );
      _sessionToken = sessionToken;
      _address = address;
      _peerName = peerName ?? _peerNameFor(_wallet!);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Signing ─────────────────────────────────────────────────────────

  /// Requests `message` to be signed by the connected wallet.
  Future<WalletConnectSignResult> signMessage(Uint8List message) async {
    _requireSession();
    final params = await _launchAndWait(
      _buildRequestUri('/signMessage', {
        'session': _sessionToken!,
        'message': base58encode(message),
      }),
      kind: 'signMessage',
    );
    final payload = _decrypt(params);
    final signature = payload['signature']?.toString() ?? '';
    if (signature.isEmpty) {
      throw StateError('Missing signature in response');
    }
    return WalletConnectSignResult(
      signature: Uint8List.fromList(base58decode(signature)),
      publicKey: _address!,
    );
  }

  /// Asks the connected wallet to sign a base58-serialized Solana transaction.
  /// Returns the base58 serialized signed transaction.
  Future<WalletConnectTxResult> signTransaction(String transaction) async {
    _requireSession();
    final params = await _launchAndWait(
      _buildRequestUri('/signTransaction', {
        'session': _sessionToken!,
        'transaction': transaction,
      }),
      kind: 'signTransaction',
    );
    final payload = _decrypt(params);
    final signed =
        (payload['transaction'] ?? payload['signature'])?.toString() ?? '';
    if (signed.isEmpty) {
      throw StateError('Missing signed transaction in response');
    }
    return WalletConnectTxResult(signature: signed, publicKey: _address!);
  }

  /// Asks the connected wallet to sign and send a base58-serialized Solana
  /// transaction. Returns the on-chain transaction id.
  Future<WalletConnectTxResult> signAndSendTransaction(
    String transaction,
  ) async {
    _requireSession();
    debugPrint('[wc] signAndSendTransaction via ${_peerName ?? _wallet}');
    final params = await _launchAndWait(
      _buildRequestUri('/signAndSendTransaction', {
        'session': _sessionToken!,
        'transaction': transaction,
      }),
      kind: 'signAndSendTransaction',
    );
    final payload = _decrypt(params);
    final txid =
        (payload['signature'] ??
            payload['transaction_id'] ??
            payload['transaction'])?.toString() ?? '';
    if (txid.isEmpty) {
      throw StateError('Missing transaction id in response');
    }
    return WalletConnectTxResult(signature: txid, publicKey: _address!);
  }

  /// Disconnects the active external-wallet session (local state + persistence
  /// cleared; the wallet's own session token is simply abandoned).
  Future<void> disconnect() async {
    _clearState();
    await _clearPersisted();
    if (!_deletedController.isClosed) _deletedController.add(null);
  }

  // ── Deep-link redirect handling ─────────────────────────────────────

  /// Feeds a deep-link return URL (from the app custom scheme) into the client
  /// so an in-flight request completes. Returns true when the URL was consumed.
  bool dispatchLink(String url) {
    Uri uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return false;
    }

    // Validate URI scheme
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'najime' && scheme != 'https') return false;

    final params = uri.queryParameters;

    if (params.containsKey('errorCode') || params.containsKey('errorMessage')) {
      final code = params['errorCode'] ?? '-1';
      final message = params['errorMessage'] ?? 'Wallet error';
      _completeError(StateError('Wallet error ($code): $message'));
      return true;
    }

    final request = params[_requestParam];
    if (request == null) return false;

    if (request == 'connect') {
      _complete(params);
      return true;
    }
    if (request == 'disconnect') {
      _clearState();
      _complete(const {});
      return true;
    }

    _complete(params);
    return true;
  }

  // ── Internal ────────────────────────────────────────────────────────

  void _requireSession() {
    if (_sessionToken == null || _address == null || _box == null) {
      throw StateError('No external wallet connected');
    }
  }

  String _buildUri(String method, Map<String, String> params) {
    final uri = Uri(
      scheme: 'https',
      host: _host,
      path: '/ul/v1$method',
      queryParameters: params,
    );
    return uri.toString();
  }

  /// Builds an encrypted request URI (payload + nonce) for a method other than
  /// `connect` (which has no shared secret yet).
  String _buildRequestUri(String method, Map<String, dynamic> payload) {
    final nonce = _randomBytes(24);
    final encrypted = _box!.encrypt(
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      nonce: nonce,
    );
    return _buildUri(method, {
      'redirect_link': '$_redirectBase?${_requestParam}=${method.substring(1)}',
      'dapp_encryption_public_key': _dappPublicKey,
      'nonce': base58encode(nonce),
      'payload': base58encode(encrypted.cipherText.asTypedList),
    });
  }

  Future<Map<String, String>> _launchAndWait(
    String uri, {
    required String kind,
  }) async {
    _pending = Completer<Map<String, String>>();
    debugPrint('[wc] launching $kind');
    try {
      final ok = await launchUrl(
        Uri.parse(uri),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        _pending = null;
        throw StateError('Could not open the wallet app');
      }
    } catch (e) {
      _pending = null;
      rethrow;
    }
    return _pending!.future.timeout(const Duration(seconds: 120));
  }

  Map<String, dynamic> _decrypt(Map<String, String> params) {
    final box = _box;
    if (box == null) throw StateError('No shared secret (not connected)');
    final data = params['data'];
    final nonce = params['nonce'];
    if (data == null || nonce == null) {
      throw StateError('Missing encrypted response data');
    }
    final plaintext = box.decrypt(
      pncl.ByteList(base58decode(data)),
      nonce: Uint8List.fromList(base58decode(nonce)),
    );
    return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
  }

  void _complete(Map<String, String> params) {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(params);
  }

  void _completeError(Object error) {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
    if (!_errorController.isClosed) _errorController.add(error);
  }

  void _clearState() {
    _keyPair = null;
    _box = null;
    _sessionToken = null;
    _address = null;
    _peerName = null;
    _wallet = null;
  }

  void _emitSession() {
    final s = session;
    if (s != null && !_sessionController.isClosed) {
      _sessionController.add(s);
    }
  }

  Future<void> _persist({required String remoteKey}) async {
    await _secureStorage.write(key: 'naji_dl.wallet', value: _wallet == SolanaWalletKind.solflare ? 'solflare' : 'phantom');
    await _secureStorage.write(key: 'naji_dl.private_key', value: base58encode(_keyPair!.asTypedList));
    await _secureStorage.write(key: 'naji_dl.remote_key', value: remoteKey);
    await _secureStorage.write(key: 'naji_dl.session_token', value: _sessionToken!);
    await _secureStorage.write(key: 'naji_dl.address', value: _address!);
    await _secureStorage.write(key: 'naji_dl.peer_name', value: _peerName!);
  }

  Future<void> _clearPersisted() async {
    for (final key in const [
      'naji_dl.wallet', 'naji_dl.private_key', 'naji_dl.remote_key',
      'naji_dl.session_token', 'naji_dl.address', 'naji_dl.peer_name',
    ]) {
      await _secureStorage.delete(key: key);
    }
  }

  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }
}
