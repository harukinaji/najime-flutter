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
          const SnackBar(content: Text('Сначала войдите в аккаунт')),
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
            ? 'Кошелёк привязан к аккаунту'
            : (result.message ?? 'Не удалось привязать кошелёк')),
      ),
    );
    if (result.success) _loadAccountBind();
  }

  Future<void> _unbindFromAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Отвязать кошелёк?'),
        content: const Text(
          'Публичный ключ кошелька будет удалён из профиля аккаунта.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Отвязать'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _accountLoading = true);
    final result = await ApiService.unlinkWalletAccount();
    if (!mounted) return;
    setState(() => _accountLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success
            ? 'Кошелёк отвязан от аккаунта'
            : (result.message ?? 'Не удалось отвязать кошелёк')),
      ),
    );
    if (result.success) _loadAccountBind();
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
        title: const Text('Введите PIN'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'PIN-код'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
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
            content: Text('Этот кошелёк был импортирован по приватному ключу (seed-фраза недоступна)'),
          ),
        );
      }
      return;
    }
    if (mounted) {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Seed-фраза'),
          content: SelectableText(
            mnemonic,
            style: const TextStyle(fontFamily: 'monospace', height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
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
          title: const Text('Приватный ключ'),
          content: SelectableText(
            key,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
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
        title: const Text('Удалить кошелёк?'),
        content: const Text(
          'Кошелёк будет удалён с этого устройства. '
          'Если у вас нет резервной копии seed-фразы, средства будут потеряны навсегда.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
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
      appBar: AppBar(title: const Text('Настройки')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet),
                title: const Text('Адрес'),
                subtitle: Text(
                  wallet.address,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: wallet.address));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Адрес скопирован')),
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
                title: const Text('Внешний кошелёк (WalletConnect)'),
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
                    title: const Text('Показать seed-фразу'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showPhrase,
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.key),
                    title: const Text('Показать приватный ключ'),
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
                  'Удалить кошелёк',
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
          title: const Text('Привязать к аккаунту'),
          subtitle: const Text('Войдите в аккаунт, чтобы привязать кошелёк'),
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
                    'Привязано к аккаунту',
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
                label: const Text('Отвязать'),
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
                  'Привязать к аккаунту',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Публичный ключ кошелька будет сохранён в профиле аккаунта.',
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
              label: const Text('Привязать'),
            ),
          ],
        ),
      ),
    );
  }
}
