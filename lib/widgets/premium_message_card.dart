import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/message.dart';

class PremiumMessageCard extends StatefulWidget {
  final PremiumUnlockInfo premiumInfo;
  final String content;
  final VoidCallback? onUnlock;

  const PremiumMessageCard({
    super.key,
    required this.premiumInfo,
    required this.content,
    this.onUnlock,
  });

  @override
  State<PremiumMessageCard> createState() => _PremiumMessageCardState();
}

class _PremiumMessageCardState extends State<PremiumMessageCard>
    with SingleTickerProviderStateMixin {
  late bool _isUnlocked;
  late AnimationController _controller;
  late Animation<double> _blurAnimation;

  @override
  void initState() {
    super.initState();
    _isUnlocked = widget.premiumInfo.isUnlocked;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _blurAnimation = Tween<double>(
      begin: 8.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    if (_isUnlocked) _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(PremiumMessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.premiumInfo.isUnlocked && !_isUnlocked) {
      _isUnlocked = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleUnlock() {
    setState(() => _isUnlocked = true);
    _controller.forward();
    widget.onUnlock?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (_isUnlocked && _controller.isCompleted) {
          return _buildUnlockedContent(cs);
        }
        return _buildLockedCard(cs);
      },
    );
  }

  Widget _buildUnlockedContent(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        widget.content,
        style: TextStyle(fontSize: 15, color: cs.onSurface),
      ),
    );
  }

  Widget _buildLockedCard(ColorScheme cs) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: _blurAnimation.value,
          sigmaY: _blurAnimation.value,
        ),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.content,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.black.withValues(
                      alpha: _isUnlocked ? 1.0 : 0.3,
                    ),
                  ),
                ),
              ),
              if (!_isUnlocked)
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.lock_outline,
                          color: cs.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Premium Message',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Unlock for ${widget.premiumInfo.amount} ${widget.premiumInfo.assetSymbol}',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _handleUnlock,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(color: cs.outlineVariant),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _handleUnlock,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: cs.primary,
                                foregroundColor: cs.onPrimary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Unlock'),
                            ),
                          ),
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
}
