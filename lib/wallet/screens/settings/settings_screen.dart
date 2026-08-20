import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/api_service.dart';
import '../../../data/auth_state.dart';
import '../../../data/lock_service.dart';
import '../../state/app_state.dart';
import '../connect_wallet_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _accountLoading = true;
  bool _walletBound = false;
  String? _boundAddress;
  String? _accountError;

  @override
  void initState() {
    super.initState();
    _loadAccountBind();
  }

  Future<void> _loadAccountBind() async {
    if (!AuthState.instance.isAuthenticated) {
      if (mounted) {
        setState(() {
          _accountLoading = false;
          _walletBound = false;
          _boundAddress = null;
        });
      }
      return;
    }
    setState(() => _accountLoading = true);
    final result = await ApiService.getConnectedAccounts();
    if (!mounted) return;
    setState(() {
      _accountLoading = false;
      if (result.success) {
        _accountError = null;
        _walletBound = result.wallet?['connected'] == true;
        _boundAddress = result.wallet?['address'] as String?;
      } else {
        _accountError = result.message;
      }
    });
  }

  Future<void> _bindToAccount() async {
    final wallet = context.read<AppState>().wallet;
    if (wallet == null) return;
    if (!AuthState.instance.isAuthenticated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to your account first')),
        );
      }
      return;
    }
    setState(() => _accountLoading = true);
    final result = await ApiService.linkWalletAccount(
      walletAddress: wallet.address,
    );
    if (!mounted) return;
    setState(() => _accountLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success
            ? 'Wallet linked to account'
            : (result.message ?? 'Failed to link wallet')),
      ),
    );
    if (result.success) await _loadAccountBind();
  }

  Future<void> _unbindFromAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unlink wallet?'),
        content: const Text(
          'The wallet\'s public key will be removed from the account profile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _accountLoading = true);
    final result = await ApiService.unlinkWalletAccount();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success
            ? 'Wallet unlinked from account'
            : (result.message ?? 'Failed to unlink wallet')),
      ),
    );
    await _loadAccountBind();
  }

  Future<bool> _requireAuth() async {
    final lock = LockService.instance;
    if (!lock.isEnabled) return true;
    if (lock.canUseBiometric) {
      return await lock.authenticateWithBiometric();
    }
    return await _showPinDialog();
  }

  Future<bool> _showPinDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter PIN'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'PIN code'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final ok = await LockService.instance.verifyPin(controller.text);
              if (ctx.mounted) Navigator.pop(ctx, ok);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result ?? false;
  }

  Future<String?> _getMnemonic() async {
    final state = context.read<AppState>();
    final seed = await state.storage.getSeedPhrase();
    if (seed != null && seed.isNotEmpty) return seed;
    return null;
  }

  Future<void> _showPhrase() async {
    if (!await _requireAuth()) return;
    final mnemonic = await _getMnemonic();
    if (mnemonic == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This wallet was imported via private key (seed phrase unavailable)'),
          ),
        );
      }
      return;
    }
    if (mounted) {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Seed phrase'),
          content: SelectableText(
            mnemonic,
            style: const TextStyle(fontFamily: 'monospace', height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showPrivateKey() async {
    if (!await _requireAuth()) return;
    final state = context.read<AppState>();
    final key = await state.getPrivateKey();
    if (mounted) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Private key'),
          content: SelectableText(
            key,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _deleteWallet() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete wallet?'),
        content: const Text(
          'The wallet will be deleted from this device. '
          'If you don\'t have a backup of your seed phrase, funds will be lost forever.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AppState>().clearWallet();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.read<AppState>().wallet!;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet),
                title: const Text('Address'),
                subtitle: Text(
                  wallet.address,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: wallet.address));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Address copied')),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            _buildAccountCard(context),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.wallet),
                title: const Text('External wallet (WalletConnect)'),
                subtitle: const Text('Phantom, Solflare, Backpack'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ConnectWalletScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.notes),
                    title: const Text('Show seed phrase'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showPhrase,
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.key),
                    title: const Text('Show private key'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showPrivateKey,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Icon(Icons.warning, color: Colors.redAccent),
                title: const Text(
                  'Delete wallet',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: _deleteWallet,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!AuthState.instance.isAuthenticated) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.link_off, color: cs.onSurfaceVariant),
          title: const Text('Link to account'),
          subtitle: const Text('Sign in to your account to link the wallet'),
        ),
      );
    }

    if (_accountLoading) {
      return Card(
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
      );
    }

    if (_walletBound && _boundAddress != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.link, color: cs.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Linked to account',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _boundAddress!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _unbindFromAccount,
                icon: const Icon(Icons.link_off, size: 18),
                label: const Text('Unlink'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link, color: cs.onSurfaceVariant, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Link to account',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'The wallet\'s public key will be saved in the account profile.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            if (_accountError != null) ...[
              const SizedBox(height: 8),
              Text(
                _accountError!,
                style: TextStyle(fontSize: 13, color: cs.error),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _bindToAccount,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Link'),
            ),
          ],
        ),
      ),
    );
  }
}
