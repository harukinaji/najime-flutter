import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';

class CreateWalletScreen extends StatefulWidget {
  const CreateWalletScreen({super.key});

  @override
  State<CreateWalletScreen> createState() => _CreateWalletScreenState();
}

class _CreateWalletScreenState extends State<CreateWalletScreen> {
  bool _revealed = false;
  bool _confirmed = false;
  String? _mnemonic;
  bool _creating = false;

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final state = context.read<AppState>();
      final wallet = await state.createWallet();
      if (mounted) {
        setState(() {
          _mnemonic = wallet.mnemonic;
          _creating = false;
          _revealed = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create wallet')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New wallet')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_mnemonic == null) ...[
                const Icon(
                  Icons.shield_outlined,
                  size: 56,
                  color: Colors.amber,
                ),
                const SizedBox(height: 16),
                Text(
                  'Your seed phrase is the only way to recover your wallet. '
                  'Write it down and keep it in a safe place. Never share it with anyone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _creating ? null : _create,
                  child: _creating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text(
                          'Generate seed phrase',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ] else ...[
                if (!_confirmed) ...[
                  Text(
                    'Copy and save your seed phrase:',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: _revealed
                        ? Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (
                                var i = 0;
                                i < _mnemonic!.split(' ').length;
                                i++
                              )
                                Chip(
                                  label: Text(
                                    '${i + 1}. ${_mnemonic!.split(' ')[i]}',
                                  ),
                                  backgroundColor: scheme.surface,
                                ),
                            ],
                          )
                        : const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Write down your seed phrase on paper and keep it in a safe place. Do not take screenshots and do not copy it to the clipboard.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.amber.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (_) =>
                            _MnemonicConfirmDialog(mnemonic: _mnemonic!),
                      );
                      if (confirmed == true && mounted) {
                        _onConfirmed();
                      }
                    },
                    icon: const Icon(Icons.verified_outlined, size: 18),
                    label: const Text('Confirm'),
                  ),
                ] else ...[
                  const Icon(Icons.check_circle, size: 72, color: Colors.green),
                  const SizedBox(height: 16),
                  const Text(
                    'Wallet created successfully!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    child: const Text(
                      'Go to wallet',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _onConfirmed() {
    setState(() => _confirmed = true);
  }
}

class _MnemonicConfirmDialog extends StatefulWidget {
  const _MnemonicConfirmDialog({required this.mnemonic});

  final String mnemonic;

  @override
  State<_MnemonicConfirmDialog> createState() => _MnemonicConfirmDialogState();
}

class _MnemonicConfirmDialogState extends State<_MnemonicConfirmDialog> {
  final _controller = TextEditingController();
  bool _error = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _verify() {
    final input = _controller.text
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .join(' ');
    if (input == widget.mnemonic) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).dialogTheme.backgroundColor ?? Colors.white,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              maxLines: 3,
              minLines: 3,
              decoration: InputDecoration(
                hintText: 'Enter all 12 words in order',
                errorText: _error ? 'Seed phrase doesn\'t match' : null,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _verify, child: const Text('Check')),
          ],
        ),
      ),
    );
  }
}
