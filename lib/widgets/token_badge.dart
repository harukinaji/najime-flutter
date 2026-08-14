import 'package:flutter/material.dart';


class TokenBadge extends StatelessWidget {
  final String symbol;
  final double balance;

  const TokenBadge({
    super.key,
    required this.symbol,
    required this.balance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            symbol,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _formatBalance(balance),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBalance(double balance) {
    if (balance >= 1000) {
      return '${(balance / 1000).toStringAsFixed(1)}k';
    }
    if (balance >= 1) {
      return balance.toStringAsFixed(2);
    }
    return balance.toStringAsFixed(4);
  }
}
