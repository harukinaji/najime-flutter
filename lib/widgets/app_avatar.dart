import 'dart:convert';
import 'package:flutter/material.dart';

class AppAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final double size;
  final bool showOnlineIndicator;
  final bool isOnline;
  final Border? border;
  final Color? gradientStart;
  final Color? gradientEnd;

  const AppAvatar({
    super.key,
    this.avatarUrl,
    required this.name,
    this.size = 56,
    this.showOnlineIndicator = false,
    this.isOnline = false,
    this.border,
    this.gradientStart,
    this.gradientEnd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dotSize = size * 0.25;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(child: _buildAvatarImage(cs)),
          if (showOnlineIndicator)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: isOnline
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

  Widget _buildAvatarImage(ColorScheme cs) {
    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;

    if (hasAvatar) {
      if (avatarUrl!.startsWith('data:image')) {
        try {
          final base64Data = avatarUrl!.split(',').last;
          return Image.memory(
            base64Decode(base64Data),
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
          avatarUrl!,
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
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: border,
        gradient: LinearGradient(
          colors: [
            gradientStart ?? cs.primary,
            gradientEnd ?? cs.primary.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
