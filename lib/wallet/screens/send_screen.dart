import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:solana/solana.dart';

import '../models/token_balance.dart';
import '../models/token_info.dart';
import '../state/app_state.dart';
import '../widgets/token_icon.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key, this.token});

  /// The token to send by default; null means SOL.
  final TokenInfo? token;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();

  bool _loadingAssets = true;
  bool _sending = false;
  String? _error;

  List<TokenInfo> _assets = const [];
  Map<String, int> _rawBalances = const {};
  TokenInfo _selected = kSolToken;

  @override
  void initState() {
    super.initState();
    _selected = widget.token ?? kSolToken;
    _loadAssets();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    final state = context.read<AppState>();
    final wallet = state.wallet;
    if (wallet == null) return;

    try {
      final lamports = await state.solana.getBalance(wallet.address);
      final tokenBalances = await state.solana.getTokenBalances(
        wallet.address,
        known: state.tokenRegistry,
      );
      if (!mounted) return;

      final registry = state.tokenRegistry;
      final assets = <TokenInfo>[
        kSolToken,
        for (final t in tokenBalances) _assetFromBalance(t, registry),
      ];
      final balances = <String, int>{
        kSolToken.mint: lamports,
        for (final t in tokenBalances) t.mint: t.rawAmount,
      };

      setState(() {
        _assets = assets;
        _rawBalances = balances;
        if (!assets.any((a) => a.mint == _selected.mint)) {
          _selected = kSolToken;
        }
        _loadingAssets = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingAssets = false);
    }
  }

  void _pasteAddress() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && mounted) {
      setState(() => _addressController.text = data!.text!.trim());
    }
  }

  int get _selectedDecimals => _selected.decimals;

  TokenInfo _assetFromBalance(TokenBalance t, Map<String, TokenInfo> registry) {
    final known = registry[t.mint];
    return TokenInfo(
      mint: t.mint,
      symbol: t.tokenSymbol.isNotEmpty
          ? t.tokenSymbol
          : (known?.symbol ?? t.tokenSymbol),
      name: t.tokenName.isNotEmpty
          ? t.tokenName
          : (known?.name ?? t.tokenSymbol),
      decimals: known?.decimals ?? t.decimals,
      isCustom: known?.isCustom ?? true,
      programId: t.programId,
    );
  }

  int get _selectedBalance => _rawBalances[_selected.mint] ?? 0;

  String _formatRaw(int raw) {
    final value = raw / pow(10, _selectedDecimals);
    var s = value.toStringAsFixed(_selectedDecimals);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Future<void> _send() async {
    final address = _addressController.text.trim();
    final amountText = _amountController.text.trim().replaceAll(',', '.');
    final amount = double.tryParse(amountText);

    if (address.isEmpty) {
      setState(() => _error = 'Enter recipient address');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    if (address.length < 32 ||
        !RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$').hasMatch(address)) {
      setState(() => _error = 'Invalid Solana address');
      return;
    }

    final rawAmount = (amount * pow(10, _selectedDecimals)).round();
    if (rawAmount <= 0) {
      setState(() => _error = 'Amount is too small');
      return;
    }

    if (rawAmount > _selectedBalance) {
      setState(() {
        _error =
            'Insufficient funds. Available: ${_formatRaw(_selectedBalance)} ${_selected.symbol}';
      });
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final state = context.read<AppState>();
      final wallet = state.wallet!;
      final memo = _memoController.text.trim().isEmpty
          ? null
          : _memoController.text.trim();

      final String signature;
      if (_selected.isSol) {
        signature = await state.solana.transfer(
          wallet: wallet,
          destination: address,
          lamports: rawAmount,
          memo: memo,
        );
      } else {
        signature = await state.solana.transferToken(
          wallet: wallet,
          mint: _selected.mint,
          destination: address,
          amount: rawAmount,
          memo: memo,
          programId: _selected.programId,
        );
      }

      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
            title: const Text('Transfer sent!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Transaction confirmed on the network.'),
                const SizedBox(height: 12),
                SelectableText(
                  signature,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.of(context).pop(true);
      }
    } on NoAssociatedTokenAccountException {
      if (mounted) {
        setState(() {
          _sending = false;
          _error =
              'Recipient doesn\'t have an account for ${_selected.symbol} yet. Send them some SOL first.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Send error: ${e.toString().split('\n').first}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTokenSelector(context),
              const SizedBox(height: 16),
              TextField(
                controller: _addressController,
                decoration: InputDecoration(
                  labelText: 'Recipient address',
                  hintText: 'Solana address (base58)',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste, size: 20),
                    onPressed: _pasteAddress,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount (${_selected.symbol})',
                  hintText: '0.1',
                  prefixIcon: const Icon(Icons.attach_money),
                  suffixText: _selectedBalance > 0
                      ? 'available: ${_formatRaw(_selectedBalance)}'
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _memoController,
                decoration: const InputDecoration(
                  labelText: 'Memo (optional)',
                  hintText: 'Comment on the transfer',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 28),
              FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: (_sending || _loadingAssets) ? null : _send,
                child: _sending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Send', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTokenSelector(BuildContext context) {
    if (_loadingAssets) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Loading tokens...'),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selected.mint,
            isExpanded: true,
            icon: const Icon(Icons.arrow_drop_down),
            items: [
              for (final asset in _assets)
                DropdownMenuItem(
                  value: asset.mint,
                  child: Row(
                    children: [
                      TokenIcon(
                        mint: asset.mint,
                        symbol: asset.symbol,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          asset.symbol,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          asset.name,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatRawFor(asset),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (mint) {
              if (mint == null) return;
              setState(() {
                _selected = _assets.firstWhere((a) => a.mint == mint);
                _error = null;
              });
            },
          ),
        ),
      ),
    );
  }

  String _formatRawFor(TokenInfo asset) {
    final raw = _rawBalances[asset.mint] ?? 0;
    final value = raw / pow(10, asset.decimals);
    var s = value.toStringAsFixed(asset.decimals);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    }
    return s;
  }
}
