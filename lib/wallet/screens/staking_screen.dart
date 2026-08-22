import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:solana/dto.dart';

import '../config/constants.dart';
import '../services/staking_service.dart';
import '../state/app_state.dart';

class StakingScreen extends StatefulWidget {
  const StakingScreen({super.key});

  @override
  State<StakingScreen> createState() => _StakingScreenState();
}

class _StakingScreenState extends State<StakingScreen> {
  final NumberFormat _solFormat = NumberFormat('#,##0.#########');
  final TextEditingController _amountController = TextEditingController();

  StakingService? _staking;
  List<VoteAccount> _validators = const [];
  VoteAccount? _validator;
  int? _walletLamports;
  List<StakedAccount> _stakes = const [];
  bool _loadingValidators = true;
  bool _staking_ = false;
  String? _error;
  String? _signature;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final wallet = state.wallet!;
    _staking ??= StakingService(state.solana.client);

    setState(() {
      _loadingValidators = true;
      _error = null;
    });
    try {
      final validators = await _staking!.getValidators();
      final lamports = await state.solana.getBalance(wallet.address);
      if (mounted) {
        setState(() {
          _validators = validators;
          _validator = validators.isNotEmpty ? validators.first : null;
          _walletLamports = lamports;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load validators: $e');
    } finally {
      if (mounted) setState(() => _loadingValidators = false);
    }
    await _refreshStakes();
  }

  Future<void> _refreshStakes() async {
    final wallet = context.read<AppState>().wallet!;
    try {
      final stakes = await _staking!.getAccounts(wallet);
      if (mounted) setState(() => _stakes = stakes);
    } catch (_) {}
  }

  Future<void> _doStake() async {
    final state = context.read<AppState>();
    final wallet = state.wallet!;
    final validator = _validator;
    final text = _amountController.text.trim();
    if (validator == null || text.isEmpty || _staking_) return;

    final amount = double.tryParse(text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    final amountLamports = (amount * WalletConfig.lamportsPerSol).round();
    if (_walletLamports == null || amountLamports > _walletLamports!) {
      setState(() => _error = 'Insufficient SOL balance');
      return;
    }

    setState(() {
      _staking_ = true;
      _error = null;
      _signature = null;
    });
    try {
      final index = _stakes.length;
      final signature = await _staking!.stake(
        wallet: wallet,
        vote: validator.votePubkey,
        amountLamports: amountLamports,
        index: index,
      );
      if (mounted) {
        setState(() => _signature = signature);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Staking sent: ${_short(signature)}')),
        );
      }
      await _refreshStakes();
    } catch (e) {
      debugPrint('Stake failed: $e');
      if (mounted) setState(() => _error = 'Staking failed: $e');
    } finally {
      if (mounted) setState(() => _staking_ = false);
    }
  }

  String _short(String s) => s.length > 24
      ? '${s.substring(0, 10)}...${s.substring(s.length - 8)}'
      : s;

  @override
  Widget build(BuildContext context) {
    final solBalance = _walletLamports == null
        ? null
        : _walletLamports! / WalletConfig.lamportsPerSol;
    return Scaffold(
      appBar: AppBar(title: const Text('SOL Staking')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (solBalance != null)
                Text(
                  'Balance: ${_solFormat.format(solBalance)} SOL',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount for staking',
                  prefixIcon: Icon(Icons.savings_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Validator:', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              if (_loadingValidators)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                DropdownButtonFormField<VoteAccount>(
                  initialValue: _validator,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: _validators.map((v) {
                    return DropdownMenuItem<VoteAccount>(
                      value: v,
                      child: Text(
                        '${_short(v.votePubkey)} · commission ${v.commission}%',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: _staking_
                      ? null
                      : (v) => setState(() => _validator = v),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _staking_ ? null : _doStake,
                icon: _staking_
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_outline),
                label: Text(_staking_ ? 'Staking...' : 'Stake'),
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
              const SizedBox(height: 24),
              const Text(
                'My stakes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (_stakes.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'No active stakes yet.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
              else
                ..._stakes.map(
                  (s) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: s.active
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.orange.withValues(alpha: 0.15),
                        child: Icon(
                          s.active ? Icons.check : Icons.schedule,
                          color: s.active ? Colors.greenAccent : Colors.orange,
                        ),
                      ),
                      title: Text(
                        '${_solFormat.format(s.amountSol)} SOL',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        s.vote != null
                            ? 'Validator: ${_short(s.vote!)}'
                            : 'Validator: —',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        s.active ? 'active' : 'activating',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
