import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/message.dart';

class PremiumUnlockScreen extends StatefulWidget {
  final PremiumUnlockInfo? premiumInfo;
  final String? contentTitle;
  final String? senderName;

  const PremiumUnlockScreen({
    super.key,
    this.premiumInfo,
    this.contentTitle,
    this.senderName,
  });

  @override
  State<PremiumUnlockScreen> createState() => _PremiumUnlockScreenState();
}

class _PremiumUnlockScreenState extends State<PremiumUnlockScreen>
    with TickerProviderStateMixin {
  ColorScheme get _cs => Theme.of(context).colorScheme;
  late bool _isUnlocked;
  late String _selectedToken;
  bool _isUnlocking = false;
  bool _showSuccess = false;

  late AnimationController _blurController;
  late AnimationController _successController;
  late Animation<double> _blurAnim;
  late Animation<double> _successScaleAnim;
  late Animation<double> _successOpacityAnim;

  PremiumUnlockInfo get _info =>
      widget.premiumInfo ??
      const PremiumUnlockInfo(assetSymbol: 'SOL', amount: 0.5);

  @override
  void initState() {
    super.initState();
    _isUnlocked = _info.isUnlocked;
    _selectedToken = _info.assetSymbol;

    _blurController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _blurAnim = Tween<double>(begin: 10.0, end: 0.0).animate(
      CurvedAnimation(parent: _blurController, curve: Curves.easeOut),
    );

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _successScaleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _successController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    _successOpacityAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _successController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );

    if (_isUnlocked) {
      _blurController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _blurController.dispose();
    _successController.dispose();
    super.dispose();
  }

  Future<void> _handleUnlock() async {
    if (_isUnlocking || _isUnlocked) return;

    setState(() => _isUnlocking = true);

    await Future.delayed(const Duration(milliseconds: 1500));

    setState(() {
      _isUnlocked = true;
      _isUnlocking = false;
    });

    _blurController.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    _successController.forward();

    setState(() => _showSuccess = true);

    await Future.delayed(const Duration(milliseconds: 2000));
    if (mounted) {
      setState(() => _showSuccess = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Premium Content'),
        backgroundColor: _cs.primary,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildContentPreview(),
                      const SizedBox(height: 24),
                      if (!_isUnlocked) _buildUnlockSection(),
                      if (_isUnlocked) _buildUnlockedContent(),
                    ],
                  ),
                ),
              ),
              if (!_isUnlocked) _buildBottomActions(),
            ],
          ),
          if (_showSuccess) _buildSuccessOverlay(),
        ],
      ),
    );
  }

  Widget _buildContentPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AnimatedBuilder(
        animation: _blurAnim,
        builder: (context, child) => ImageFiltered(
          imageFilter: _isUnlocked
              ? ImageFilter.blur(sigmaX: 0, sigmaY: 0)
              : ImageFilter.blur(sigmaX: _blurAnim.value, sigmaY: _blurAnim.value),
          child: child,
        ),
        child: Container(
          width: double.infinity,
          height: 240,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _cs.primary.withValues(alpha: 0.15),
                _cs.primary.withValues(alpha: 0.7).withValues(alpha: 0.25),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isUnlocked ? Icons.lock_open : Icons.lock,
                size: 56,
                color: _cs.primary.withValues(alpha: _isUnlocked ? 0.6 : 0.4),
              ),
              const SizedBox(height: 12),
              Text(
                widget.contentTitle ?? 'Exclusive Content',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurface.withValues(alpha: _isUnlocked ? 1 : 0.5),
                ),
              ),
              if (!_isUnlocked) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Locked',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnlockSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Unlock for',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: _cs.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        _buildTokenSelector(),
        const SizedBox(height: 16),
        _buildAmountDisplay(),
        const SizedBox(height: 16),
        _buildSenderInfo(),
      ],
    );
  }

  Widget _buildTokenSelector() {
    final tokens = ['SOL', 'USDC', 'BONK', 'RAY'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: tokens.map((token) {
          final isSelected = _selectedToken == token;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedToken = token),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? _cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      token,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? Colors.white
                            : _cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAmountDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cs.outlineVariant),
      ),
      child: Column(
        children: [
          Text(
            _selectedToken,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _info.amount.toStringAsFixed(_info.amount < 1 ? 4 : 2),
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: _cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '≈ \$${(_info.amount * 170).toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14,
              color: _cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSenderInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.person_outline, size: 20, color: _cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From',
                  style: TextStyle(
                    fontSize: 12,
                    color: _cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.senderName ?? 'Sender',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnlockedContent() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle, size: 48, color: Color(0xFF22C55E)),
          const SizedBox(height: 12),
          const Text(
            'Content Unlocked!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF22C55E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You now have access to ${widget.contentTitle ?? 'this premium content'}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: _cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  _cs.primary.withValues(alpha: 0.2),
                  _cs.secondary.withValues(alpha: 0.3),
                ],
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image, size: 40, color: _cs.primary),
                  const SizedBox(height: 8),
                  Text(
                    'Premium content revealed',
                    style: TextStyle(
                      color: _cs.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(
        color: _cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: _cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isUnlocking ? null : _handleUnlock,
              style: ElevatedButton.styleFrom(
                backgroundColor: _cs.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _cs.primary.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isUnlocking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Unlock for ${_info.amount.toStringAsFixed(_info.amount < 1 ? 4 : 2)} $_selectedToken',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessOverlay() {
    return AnimatedBuilder(
      animation: _successController,
      builder: (context, child) => Opacity(
        opacity: _successOpacityAnim.value,
        child: Container(
          color: Colors.black.withValues(alpha: 0.5),
          child: Center(
            child: Transform.scale(
              scale: _successScaleAnim.value,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.4),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check,
                  size: 60,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
