import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AddressChip extends StatelessWidget {
  const AddressChip({super.key, required this.address, this.onCopy});

  final String address;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final short = address.length > 20
        ? '${address.substring(0, 8)}...${address.substring(address.length - 6)}'
        : address;
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: address));
        if (onCopy != null) {
          onCopy!();
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Address copied')));
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              short,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.copy, size: 14, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}
