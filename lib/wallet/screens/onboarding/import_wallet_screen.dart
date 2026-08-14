import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';

class ImportWalletScreen extends StatefulWidget {
  const ImportWalletScreen({super.key});

  @override
  State<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends State<ImportWalletScreen> {
  final _seedController = TextEditingController();
  final _keyController = TextEditingController();
  bool _usePrivateKey = false;
  bool _importing = false;
  String? _error;

  @override
  void dispose() {
    _seedController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final state = context.read<AppState>();
      if (_usePrivateKey) {
        final key = _keyController.text.trim();
        if (key.isEmpty) throw const FormatException('Введите приватный ключ');
        await state.importFromPrivateKey(key);
      } else {
        final seed = _seedController.text.trim();
        final words = seed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        if (words != 12 && words != 24) {
          throw const FormatException('Seed-фраза должна содержать 12 или 24 слова');
        }
        // Validate individual words (basic check - each word should be lowercase letters only)
        final wordList = seed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        for (final word in wordList) {
          if (!RegExp(r'^[a-z]+$').hasMatch(word)) {
            throw const FormatException('Каждое слово должно содержать только латинские буквы в нижнем регистре');
          }
        }
        await state.importFromMnemonic(seed);
      }
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _importing = false;
          _error = e.toString().replaceFirst('FormatException: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Импорт кошелька')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Seed-фраза'), icon: Icon(Icons.notes)),
                  ButtonSegment(
                    value: true,
                    label: Text('Приватный ключ'),
                    icon: Icon(Icons.key),
                  ),
                ],
                selected: {_usePrivateKey},
                onSelectionChanged: (selection) {
                  setState(() => _usePrivateKey = selection.first);
                },
              ),
              const SizedBox(height: 24),
              if (!_usePrivateKey) ...[
                TextField(
                  controller: _seedController,
                  maxLines: 4,
                  minLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Seed-фраза (12 или 24 слова)',
                    hintText: 'apple banana cherry ...',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Введите слова в правильном порядке, разделённые пробелами.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _keyController,
                  maxLines: 2,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'Приватный ключ (base58)',
                    hintText: '64-байтовый ключ в формате base58',
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _importing ? null : _import,
                child: _importing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Импортировать', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
