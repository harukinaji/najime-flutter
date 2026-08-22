import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../theme/app_colors.dart';
import '../../utils/platform.dart';
import '../config/constants.dart';
import '../models/nft.dart';
import '../models/token_balance.dart';
import '../models/token_info.dart';
import '../models/transaction_record.dart';
import '../services/wallet_service.dart';
import '../state/app_state.dart';
import '../widgets/address_chip.dart';
import '../widgets/token_icon.dart';
import 'history/history_screen.dart';
import 'history/transaction_detail_screen.dart';
import 'nft_screen.dart';
import 'receive_screen.dart';
import 'send_screen.dart';
import 'solana_pay_screen.dart';
import 'connect_wallet_screen.dart';
import 'settings/settings_screen.dart';
import 'staking_screen.dart';
import 'swap_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final NumberFormat _solFormat = NumberFormat('#,##0.########');

  int? _lamports;
  bool _loadingBalance = true;
  bool _airdropping = false;
  List<TokenBalance> _tokens = const [];
  List<Nft> _nfts = const [];
  List<TransactionRecord> _history = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  ColorScheme get _cs => Theme.of(context).colorScheme;

  Future<void> _refresh() async {
    final state = context.read<AppState>();
    final wallet = state.wallet;
    if (wallet == null) return;

    setState(() => _loadingBalance = true);
    try {
      final lamports = await state.solana.getBalance(wallet.address);
      final tokens = await state.solana.getTokenBalances(
        wallet.address,
        known: state.tokenRegistry,
      );
      final history = await state.solana.getTransactionHistory(
        wallet.address,
        limit: 20,
      );
      final nfts = await state.solana.getNfts(wallet.address);
      if (mounted) {
        setState(() {
          _lamports = lamports;
          _tokens = tokens;
          _nfts = nfts;
          _history = history;
          _loadingBalance = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingBalance = false);
    }
  }

  Future<void> _airdrop() async {
    final state = context.read<AppState>();
    final wallet = state.wallet;
    if (wallet == null || _airdropping) return;

    setState(() => _airdropping = true);
    try {
      await state.solana.requestAirdrop(
        wallet.address,
        2 * WalletConfig.lamportsPerSol,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Airdrop completed: +2 SOL (devnet)')),
        );
      }
      await _refresh();
    } catch (e) {
      debugPrint('Airdrop failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Airdrop failed. Try again later.')),
        );
      }
    } finally {
      if (mounted) setState(() => _airdropping = false);
    }
  }

  void _copyAddress() {
    final wallet = context.read<AppState>().wallet;
    if (wallet == null) return;
    Clipboard.setData(ClipboardData(text: wallet.address));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Address copied')));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final wallet = state.wallet!;
    final sol = _lamports == null
        ? null
        : _lamports! / WalletConfig.lamportsPerSol;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              // On desktop keep the wallet a comfortable reading width and
              // center it; on mobile fill the whole screen.
              constraints: BoxConstraints(maxWidth: isDesktop ? 720 : 1200),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(context, wallet)),
                  SliverToBoxAdapter(child: _buildDevnetBanner()),
                  SliverToBoxAdapter(child: _buildBalanceCard(context, sol)),
                  SliverToBoxAdapter(child: _buildActions(context)),
                  SliverToBoxAdapter(child: _buildExternalWalletCard(context)),
                  SliverToBoxAdapter(child: _buildTokensSection(context)),
                  SliverToBoxAdapter(child: _buildNftSection(context)),
                  SliverToBoxAdapter(child: _buildHistoryHeader()),
                  if (_history.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyHistory(context),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList.builder(
                        itemCount: _history.length,
                        itemBuilder: (context, index) =>
                            _buildHistoryTile(context, _history[index]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Wallet wallet) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Naji Wallet',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              Text(
                WalletConfig.clusterName,
                style: TextStyle(color: _cs.primary, fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: Icon(Icons.settings_outlined, color: _cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildExternalWalletCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = context.read<AppState>();
    final session = state.walletConnectSession;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(
            session != null ? Icons.link : Icons.wallet,
            color: session != null ? cs.primary : cs.onSurfaceVariant,
          ),
          title: Text(
            session != null
                ? 'External wallet: ${session.peerName}'
                : 'Connect external wallet',
          ),
          subtitle: Text(
            session != null
                ? (session.primaryAccount ?? 'Accounts not provided')
                : 'Phantom, Solflare',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ConnectWalletScreen()),
          ),
        ),
      ),
    );
  }

  Widget _buildDevnetBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: Colors.orange.shade700,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'You are using Solana Devnet. All tokens and transactions have no real value.',
                style: TextStyle(color: Colors.orange.shade900, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, double? sol) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, Color(0xFF0F766E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Balance',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 8),
            if (_loadingBalance && sol == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            else
              Text(
                '${_solFormat.format(sol ?? 0)} SOL',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Flexible(
                  child: AddressChip(
                    address: context.read<AppState>().wallet!.address,
                    onCopy: _copyAddress,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Refresh',
                  onPressed: _refresh,
                  icon: _loadingBalance
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white24,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _WalletAction(
                  icon: Icons.arrow_downward_rounded,
                  label: 'Receive',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ReceiveScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _WalletAction(
                  icon: Icons.arrow_upward_rounded,
                  label: 'Send',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SendScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _WalletAction(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Swap',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SwapScreen()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _WalletAction(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Airdrop',
                  loading: _airdropping,
                  onTap: _airdrop,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _WalletAction(
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Pay',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SolanaPayScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _WalletAction(
                  icon: Icons.lock_outline_rounded,
                  label: 'Staking',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StakingScreen()),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTokensSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Tokens',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Add token',
                onPressed: _openAddTokenDialog,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(child: Column(children: _buildTokenRows())),
        ],
      ),
    );
  }

  Widget _buildNftSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'NFT',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (_nfts.isNotEmpty)
                Text(
                  '${_nfts.length}',
                  style: TextStyle(color: _cs.onSurfaceVariant, fontSize: 14),
                ),
              IconButton(
                tooltip: 'Open NFT collection',
                onPressed: _openNftCollection,
                icon: Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: _cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_nfts.isEmpty)
            Card(
              child: InkWell(
                onTap: _openNftCollection,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.image_not_supported_outlined,
                        color: _cs.onSurfaceVariant,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'You don\'t have any NFTs yet. Open collection.',
                          style: TextStyle(
                            color: _cs.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _nfts.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final nft = _nfts[index];
                  return GestureDetector(
                    onTap: _openNftCollection,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 100,
                            height: 100,
                            child: NftImage(nft: nft, fit: BoxFit.contain),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 100,
                          child: Text(
                            nft.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: _cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _openNftCollection() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NftScreen()),
    );
  }

  List<Widget> _buildTokenRows() {
    final state = context.read<AppState>();
    final registry = state.tokenRegistry;
    final rows = <Widget>[
      _TokenRow(
        mint: kSolToken.mint,
        symbol: kSolToken.symbol,
        name: kSolToken.name,
        amountText: _lamports == null
            ? '…'
            : _solFormat.format(_lamports! / WalletConfig.lamportsPerSol),
        onTap: () => _openSend(kSolToken),
      ),
    ];

    for (final token in _tokens) {
      final info = registry[token.mint];
      final isCustom = info?.isCustom ?? false;
      rows.add(
        _TokenRow(
          mint: token.mint,
          symbol: token.tokenSymbol,
          name: token.tokenName.isNotEmpty
              ? token.tokenName
              : (info?.name ?? token.tokenSymbol),
          amountText: _formatUiAmount(token.uiAmountString),
          isCustom: isCustom,
          onTap: () => _openSend(
            info != null
                ? TokenInfo(
                    mint: info.mint,
                    symbol: token.tokenSymbol.isNotEmpty
                        ? token.tokenSymbol
                        : info.symbol,
                    name: token.tokenName.isNotEmpty
                        ? token.tokenName
                        : info.name,
                    decimals: info.decimals,
                    isCustom: info.isCustom,
                    programId: token.programId,
                  )
                : TokenInfo(
                    mint: token.mint,
                    symbol: token.tokenSymbol,
                    name: token.tokenName.isNotEmpty
                        ? token.tokenName
                        : token.tokenSymbol,
                    decimals: token.decimals,
                    isCustom: true,
                    programId: token.programId,
                  ),
          ),
          onLongPress: isCustom ? () => _confirmRemoveToken(token.mint) : null,
        ),
      );
    }

    if (_loadingBalance && _lamports == null) {
      rows.add(
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    return rows;
  }

  void _openSend(TokenInfo token) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SendScreen(token: token)),
    );
  }

  Future<void> _confirmRemoveToken(String mint) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove token?'),
        content: const Text('Token will be removed from the list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AppState>().removeCustomToken(mint);
      _refresh();
    }
  }

  Future<void> _openAddTokenDialog() async {
    final mintController = TextEditingController();
    final symbolController = TextEditingController();
    final nameController = TextEditingController();
    final decimalsController = TextEditingController(text: '9');
    String? error;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Add token'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: mintController,
                  decoration: InputDecoration(
                    labelText: 'Mint address',
                    hintText: 'Coin address (base58)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: symbolController,
                  decoration: const InputDecoration(
                    labelText: 'Symbol',
                    hintText: 'USDC',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: 'USD Coin',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: decimalsController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Decimal places',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: TextStyle(color: _cs.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final mint = mintController.text.trim();
                final symbol = symbolController.text.trim().toUpperCase();
                final name = nameController.text.trim();
                final decimals = int.tryParse(decimalsController.text.trim());
                if (mint.length < 32 ||
                    !RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$').hasMatch(mint)) {
                  setDialogState(() => error = 'Invalid mint address');
                  return;
                }
                if (symbol.isEmpty) {
                  setDialogState(() => error = 'Enter token symbol');
                  return;
                }
                if (decimals == null || decimals < 0 || decimals > 19) {
                  setDialogState(
                    () => error = 'Invalid number of decimal places',
                  );
                  return;
                }
                final state = context.read<AppState>();
                if (state.tokenRegistry.containsKey(mint)) {
                  setDialogState(
                    () => error = 'This token is already in the list',
                  );
                  return;
                }
                state.addCustomToken(
                  TokenInfo(
                    mint: mint,
                    symbol: symbol,
                    name: name.isEmpty ? symbol : name,
                    decimals: decimals,
                    isCustom: true,
                  ),
                );
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    mintController.dispose();
    symbolController.dispose();
    nameController.dispose();
    decimalsController.dispose();

    if (result == true && mounted) _refresh();
  }

  String _formatUiAmount(String value) {
    if (!value.contains('.')) return value;
    var s = value.replaceAll(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  Widget _buildHistoryHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          const Text(
            'Transaction history',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (_history.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              ),
              child: const Text('All'),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyHistory(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history,
            size: 56,
            color: _cs.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text(
            'No transactions yet.\nGet SOL via Airdrop.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(BuildContext context, TransactionRecord record) {
    final isSuccess = record.isSuccess;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (isSuccess ? Colors.green : _cs.error).withValues(
            alpha: 0.15,
          ),
          child: Icon(
            isSuccess ? Icons.check : Icons.error_outline,
            color: isSuccess ? Colors.green : _cs.error,
          ),
        ),
        title: Text(
          record.signature.length > 20
              ? '${record.signature.substring(0, 10)}...${record.signature.substring(record.signature.length - 8)}'
              : record.signature,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
        ),
        subtitle: Text(
          record.date != null
              ? DateFormat('dd.MM.yyyy HH:mm').format(record.date!)
              : 'Waiting...',
          style: TextStyle(fontSize: 12, color: _cs.onSurfaceVariant),
        ),
        trailing: isSuccess
            ? Icon(Icons.chevron_right, color: _cs.onSurfaceVariant)
            : Text('error', style: TextStyle(color: _cs.error, fontSize: 12)),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TransactionDetailScreen(record: record),
          ),
        ),
      ),
    );
  }
}

class _TokenRow extends StatelessWidget {
  const _TokenRow({
    required this.mint,
    required this.symbol,
    required this.name,
    required this.amountText,
    required this.onTap,
    this.onLongPress,
    this.isCustom = false,
  });

  final String mint;
  final String symbol;
  final String name;
  final String amountText;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isCustom;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: TokenIcon(mint: mint, symbol: symbol),
      title: Text(symbol, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCustom)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.star, size: 14, color: cs.onSurfaceVariant),
            ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                amountText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// A proper action button: circular primary icon button with a label beneath,
/// matching the messenger's Material 3 look.
class _WalletAction extends StatelessWidget {
  const _WalletAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 56,
          child: IconButton.filled(
            onPressed: loading ? null : onTap,
            iconSize: 24,
            tooltip: label,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              shape: const CircleBorder(),
            ),
            icon: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Icon(icon, size: 24),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
