import 'dart:convert';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/chat.dart';
import '../models/message.dart';

class ChatTile extends StatelessWidget {
  final ChatModel chat;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ChatTile({super.key, required this.chat, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _buildAvatar(context, cs),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (chat.isMuted) ...[
                          Icon(
                            Icons.notifications_off,
                            size: 14,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          _formatTime(chat.lastActivity),
                          style: TextStyle(
                            fontSize: 12,
                            color: chat.unreadCount > 0
                                ? cs.primary
                                : cs.onSurfaceVariant,
                            fontWeight: chat.unreadCount > 0
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _buildLastMessagePreview(cs),
                        ),
                        if (chat.unreadCount > 0) ...[
                          const SizedBox(width: 8),
                          _buildUnreadBadge(cs),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, ColorScheme cs) {
    const double avatarSize = 56;
    const double dotSize = 14;

    return SizedBox(
      width: avatarSize,
      height: avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: _buildAvatarImage(avatarSize, cs),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: chat.isOnline
                    ? const Color(0xFF22C55E)
                    : const Color(0xFF787880),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).cardColor,
                  width: 2.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarImage(double size, ColorScheme cs) {
    if (chat.avatarUrl != null && chat.avatarUrl!.isNotEmpty) {
      if (chat.avatarUrl!.startsWith('data:image')) {
        try {
          return Image.memory(
            base64Decode(chat.avatarUrl!.split(',').last),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildInitialAvatar(cs),
          );
        } catch (_) {
          return _buildInitialAvatar(cs);
        }
      } else {
        return Image.network(
          chat.avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildInitialAvatar(cs),
        );
      }
    }
    return _buildInitialAvatar(cs);
  }

  Widget _buildInitialAvatar(ColorScheme cs) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
        ),
      ),
      child: Center(
        child: Text(
          chat.name.isNotEmpty ? chat.name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildUnreadBadge(ColorScheme cs) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Center(
        child: Text(
          chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildLastMessagePreview(ColorScheme cs) {
    final msg = chat.lastMessage;
    if (msg == null) return const SizedBox.shrink();

    final textStyle = TextStyle(
      fontSize: 14,
      color: chat.unreadCount > 0 ? cs.onSurface : cs.onSurfaceVariant,
      fontWeight: chat.unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
    );

    switch (msg.type) {
      case MessageType.text:
        return Text(
          msg.content,
          style: textStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case MessageType.image:
        return Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: _buildPreviewImage(msg.content, 28, 28),
            ),
            const SizedBox(width: 6),
            Text('Photo', style: textStyle),
          ],
        );
      case MessageType.sticker:
        return Text(
          'Sticker',
          style: textStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case MessageType.voice:
        return Row(
          children: [
            Icon(Icons.mic, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('Voice message', style: textStyle),
          ],
        );
      case MessageType.file:
        return Row(
          children: [
            Icon(Icons.attach_file, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                msg.fileName ?? 'File',
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      case MessageType.premiumMessage:
        return Row(
          children: [
            Icon(Icons.lock, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('Premium message', style: textStyle),
          ],
        );
      case MessageType.invoice:
        final inv = InvoiceData.tryParse(msg.content);
        return Row(
          children: [
            Icon(Icons.receipt_long, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              inv != null
                  ? 'Invoice: ${inv.amount} ${inv.currency}'
                  : 'Invoice',
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      case MessageType.check:
        final chk = CheckData.tryParse(msg.content);
        return Row(
          children: [
            Icon(Icons.card_giftcard, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              chk != null
                  ? 'Чек: ${chk.amount} ${chk.currency}'
                  : 'Чек',
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
    }
  }

  Widget _buildPreviewImage(String url, double w, double h) {
    final fullUrl = url.startsWith('/uploads')
        ? '${AppConfig.apiBaseUrl}$url'
        : url;
    if (fullUrl.startsWith('data:image')) {
      try {
        return Image.memory(
          base64Decode(fullUrl.split(',').last),
          width: w,
          height: h,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultThumb(),
        );
      } catch (_) {
        return _defaultThumb();
      }
    }
    return Image.network(
      fullUrl,
      width: w,
      height: h,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _defaultThumb(),
    );
  }

  Widget _defaultThumb() {
    return Container(
      width: 28,
      height: 28,
      color: Colors.grey[300],
      child: const Icon(Icons.image, size: 16, color: Colors.grey),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays == 0) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[time.weekday - 1];
    } else {
      return '${time.day}/${time.month}';
    }
  }
}
