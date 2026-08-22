import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../theme/app_colors.dart';
import '../../../utils/platform.dart';
import '../services/walletconnect_service.dart';
import '../state/app_state.dart';

/// Connects an external Solana wallet (Phantom, Solflare) through the direct
/// E2E-encrypted deep-link protocol — no WalletConnect relay / Reown involved.
class ConnectWalletScreen extends StatefulWidget {
  const ConnectWalletScreen({super.key});

  @override
  State<ConnectWalletScreen> createState() => _ConnectWalletScreenState();
}

class _ConnectWalletScreenState extends State<ConnectWalletScreen> {
  String? _error;
  bool _signing = false;
  String? _signaturePreview;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _connect(SolanaWalletKind wallet) async {
    setState(() {
      _error = null;
      _signaturePreview = null;
    });
    try {
      await context.read<AppState>().connectExternalWallet(
        context,
        wallet: wallet,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _testSign() async {
    setState(() {
      _signing = true;
      _signaturePreview = null;
    });
    try {
      final message =
          'Najime Wallet verification\nTimestamp: '
          '${DateTime.now().millisecondsSinceEpoch}';
      final result = await context.read<AppState>().signWithWalletConnect(
        message.codeUnits,
      );
      if (!mounted) return;
      setState(() {
        _signing = false;
        _signaturePreview = result.publicKey;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Message signed')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _signing = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _disconnect() async {
    await context.read<AppState>().disconnectWalletConnect();
    if (!mounted) return;
    setState(() {
      _error = null;
      _signaturePreview = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    final session = state.walletConnectSession;

    return Scaffold(
      appBar: AppBar(title: const Text('Connect wallet')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isDesktop ? 560 : 1200),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: session != null
                  ? _buildSession(context, cs, session)
                  : _buildPairing(context, cs, state),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPairing(BuildContext context, ColorScheme cs, AppState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        if (_error != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.error),
            ),
          ),
        ],
        Text(
          'Connect an external wallet (Phantom, Solflare).',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: state.walletConnectLoading
              ? null
              : () => _connect(SolanaWalletKind.phantom),
          icon: state.walletConnectLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.account_balance_wallet),
          label: const Text('Phantom'),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: state.walletConnectLoading
              ? null
              : () => _connect(SolanaWalletKind.solflare),
          icon: const Icon(Icons.account_balance_wallet),
          label: const Text('Solflare'),
        ),
        const SizedBox(height: 20),
        Text(
          'The connection is secure: secret keys never leave your wallet, '
          'all signatures are confirmed in the wallet app.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildSession(
    BuildContext context,
    ColorScheme cs,
    WalletConnectSession session,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, Color(0xFF0F766E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const Icon(Icons.link, color: Colors.white, size: 32),
              const SizedBox(height: 8),
              const Text(
                'Wallet connected',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                session.peerName,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connected account',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  session.primaryAccount ?? 'Accounts not provided',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Signing happens in your wallet — '
                        'the private key is not transmitted.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_signaturePreview != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Message signed',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.check_circle, size: 16, color: cs.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _signaturePreview!,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              style: TextStyle(fontSize: 13, color: cs.error),
            ),
          ),
        FilledButton.icon(
          onPressed: _signing ? null : _testSign,
          icon: _signing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.edit_note),
          label: Text(
            _signing ? 'Waiting for signature…' : 'Sign test message',
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _disconnect,
          icon: const Icon(Icons.link_off, size: 18),
          label: const Text('Disconnect wallet'),
        ),
      ],
    );
  }
}
