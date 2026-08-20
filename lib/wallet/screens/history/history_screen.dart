import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/transaction_record.dart';
import '../../state/app_state.dart';
import 'transaction_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<TransactionRecord>? _records;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final wallet = context.read<AppState>().wallet;
    if (wallet == null) return;
    final records = await context.read<AppState>().solana.getTransactionHistory(
          wallet.address,
          limit: 100,
        );
    if (mounted) {
      setState(() {
        _records = records;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction history')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _records!.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Icon(Icons.history, size: 56, color: cs.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(
                        'No transactions yet',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  )
                : Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: _records!.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final record = _records![index];
                          return _HistoryTile(record: record);
                        },
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record});

  final TransactionRecord record;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSuccess = record.isSuccess;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isSuccess
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.red.withValues(alpha: 0.15),
          child: Icon(
            isSuccess ? Icons.check : Icons.error_outline,
            color: isSuccess ? Colors.greenAccent : Colors.redAccent,
          ),
        ),
        title: Text(
          record.signature.length > 24
              ? '${record.signature.substring(0, 12)}...${record.signature.substring(record.signature.length - 8)}'
              : record.signature,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
        ),
        subtitle: Text(
          record.date != null
              ? DateFormat('dd.MM.yyyy HH:mm:ss').format(record.date!)
              : 'Waiting...',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        trailing: isSuccess
            ? Icon(Icons.chevron_right, color: cs.onSurfaceVariant)
            : Text('error', style: TextStyle(color: cs.error, fontSize: 12)),
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
