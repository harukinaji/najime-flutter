import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/lock_service.dart';
import '../../theme/app_colors.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with TickerProviderStateMixin {
  String _pin = '';
  bool _error = false;
  bool _biometricAvailable = false;
  bool _biometricInProgress = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );
    _checkBiometric();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometric() async {
    final lock = LockService.instance;
    debugPrint('[LockScreen] _checkBiometric: canUseBiometric=${lock.canUseBiometric}, method=${lock.method}');
    if (!lock.canUseBiometric) return;
    setState(() => _biometricAvailable = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) _tryBiometric();
  }

  Future<void> _tryBiometric() async {
    if (_biometricInProgress) {
      debugPrint('[LockScreen] _tryBiometric: already in progress, skipping');
      return;
    }
    _biometricInProgress = true;
    debugPrint('[LockScreen] _tryBiometric: starting');
    try {
      final success = await LockService.instance.authenticateWithBiometric();
      debugPrint('[LockScreen] _tryBiometric: result=$success, mounted=$mounted');
      if (success) {
        HapticFeedback.lightImpact();
        debugPrint('[LockScreen] calling onUnlocked...');
        widget.onUnlocked();
      }
    } catch (e) {
      debugPrint('[LockScreen] _tryBiometric: exception=$e');
    } finally {
      _biometricInProgress = false;
    }
  }

  void _onDigit(String digit) {
    if (_pin.length >= 8) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin += digit;
      _error = false;
    });

    if (_pin.length >= 4) {
      _verifyPin();
    }
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = false;
    });
  }

  Future<void> _verifyPin() async {
    final success = await LockService.instance.verifyPin(_pin);
    if (success) {
      HapticFeedback.mediumImpact();
      if (mounted) widget.onUnlocked();
    } else if (_pin.length >= 4) {
      HapticFeedback.heavyImpact();
      setState(() => _error = true);
      _shakeController.forward(from: 0);
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) setState(() => _pin = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1419) : cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Icon(
              Icons.lock_outline,
              size: 48,
              color: AppColors.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Enter PIN',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 32),
            _buildPinDots(cs),
            if (_error) ...[
              const SizedBox(height: 12),
              Text(
                'Wrong PIN, try again',
                style: TextStyle(
                  color: AppColors.error,
                  fontSize: 14,
                ),
              ),
            ],
            const Spacer(flex: 1),
            _buildNumpad(cs),
            if (_biometricAvailable) ...[
              const SizedBox(height: 16),
              _buildBiometricButton(cs),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPinDots(ColorScheme cs) {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        final offset = _error
            ? Offset(_shakeAnimation.value * 10 * (1 - _shakeAnimation.value), 0)
            : Offset.zero;
        return Transform.translate(
          offset: offset,
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final filled = i < _pin.length;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled
                  ? (_error ? AppColors.error : AppColors.primary)
                  : Colors.transparent,
              border: Border.all(
                color: _error && filled
                    ? AppColors.error
                    : (filled ? AppColors.primary : cs.outlineVariant),
                width: 2,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNumpad(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          for (int row = 0; row < 3; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(3, (col) {
                  final digit = (row * 3 + col + 1).toString();
                  return _buildDigitButton(digit, cs);
                }),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 72, height: 72),
              _buildDigitButton('0', cs),
              SizedBox(
                width: 72,
                height: 72,
                child: IconButton(
                  onPressed: _pin.isNotEmpty ? _onDelete : null,
                  icon: Icon(
                    Icons.backspace_outlined,
                    color: _pin.isNotEmpty ? cs.onSurface : cs.outlineVariant,
                    size: 26,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDigitButton(String digit, ColorScheme cs) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(36),
          onTap: () => _onDigit(digit),
          child: Center(
            child: Text(
              digit,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBiometricButton(ColorScheme cs) {
    return TextButton.icon(
      onPressed: _tryBiometric,
      icon: Icon(Icons.fingerprint, color: AppColors.primary, size: 28),
      label: Text(
        'Use Fingerprint',
        style: TextStyle(color: AppColors.primary, fontSize: 15),
      ),
    );
  }
}
