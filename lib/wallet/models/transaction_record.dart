import 'package:solana/dto.dart';

class TransactionRecord {
  const TransactionRecord({
    required this.signature,
    required this.slot,
    this.blockTime,
    this.err,
    this.memo,
    this.status,
  });

  final String signature;
  final int slot;
  final int? blockTime;
  final Map<String, dynamic>? err;
  final String? memo;
  final ConfirmationStatus? status;

  bool get isSuccess => err == null;

  DateTime? get date => blockTime != null
      ? DateTime.fromMillisecondsSinceEpoch(blockTime! * 1000)
      : null;
}
