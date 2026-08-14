import 'package:flutter/material.dart';

class PhoneNumberCard extends StatelessWidget {
  final String? phoneNumber;
  final bool isVerified;
  final VoidCallback? onEdit;

  const PhoneNumberCard({
    super.key,
    this.phoneNumber,
    this.isVerified = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.phone,
                color: cs.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Phone Number',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          phoneNumber ?? 'Add Phone Number',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: phoneNumber != null
                                ? cs.onSurface
                                : cs.primary,
                          ),
                        ),
                      ),
                      if (isVerified && phoneNumber != null) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.verified,
                          color: cs.primary,
                          size: 16,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onEdit,
              icon: Icon(
                phoneNumber != null ? Icons.edit_outlined : Icons.add_circle_outline,
                color: cs.primary,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
