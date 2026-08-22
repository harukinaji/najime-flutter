import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/token_info.dart';
import '../services/raydium_service.dart';
import '../state/app_state.dart';
import '../widgets/token_icon.dart';

class SwapScreen extends StatefulWidget {
  const SwapScreen({super.key});

  @override
  State<SwapScreen> createState() => _SwapScreenState();
}

class _SwapScreenState extends State<SwapScreen> {
  final TextEditingController _amountController = TextEditingController();
  final NumberFormat _fmt = NumberFormat('#,##0.#########');

  RaydiumService? _raydium;
  List<TokenInfo> _tokens = const [];
  TokenInfo _fromToken = kSolToken;
  TokenInfo? _toToken;

  RaydiumCpmmPool? _pool;
  RaydiumAmmConfig? _config;
  RaydiumQuote? _quote;
  String? _error;
  String? _signature;
  bool _loadingPool = false;
  bool _swapping = false;

  int _slippageBps = 100; // 1%

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final state = context.read<AppState>();
    final known = state.tokenRegistry.values.where((t) => !t.isSol).toList();
    setState(() {
      _tokens = [kSolToken, ...known];
      _toToken = known.isNotEmpty ? known.first : kSolToken;
    });
    await _discoverPool();
  }

  /// Finds the most liquid enabled CPMM pool for the current pair.
  Future<void> _discoverPool() async {
    final state = context.read<AppState>();
    final raydium = _raydium ??= RaydiumService(state.solana.client);
    final to = _toToken;
    setState(() {
      _loadingPool = true;
      _pool = null;
      _config = null;
      _quote = null;
      _error = null;
    });

    try {
      var pools = await raydium.findPools(
        mintA: _fromToken.isSol ? TokenInfo.solMint : _fromToken.mint,
        mintB: to == null || to.isSol ? null : to.mint,
      );
      pools = pools.where((p) => p.swapEnabled).toList();
      if (pools.isEmpty) {
        if (mounted)
          setState(() => _error = 'Pool for this pair not found on devnet.');
      } else {
        final pool = await _firstWithLiquidity(raydium, pools);
        final config = await raydium.getAmmConfig(pool);
        if (mounted) {
          setState(() {
            _pool = pool;
            _config = config;
          });
        }
        await _refreshQuote();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to find pool: $e');
    } finally {
      if (mounted) setState(() => _loadingPool = false);
    }
  }

  Future<RaydiumCpmmPool> _firstWithLiquidity(
    RaydiumService raydium,
    List<RaydiumCpmmPool> pools,
  ) async {
    // Prefer pools that are currently open and have reserves.
    RaydiumCpmmPool? best;
    int bestLiquidity = 0;
    for (final p in pools.take(15)) {
      try {
        final bal = await raydium.getVaultBalances(p);
        final liquidity = bal.token0 + bal.token1;
        if (best == null || liquidity > bestLiquidity) {
          best = p;
          bestLiquidity = liquidity;
        }
      } catch (_) {}
    }
    return best ?? pools.first;
  }

  Future<void> _refreshQuote() async {
    final pool = _pool;
    final config = _config;
    final from = _fromToken;
    if (pool == null || config == null) return;

    final inputMint = from.isSol ? TokenInfo.solMint : from.mint;
    final amountIn = _parseAmount(_amountController.text, from.decimals);
    if (amountIn == null) {
      if (mounted) setState(() => _quote = null);
      return;
    }

    try {
      final quote = await _raydium!.quote(
        pool: pool,
        config: config,
        inputMint: inputMint,
        amountIn: amountIn,
        slippageBps: _slippageBps,
      );
      if (mounted) {
        setState(() {
          _quote = quote;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Calculation error: $e');
    }
  }

  int? _parseAmount(String text, int decimals) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final dec = Decimal.tryParse(t);
    if (dec == null || dec <= Decimal.zero) return null;
    final scaled = dec * Decimal.fromInt(_pow10(decimals));
    if (!scaled.isInteger) return null;
    final big = scaled.toBigInt();
    if (big <= BigInt.zero) return null;
    if (big > BigInt.from(1 << 62)) return null;
    return big.toInt();
  }

  Future<void> _doSwap() async {
    final state = context.read<AppState>();
    final wallet = state.wallet;
    final pool = _pool;
    final config = _config;
    final quote = _quote;
    if (wallet == null ||
        pool == null ||
        config == null ||
        quote == null ||
        _swapping)
      return;

    setState(() {
      _swapping = true;
      _error = null;
      _signature = null;
    });
    try {
      final signature = await _raydium!.swap(
        wallet: wallet,
        pool: pool,
        config: config,
        quote: quote,
      );
      if (mounted) {
        setState(() => _signature = signature);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Swap sent: ${_short(signature)}')),
        );
      }
    } catch (e) {
      debugPrint('Swap failed: $e');
      if (mounted) setState(() => _error = 'Swap failed: $e');
    } finally {
      if (mounted) setState(() => _swapping = false);
    }
  }

  Future<void> _pickFrom() async {
    final picked = await _pickToken(_tokens, _fromToken);
    if (picked != null && mounted) {
      if (_toToken == null) {
        setState(() {
          _toToken = _fromToken;
          _fromToken = picked;
          _amountController.clear();
        });
        await _discoverPool();
        return;
      }
      if (picked.mint == _toToken!.mint) {
        setState(() => _toToken = _fromToken);
      }
      setState(() {
        _fromToken = picked;
        _amountController.clear();
      });
      await _discoverPool();
    }
  }

  Future<void> _pickTo() async {
    final to = _toToken;
    if (to == null) return;
    final picked = await _pickToken(_tokens, to);
    if (picked != null && mounted) {
      if (picked.mint == _fromToken.mint) {
        setState(() => _fromToken = to);
      }
      setState(() => _toToken = picked);
      await _discoverPool();
    }
  }

  Future<TokenInfo?> _pickToken(List<TokenInfo> tokens, TokenInfo current) {
    return showModalBottomSheet<TokenInfo>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          children: tokens.map((t) {
            final checked = t.mint == current.mint;
            return ListTile(
              leading: TokenIcon(mint: t.mint, symbol: t.symbol),
              title: Text(t.symbol),
              subtitle: Text(t.name),
              trailing: checked
                  ? const Icon(Icons.check, color: Colors.greenAccent)
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(t),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _short(String s) => s.length > 24
      ? '${s.substring(0, 10)}...${s.substring(s.length - 8)}'
      : s;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Swap (Raydium)')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              _buildFromCard(),
              const SizedBox(height: 12),
              _buildToCard(),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                enabled: !_swapping,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => _refreshQuote(),
                decoration: InputDecoration(
                  labelText: 'Amount (${_fromToken.symbol})',
                  prefixIcon: const Icon(Icons.input),
                  border: const OutlineInputBorder(),
                  filled: true,
                ),
              ),
              const SizedBox(height: 16),
              _buildQuoteCard(),
              const SizedBox(height: 8),
              _buildSlippRow(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: (_quote == null || _swapping) ? null : _doSwap,
                icon: _swapping
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.swap_horiz),
                label: Text(_swapping ? 'Swap...' : 'Swap'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              if (_signature != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(
                    'Signature: $_signature',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.greenAccent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFromCard() {
    return _tokenCard(
      label: 'Input',
      token: _fromToken,
      onTap: _swapping ? () {} : _pickFrom,
    );
  }

  Widget _buildToCard() {
    final to = _toToken;
    if (to == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF16182B),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text('Loading...', style: TextStyle(color: Colors.white38)),
        ),
      );
    }
    return _tokenCard(
      label: 'Output',
      token: to,
      onTap: _swapping ? () {} : _pickTo,
    );
  }

  Widget _tokenCard({
    required String label,
    required TokenInfo token,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF16182B),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            TokenIcon(mint: token.mint, symbol: token.symbol),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    token.symbol,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    token.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildQuoteCard() {
    if (_loadingPool) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    final quote = _quote;
    if (quote == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              'Enter an amount to calculate',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }
    final inUi = quote.amountIn / _pow10(quote.inputDecimals);
    final outUi = quote.amountOut / _pow10(quote.outputDecimals);
    final feeUi = quote.fee / _pow10(quote.inputDecimals);
    final minOutUi = quote.minimumAmountOut / _pow10(quote.outputDecimals);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_fmt.format(inUi)} ${_fromToken.symbol} → '
              '${_fmt.format(outUi)} ${_toToken!.symbol}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            _quoteRow('Fee', '${_fmt.format(feeUi)} ${_fromToken.symbol}'),
            _quoteRow(
              'Price (impact)',
              '${(quote.priceImpactBps / 100).toStringAsFixed(2)}%',
            ),
            _quoteRow(
              'Minimum output',
              '${_fmt.format(minOutUi)} ${_toToken!.symbol}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _quoteRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildSlippRow() {
    return Row(
      children: [
        const Text('Slippage:'),
        const Spacer(),
        SizedBox(
          width: 150,
          child: Slider(
            value: _slippageBps.toDouble(),
            min: 10,
            max: 500,
            divisions: 49,
            label: '${(_slippageBps / 100).toStringAsFixed(2)}%',
            onChanged: _swapping
                ? null
                : (v) {
                    setState(() => _slippageBps = v.round());
                    _refreshQuote();
                  },
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            '${(_slippageBps / 100).toStringAsFixed(2)}%',
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

double pow(int base, int exponent) {
  var result = 1.0;
  for (var i = 0; i < exponent; i++) {
    result *= base;
  }
  return result;
}

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}
