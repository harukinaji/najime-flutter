import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const availableReactions = ['👍', '❤️', '😂', '😮', '😢', '🔥', '👏', '🎉'];

class ReactionPicker extends StatelessWidget {
  final String messageId;
  final void Function(String emoji) onReaction;

  const ReactionPicker({
    super.key,
    required this.messageId,
    required this.onReaction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: availableReactions.map((emoji) {
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onReaction(emoji);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(emoji, style: const TextStyle(fontSize: 24)),
            ),
          );
        }).toList(),
      ),
    );
  }
}
