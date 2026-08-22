import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/transaction_record.dart';
import '../../state/app_state.dart';

class TransactionDetailScreen extends StatefulWidget {
  const TransactionDetailScreen({super.key, required this.record});

  final TransactionRecord record;

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  dynamic _details;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final details = await context.read<AppState>().solana.getTransaction(
        widget.record.signature,
      );
      if (mounted) {
        setState(() {
          _details = details;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction details')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: (record.isSuccess ? Colors.green : Colors.red)
                      .withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  record.isSuccess ? Icons.check : Icons.error_outline,
                  color: record.isSuccess
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                record.isSuccess ? 'Success' : 'Error',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: record.isSuccess
                      ? Colors.greenAccent
                      : Colors.redAccent,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _InfoRow(
              label: 'Signature',
              value: record.signature,
              monospace: true,
            ),
            _InfoRow(label: 'Status', value: record.status?.name ?? '—'),
            _InfoRow(label: 'Slot', value: '${record.slot}'),
            _InfoRow(
              label: 'Time',
              value: record.date != null
                  ? DateFormat('dd.MM.yyyy HH:mm:ss').format(record.date!)
                  : '—',
            ),
            if (record.memo != null)
              _InfoRow(label: 'Memo', value: record.memo!),
            if (record.err != null)
              _InfoRow(
                label: 'Error',
                value: record.err.toString(),
                error: true,
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            else if (_details != null)
              _InfoRow(
                label: 'Fee',
                value: '${_extractFee(_details)} lamports',
              ),
          ],
        ),
      ),
    );
  }

  int _extractFee(dynamic details) {
    try {
      final meta = details.meta;
      if (meta == null) return 0;
      final fee = meta.fee;
      return fee is num ? fee.toInt() : 0;
    } catch (_) {
      return 0;
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.monospace = false,
    this.error = false,
  });

  final String label;
  final String value;
  final bool monospace;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: TextStyle(
              fontSize: 14,
              fontFamily: monospace ? 'monospace' : null,
              color: error ? cs.error : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
