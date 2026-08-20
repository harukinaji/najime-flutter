import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/api_service.dart';
import '../models/token_info.dart';
import '../services/secure_storage_service.dart';
import '../services/solana_service.dart';
import '../services/wallet_service.dart';
import '../services/walletconnect_service.dart';

class AppState extends ChangeNotifier {
  /// Global wallet state shared by the messenger and every mini-app, so the
  /// connected wallet is bound to the profile rather than to a single screen.
  static final AppState instance = AppState._();

  /// Creates a standalone instance (used only for tests).
  @visibleForTesting
  AppState({
    SecureStorageService? storage,
    SolanaService? solana,
  })  : _storage = storage ?? SecureStorageService(),
        _solana = solana ?? SolanaService();

  AppState._()
      : _storage = SecureStorageService(),
        _solana = SolanaService();

  bool _restored = false;

  final SecureStorageService _storage;
  final SolanaService _solana;

  Wallet? _wallet;
  bool _loading = true;
  List<TokenInfo> _customTokens = const [];

  Wallet? get wallet => _wallet;
  bool get loading => _loading;
  bool get isAuthenticated => _wallet != null;

  SolanaService get solana => _solana;
  SecureStorageService get storage => _storage;

  // ── WalletConnect (external wallets) ────────────────────────────────

  WalletConnectClient? _wc;
  bool _wcLoading = false;

  /// Lazily-created external-wallet client.
  WalletConnectClient? get walletConnectClient => _wc;

  /// True while a pairing URI is being prepared.
  bool get walletConnectLoading => _wcLoading;

  /// The active WalletConnect session, if the user connected an external wallet.
  WalletConnectSession? get walletConnectSession => _wc?.session;

  List<TokenInfo> get customTokens => _customTokens;

  /// Combines built-in and user-added tokens, keyed by mint address.
  Map<String, TokenInfo> get tokenRegistry => {
        for (final token in [...kKnownTokens, ..._customTokens]) token.mint: token,
      };

  Future<void> _loadCustomTokens() async {
    _customTokens = await _storage.getCustomTokens();
    notifyListeners();
  }

  /// Loads a saved wallet from secure storage on app start. Idempotent: the
  /// inherent state is restored only once for the global [AppState.instance].
  Future<void> restoreSession() async {
    if (_restored) return;
    _restored = true;
    _loading = true;
    notifyListeners();
    try {
      final seed = await _storage.getSeedPhrase();
      if (seed != null && seed.isNotEmpty) {
        _wallet = await Wallet.fromMnemonic(seed);
      } else {
        final privateKey = await _storage.getPrivateKey();
        if (privateKey != null && privateKey.isNotEmpty) {
          _wallet = await Wallet.fromPrivateKey(privateKey);
        }
      }
    } catch (_) {
      _wallet = null;
    }
    await _loadCustomTokens();
    _loading = false;
    notifyListeners();
  }

  /// Adds a user-defined token to the tracked list.
  Future<void> addCustomToken(TokenInfo token) async {
    _customTokens = [..._customTokens, token];
    await _storage.saveCustomTokens(_customTokens);
    notifyListeners();
  }

  /// Removes a user-defined token from the tracked list.
  Future<void> removeCustomToken(String mint) async {
    _customTokens = _customTokens.where((t) => t.mint != mint).toList();
    await _storage.saveCustomTokens(_customTokens);
    notifyListeners();
  }

  /// Creates a brand new wallet and stores it.
  Future<Wallet> createWallet() async {
    final wallet = await Wallet.generate();
    await _storage.saveWallet(mnemonic: wallet.mnemonic);
    _wallet = wallet;
    notifyListeners();
    return wallet;
  }

  /// Imports an existing wallet from a mnemonic phrase.
  Future<Wallet> importFromMnemonic(String mnemonic) async {
    final wallet = await Wallet.fromMnemonic(mnemonic);
    await _storage.saveWallet(mnemonic: wallet.mnemonic);
    _wallet = wallet;
    notifyListeners();
    return wallet;
  }

  /// Imports an existing wallet from a base58 private key.
  Future<Wallet> importFromPrivateKey(String privateKey) async {
    final wallet = await Wallet.fromPrivateKey(privateKey);
    await _storage.saveWallet(privateKey: privateKey);
    _wallet = wallet;
    notifyListeners();
    return wallet;
  }

  /// Returns the base58-encoded private key of the current wallet.
  Future<String> getPrivateKey() async {
    final wallet = _wallet;
    if (wallet == null) throw StateError('No wallet');
    final seed = await _storage.getSeedPhrase();
    if (seed != null && seed.isNotEmpty) {
      return wallet.encodePrivateKey();
    }
    final pk = await _storage.getPrivateKey();
    if (pk != null) return pk;
    return wallet.encodePrivateKey();
  }

  Future<void> clearWallet() async {
    await _storage.clear();
    _wallet = null;
    notifyListeners();
  }

  // ── WalletConnect (external wallet) operations ─────────────────────

  /// Ensures the direct deep-link client is ready and connects the selected
  /// external wallet (Phantom/Solflare). When [wallet] is omitted, shows a
  /// bottom sheet so the user can pick one.
  Future<void> connectExternalWallet(
    BuildContext context, {
    SolanaWalletKind? wallet,
  }) async {
    final kind = wallet ?? await _pickWallet(context);
    if (kind == null) return;
    final client = await _ensureWalletConnectClient();
    _wcLoading = true;
    notifyListeners();
    try {
      if (!context.mounted) return;
      await client.ensureInitialized(context);
      await client.connect(kind);
      // Bind the external wallet address to this account on the server. The
      // backend rejects (409) when the address is already bound to another
      // account — in that case tear down the just-established session.
      final address = client.session?.primaryAccount;
      if (address != null) {
        final link = await ApiService.linkWalletAccount(walletAddress: address);
        if (!link.success) {
          await client.disconnect();
          throw StateError(
            link.message ?? 'This wallet is already linked to another account',
          );
        }
      }
    } finally {
      _wcLoading = false;
      notifyListeners();
    }
  }

  Future<SolanaWalletKind?> _pickWallet(BuildContext context) {
    return showModalBottomSheet<SolanaWalletKind>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Connect wallet',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: const Text('Phantom'),
              onTap: () => Navigator.pop(ctx, SolanaWalletKind.phantom),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: const Text('Solflare'),
              onTap: () => Navigator.pop(ctx, SolanaWalletKind.solflare),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Routes a deep-link return URL (native scheme / app link) into AppKit so
  /// Phantom/Solflare requests can complete after the wallet redirects back.
  Future<bool> dispatchWalletLink(String url) async {
    final client = _wc;
    if (client == null) return false;
    return client.dispatchLink(url);
  }

  /// The direct deep-link client has no external configuration requirement.
  Future<bool> isWalletConnectConfigured() async => true;

  /// Requests the connected external wallet to sign [message] (raw bytes).
  Future<WalletConnectSignResult> signWithWalletConnect(
    List<int> message,
  ) async {
    final client = _wc;
    if (client == null) {
      throw StateError('No WalletConnect session');
    }
    return client.signMessage(
      message is Uint8List ? message : Uint8List.fromList(message),
    );
  }

  /// Disconnects the active external-wallet session.
  Future<void> disconnectWalletConnect() async {
    final client = _wc;
    if (client == null) return;
    await client.disconnect();
    _wc = null;
    notifyListeners();
  }

  /// Restores a previously persisted Phantom/Solflare session without opening
  /// a connect UI. The deep-link session is stored in shared prefs; calling
  /// [WalletConnectClient.ensureInitialized] reloads it so
  /// [walletConnectSession] is non-null again after an app restart. Idempotent.
  ///
  /// Returns true when a session is active afterwards.
  Future<bool> restoreExternalWalletSession(BuildContext context) async {
    final client = await _ensureWalletConnectClient();
    if (!client.isInitialized) {
      try {
        await client.ensureInitialized(context);
      } catch (e) {
        debugPrint('[wc] restore session init failed: $e');
        // Non-fatal: caller can still fall back to the built-in wallet.
      }
    }
    final restored = client.session != null;
    if (restored) notifyListeners();
    return restored;
  }

  Future<WalletConnectClient> _ensureWalletConnectClient() async {
    if (_wc != null) return _wc!;
    var config = await ApiService.fetchWalletConnectConfig();
    config ??= const WalletConnectConfig(
      relayUrl: '',
      metadata: WalletConnectMetadata(
        name: 'Najime',
        description: 'Najime Wallet',
        url: 'https://najime.app',
        icons: [],
        redirectNative: 'najime://',
        redirectUniversal: 'https://najime.app',
      ),
    );
    final client = WalletConnectClient(config: config);
    _wc = client;
    client.onSessionCreated.listen((_) => notifyListeners());
    client.onSessionDeleted.listen((_) => notifyListeners());
    client.onError.listen((_) => notifyListeners());
    return client;
  }
}
