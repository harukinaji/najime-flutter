import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../services/solana_pay_service.dart';
import '../state/app_state.dart';

class SolanaPayScreen extends StatefulWidget {
  const SolanaPayScreen({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  State<SolanaPayScreen> createState() => _SolanaPayScreenState();
}

class _SolanaPayScreenState extends State<SolanaPayScreen> {
  late final TextEditingController _urlController;
  SolanaPayService? _payService;
  SolanaPayInfo? _info;
  String? _error;
  bool _busy = false;
  String? _resultSignature;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl ?? '');
    if (widget.initialUrl != null) _parseUrl();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _parseUrl() {
    final service = context.read<AppState>().solana;
    final payService = _payService ??= SolanaPayService(service.client);
    final info = payService.tryParse(_urlController.text);
    setState(() {
      _info = info;
      _error = info == null ? 'Это не похоже на ссылку Solana Pay.' : null;
      _resultSignature = null;
    });
  }

  Future<void> _scanQr() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScannerScreen()),
    );
    if (scanned != null && mounted) {
      _urlController.text = scanned;
      _parseUrl();
    }
  }

  Future<void> _pay() async {
    final state = context.read<AppState>();
    final wallet = state.wallet;
    final info = _info;
    if (wallet == null || info == null || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _resultSignature = null;
    });

    try {
      final service = _payService ??= SolanaPayService(state.solana.client);
      final signature = switch (info.type) {
        SolanaPayType.transfer => await service.payWithSol(wallet: wallet, info: info),
        SolanaPayType.transactionRequest => await service.processTransactionRequest(
            wallet: wallet,
            info: info,
          ),
      };
      if (mounted) {
        setState(() => _resultSignature = signature);
      }
    } catch (e) {
      debugPrint('Solana Pay failed: $e');
      if (mounted) {
        setState(() => _error = 'Оплата не прошла: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Оплатить (Solana Pay)')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Ссылка Solana Pay',
                  hintText: 'solana:... или https://...',
                  prefixIcon: const Icon(Icons.link),
                  suffixIcon: IconButton(
                    tooltip: 'Отсканировать QR',
                    onPressed: _scanQr,
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                ),
                onSubmitted: (_) => _parseUrl(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _parseUrl,
                      icon: const Icon(Icons.check),
                      label: const Text('Разобрать'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _scanQr,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Сканировать'),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
              if (_info != null) ...[
                const SizedBox(height: 16),
                _buildDetails(context),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _pay,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.payment),
                  label: Text(_busy ? 'Отправка...' : 'Оплатить'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
              if (_resultSignature != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Оплата отправлена',
                        style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        _resultSignature!,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context) {
    final info = _info!;
    final isV2 = info.type == SolanaPayType.transactionRequest;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isV2 ? 'Запрос платежа (мерчант)' : 'Прямой перевод',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (info.label != null) ...[
              const SizedBox(height: 12),
              _DetailRow(label: 'Продавец', value: info.label!),
            ],
            if (info.message != null) ...[
              const SizedBox(height: 8),
              _DetailRow(label: 'Сообщение', value: info.message!),
            ],
            const SizedBox(height: 8),
            _DetailRow(
              label: isV2 ? 'Ссылка' : 'Получатель',
              value: info.recipient,
              selectable: true,
            ),
            if (info.amount != null) ...[
              const SizedBox(height: 8),
              _DetailRow(
                label: 'Сумма',
                value: '${_formatAmount(info.amount!)} ${info.splToken == null ? 'SOL' : 'SPL'}',
              ),
            ],
            if (info.memo != null) ...[
              const SizedBox(height: 8),
              _DetailRow(label: 'Memo', value: info.memo!),
            ],
          ],
        ),
      ),
    );
  }

  String _formatAmount(Decimal amount) {
    final s = amount.toString();
    return s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.selectable = false});

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ),
        Expanded(
          child: selectable
              ? SelectableText(
                  value,
                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                )
              : Text(value, style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}

/// Full-screen camera scanner that pops with the first detected text barcode.
class _QrScannerScreen extends StatefulWidget {
  const _QrScannerScreen();

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сканировать QR')),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          if (_handled) return;
          final raw = capture.barcodes.firstOrNull?.rawValue;
          if (raw == null || raw.isEmpty) return;
          _handled = true;
          Navigator.of(context).pop(raw);
        },
      ),
    );
  }
}
