import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_service.dart';
import '../../data/auth_state.dart';

class LoginApprovalScreen extends StatefulWidget {
  final String username;
  final String approvalId;
  final String pollSecret;
  final int expiresIn;

  const LoginApprovalScreen({
    super.key,
    required this.username,
    required this.approvalId,
    required this.pollSecret,
    required this.expiresIn,
  });

  @override
  State<LoginApprovalScreen> createState() => _LoginApprovalScreenState();
}

class _LoginApprovalScreenState extends State<LoginApprovalScreen> {
  Timer? _timer;
  Timer? _countdown;
  int _secondsRemaining = 0;
  bool _fallbackLoading = false;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.expiresIn;
    _startPolling();
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_secondsRemaining > 0) _secondsRemaining--;
      });
    });
  }

  Future<void> _poll() async {
    final result = await ApiService.pollApproval(
      widget.approvalId,
      widget.pollSecret,
    );

    if (!mounted) return;

    if (result.success) {
      _timer?.cancel();
      _countdown?.cancel();
      AuthState.instance.isAuthenticated = true;
      AuthState.instance.username = result.username;
      context.go('/home/chats');
      return;
    }

    if (result.approvalStatus == 'denied') {
      _cancelTimers();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Login denied on phone'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      context.go('/auth');
      return;
    }

    if (result.approvalStatus == 'expired' || _secondsRemaining <= 0) {
      _cancelTimers();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Login request expired')));
      context.go('/auth');
    }
  }

  Future<void> _fallbackToEmail() async {
    setState(() => _fallbackLoading = true);

    final result = await ApiService.fallbackToEmail(
      widget.approvalId,
      widget.pollSecret,
    );

    if (!mounted) return;

    setState(() => _fallbackLoading = false);

    if (result.emailHint != null) {
      _cancelTimers();
      context.push('/auth/verify', extra: {
        'username': widget.username,
        'emailHint': result.emailHint,
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'No email on account'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _cancelTimers() {
    _timer?.cancel();
    _countdown?.cancel();
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  String get _formattedTime {
    final min = _secondsRemaining ~/ 60;
    final sec = _secondsRemaining % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Login')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.smartphone, size: 80, color: Color(0xFF18A7B5)),
              const SizedBox(height: 24),
              Text(
                'Confirm on your phone',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'A login request was sent to your phone.\nOpen NajiMe on your device to approve it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                'Expires in $_formattedTime',
                style: TextStyle(
                  color: _secondsRemaining < 30
                      ? cs.error
                      : cs.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 40),
              TextButton.icon(
                onPressed: _fallbackLoading ? null : _fallbackToEmail,
                icon: _fallbackLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.email_outlined, size: 20),
                label: Text(
                  _fallbackLoading
                      ? 'Sending...'
                      : 'Send code to email instead',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
