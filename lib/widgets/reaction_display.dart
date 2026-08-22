import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/message.dart';

class ReactionDisplay extends StatelessWidget {
  final List<Reaction> reactions;
  final bool isMe;
  final String? currentUserId;
  final void Function(String emoji) onTap;

  const ReactionDisplay({
    super.key,
    required this.reactions,
    required this.isMe,
    this.currentUserId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        left: isMe ? 0 : 16,
        right: isMe ? 16 : 0,
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: reactions.map((r) {
              return _ReactionChip(
                reaction: r,
                currentUserId: currentUserId,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onTap(r.emoji);
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final Reaction reaction;
  final String? currentUserId;
  final VoidCallback onTap;

  const _ReactionChip({
    required this.reaction,
    this.currentUserId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasReacted = reaction.hasUser(currentUserId);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: hasReacted
              ? cs.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: hasReacted
              ? Border.all(color: cs.primary.withValues(alpha: 0.3), width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(reaction.emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 3),
            if (reaction.count <= 2) ...[
              ...reaction.users
                  .take(2)
                  .map(
                    (u) => Padding(
                      padding: const EdgeInsets.only(left: 1),
                      child: _UserAvatar(user: u, size: 16),
                    ),
                  ),
            ] else ...[
              _UserAvatar(user: reaction.users.first, size: 16),
              const SizedBox(width: 1),
              Text(
                '${reaction.count}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: hasReacted ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  final ReactionUser user;
  final double size;

  const _UserAvatar({required this.user, required this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasAvatar = user.avatarUrl.isNotEmpty;

    Widget avatar;

    if (hasAvatar && user.avatarUrl.startsWith('data:image')) {
      try {
        final base64Data = user.avatarUrl.split(',').last;
        final bytes = base64Decode(base64Data);
        avatar = ClipOval(
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {
        avatar = _initialsAvatar(cs);
      }
    } else if (hasAvatar) {
      avatar = ClipOval(
        child: Image.network(
          user.avatarUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _initialsAvatar(cs),
        ),
      );
    } else {
      avatar = _initialsAvatar(cs);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: cs.surfaceContainerHighest, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatar,
    );
  }

  Widget _initialsAvatar(ColorScheme cs) {
    final initial = user.displayName.isNotEmpty
        ? user.displayName[0].toUpperCase()
        : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.primary.withValues(alpha: 0.2),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.55,
            fontWeight: FontWeight.w600,
            color: cs.primary,
          ),
        ),
      ),
    );
  }
}
