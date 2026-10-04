import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/message.dart';
import '../data/api_service.dart';
import '../wallet/services/wallet_access_proxy.dart';
import '../wallet/state/app_state.dart';

class PremiumMessageCard extends StatefulWidget {
  final PremiumUnlockInfo premiumInfo;
  final String messageId;
  final String content;
  final ValueChanged<String>? onUnlocked;

  const PremiumMessageCard({
    super.key,
    required this.premiumInfo,
    required this.messageId,
    required this.content,
    this.onUnlocked,
  });

  @override
  State<PremiumMessageCard> createState() => _PremiumMessageCardState();
}

class _PremiumMessageCardState extends State<PremiumMessageCard>
    with SingleTickerProviderStateMixin {
  late bool _isUnlocked;
  late AnimationController _controller;
  late Animation<double> _blurAnimation;
  bool _isPaying = false;
  late String _unlockedContent;

  @override
  void initState() {
    super.initState();
    _isUnlocked = widget.premiumInfo.isUnlocked;
    _unlockedContent = widget.content;
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

  Future<void> _handleUnlock() async {
    if (_isPaying ||
        widget.premiumInfo.amountLamports <= 0 ||
        widget.premiumInfo.recipient.isEmpty) {
      return;
    }
    setState(() => _isPaying = true);
    try {
      const proxy = WalletAccessProxy();
      var binding = await proxy.getBinding();
      if (!binding.bound && mounted) {
        await AppState.instance.restoreExternalWalletSession(context);
        binding = await proxy.getBinding();
      }
      if (!binding.bound && mounted) {
        await AppState.instance.connectExternalWallet(context);
        binding = await proxy.getBinding();
      }
      if (!binding.bound || binding.publicKey == null || !mounted) {
        throw StateError('Connect a wallet to continue');
      }
      final proof = await ApiService.linkWalletAccount(
        walletAddress: binding.publicKey!,
        signMessage: (message) async =>
            (await proxy.signMessage(
              context,
              message: utf8.encode(message),
            )).signature ??
            '',
      );
      if (!proof.success) {
        throw StateError(proof.message ?? 'Wallet proof failed');
      }
      if (!mounted) return;
      final payment = await proxy.paySolana(
        context,
        recipient: widget.premiumInfo.recipient,
        lamports: widget.premiumInfo.amountLamports,
        memo: 'najime:premium:${widget.messageId}',
      );
      final signature = payment.signature;
      if (signature == null || signature.isEmpty) {
        throw StateError('Wallet did not return a transaction signature');
      }
      String? content;
      Object? lastSyncError;
      for (var attempt = 0; attempt < 5 && content == null; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        try {
          content = await ApiService.unlockPremiumMessage(
            widget.messageId,
            signature,
          );
        } catch (error) {
          lastSyncError = error;
        }
      }
      if (content == null) {
        throw StateError(
          'Payment submitted but is not confirmed yet: $lastSyncError',
        );
      }
      final unlockedContent = content;
      if (!mounted) return;
      setState(() {
        _unlockedContent = unlockedContent;
        _isUnlocked = true;
        _isPaying = false;
      });
      _controller.forward();
      widget.onUnlocked?.call(unlockedContent);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPaying = false);
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Payment failed: $e')));
    }
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
        _unlockedContent,
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
                        AppLocalizations.of(context).translate('premium.title'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${AppLocalizations.of(context).translate('premium.unlockFor')} ${widget.premiumInfo.amount} ${widget.premiumInfo.assetSymbol}',
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
                              onPressed: _isPaying ? null : () {},
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(color: cs.outlineVariant),
                              ),
                              child: Text(
                                AppLocalizations.of(
                                  context,
                                ).translate('premium.cancel'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isPaying ? null : _handleUnlock,
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
                              child: _isPaying
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      AppLocalizations.of(
                                        context,
                                      ).translate('premium.unlock'),
                                    ),
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
