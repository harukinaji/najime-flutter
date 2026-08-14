import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_service.dart';
import '../../data/auth_state.dart';

class LoginVerifyScreen extends StatefulWidget {
  final String username;
  final String emailHint;
  final String? password;
  final String? authTicket;

  const LoginVerifyScreen({
    super.key,
    required this.username,
    required this.emailHint,
    this.password,
    this.authTicket,
  });

  @override
  State<LoginVerifyScreen> createState() => _LoginVerifyScreenState();
}

class _LoginVerifyScreenState extends State<LoginVerifyScreen> {
  final _controllers = List.generate(8, (_) => TextEditingController());
  final _focusNodes = List.generate(8, (_) => FocusNode());
  bool _loading = false;
  bool _resending = false;
  int _secondsRemaining = 120;
  Timer? _timer;
  String? _authTicket;

  @override
  void initState() {
    super.initState();
    _authTicket = widget.authTicket;
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _timer?.cancel();
      }
    });
  }

  String get _code => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_code.length < 8) return;

    setState(() => _loading = true);

    final result = await ApiService.verifyEmailCode(
      widget.username,
      _code,
      authTicket: _authTicket,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      await AuthState.instance.saveSession(
        token: result.token ?? '',
        username: result.username ?? widget.username,
        displayName: result.displayName,
        email: result.email,
        bio: result.bio,
        avatarUrl: result.avatarUrl,
      );
      context.go('/home/chats');
    } else {
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Invalid code'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _resend() async {
    if (widget.password == null) return;

    setState(() => _resending = true);

    final result = await ApiService.login(widget.username, widget.password!);

    if (!mounted) return;
    setState(() => _resending = false);
    if (result.authTicket != null) {
      setState(() => _authTicket = result.authTicket);
    }
    setState(() => _secondsRemaining = 120);
    _startTimer();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('New code sent to your email')),
    );
  }

  void _onDigitChanged(int index, String value) {
    if (value.isEmpty) {
      if (index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
      return;
    }

    if (value.length > 1) {
      final chars = value.split('');
      for (int i = 0; i < chars.length && index + i < 8; i++) {
        _controllers[index + i].text = chars[i];
      }
      final lastIndex = (index + chars.length - 1).clamp(0, 7);
      if (lastIndex < 7) {
        _focusNodes[lastIndex + 1].requestFocus();
      } else {
        _focusNodes[7].unfocus();
        _verify();
      }
      return;
    }

    _controllers[index].text = value;
    if (index < 7) {
      _focusNodes[index + 1].requestFocus();
    } else {
      _focusNodes[index].unfocus();
      _verify();
    }
  }

  Widget _buildDigitBox(int index, ColorScheme cs) {
    final hasFocus = _focusNodes[index].hasFocus;
    final hasText = _controllers[index].text.isNotEmpty;
    return Container(
      width: 36,
      height: 44,
      decoration: BoxDecoration(
        color: hasFocus
            ? cs.primary.withValues(alpha: 0.08)
            : cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasFocus
              ? cs.primary
              : hasText
                  ? cs.outline
                  : cs.outlineVariant,
          width: hasFocus ? 1.5 : 1,
        ),
      ),
      child: Center(
        child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          enableInteractiveSelection: false,
          onChanged: (v) => _onDigitChanged(index, v),
        ),
      ),
    );
  }

  String get _formattedTime {
    final m = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.shield_outlined,
                size: 36,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Two-Factor Authentication',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the 8-digit code sent to',
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.emailHint,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 32),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: cs.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
                child: FittedBox(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ...List.generate(4, (index) => _buildDigitBox(index, cs)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '-',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: cs.outlineVariant,
                          ),
                        ),
                      ),
                      ...List.generate(4, (index) => _buildDigitBox(index + 4, cs)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading || _code.length < 8 ? null : _verify,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF18A7B5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Verify',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            if (_secondsRemaining > 0)
              Text(
                'Code expires in $_formattedTime',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
              )
            else
              Text(
                'Code expired',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (widget.password != null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed:
                    _resending || _secondsRemaining > 0 ? null : _resend,
                child: _resending
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _secondsRemaining > 0
                            ? 'Resend code'
                            : 'Send new code',
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
