import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api_service.dart';
import '../../data/phone_verification_service.dart';
import 'password_creation_screen.dart';

class PhoneVerificationScreen extends StatefulWidget {
  final String? currentPhone;
  final void Function(String phone) onVerified;

  const PhoneVerificationScreen({
    super.key,
    this.currentPhone,
    required this.onVerified,
  });

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  final _phoneController = TextEditingController();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());
  final _phoneService = PhoneVerificationService();
  final _phoneFocusNode = FocusNode();

  bool _codeSent = false;
  bool _loading = false;
  String? _error;
  int _resendSeconds = 0;
  String? _phoneError;
  bool _phoneTouched = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentPhone != null) {
      _phoneController.text = widget.currentPhone!;
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  static final _phoneRegex = RegExp(r'^\+[1-9]\d{6,14}$');

  String? _validatePhone(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Phone number is required.';
    if (!trimmed.startsWith('+')) return 'Must start with + and country code.';
    if (!_phoneRegex.hasMatch(trimmed)) return 'Invalid phone number format.';
    return null;
  }

  String get _fullPhone {
    final raw = _phoneController.text.trim();
    if (raw.startsWith('+')) return raw;
    return '+$raw';
  }

  String? _userPassword;

  Future<void> _sendCode() async {
    final phone = _fullPhone;
    final validationError = _validatePhone(phone);
    if (validationError != null) {
      setState(() => _phoneError = validationError);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _phoneError = null;
    });

    final hasPassword = await ApiService.hasPassword();
    if (!mounted) return;

    if (!hasPassword) {
      final password = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => PasswordCreationScreen(phoneNumber: phone),
        ),
      );
      if (password == null) {
        setState(() {
          _loading = false;
          _error = 'A password is required to link your phone number.';
        });
        return;
      }
      _userPassword = password;
    }

    await _phoneService.sendCode(
      phoneNumber: phone,
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = err;
        });
      },
      onCodeSent: () {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _codeSent = true;
          _resendSeconds = 60;
        });
        _startResendTimer();
        _otpFocusNodes[0].requestFocus();
      },
      onAutoVerify: (credential) async {
        await _phoneService.verifyCode(
          smsCode: credential.smsCode ?? '',
          onError: (_) {},
          onSuccess: (phone) => _onPhoneVerified(phone),
        );
      },
    );
  }

  void _startResendTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      if (_resendSeconds <= 0) return false;
      setState(() => _resendSeconds--);
      return _resendSeconds > 0;
    });
  }

  Future<void> _verifyCode() async {
    final code = _otpControllers.map((c) => c.text).join();
    if (code.length < 6) {
      setState(() => _error = 'Enter the full 6-digit code.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final success = await _phoneService.verifyCode(
      smsCode: code,
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = err;
        });
        for (final c in _otpControllers) {
          c.clear();
        }
        _otpFocusNodes[0].requestFocus();
      },
      onSuccess: (phone) => _onPhoneVerified(phone),
    );

    if (!success && mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _onPhoneVerified(String phone) async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final linkResult = await ApiService.linkPhoneAccount(
      phoneNumber: phone,
      isVerified: true,
      password: _userPassword,
    );

    if (!mounted) return;

    setState(() => _loading = false);

    if (linkResult.success) {
      widget.onVerified(phone);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phone number verified and encrypted!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    } else {
      setState(() => _error = linkResult.message ?? 'Failed to link phone number.');
    }
  }


  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_codeSent ? 'Verify Code' : 'Phone Number'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: _codeSent ? _buildOtpView(cs) : _buildPhoneView(cs),
      ),
    );
  }

  Widget _buildPhoneView(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Icon(Icons.phone_android, size: 48, color: cs.primary),
        const SizedBox(height: 20),
        Text(
          'Enter your phone number',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "We'll send you a verification code via SMS.",
          style: TextStyle(
            fontSize: 14,
            color: cs.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _phoneController,
          focusNode: _phoneFocusNode,
          keyboardType: TextInputType.phone,
          style: TextStyle(fontSize: 16, color: cs.onSurface),
          onChanged: (_) {
            if (_phoneTouched) {
              setState(() => _phoneError = _validatePhone(_fullPhone));
            }
          },
          onTap: () => _phoneTouched = true,
          decoration: InputDecoration(
            hintText: '+1 (555) 123-4567',
            hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            prefixIcon: Icon(Icons.phone_outlined, color: cs.onSurfaceVariant, size: 22),
            errorText: _phoneError,
            errorStyle: TextStyle(fontSize: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: _phoneError != null ? cs.error : cs.primary,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.error, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
        ],
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _loading ? null : _sendCode,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text('Send Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpView(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Icon(Icons.sms_outlined, size: 48, color: cs.primary),
        const SizedBox(height: 20),
        Text(
          'Enter verification code',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            text: 'A 6-digit code was sent to ',
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant, height: 1.4),
            children: [
              TextSpan(
                text: _fullPhone,
                style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(6, (i) {
            return SizedBox(
              width: 48,
              height: 56,
              child: TextField(
                controller: _otpControllers[i],
                focusNode: _otpFocusNodes[i],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: cs.onSurface),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _otpControllers[i].text.isNotEmpty
                          ? cs.primary
                          : cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.primary, width: 1.5),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (value) {
                  setState(() {});
                  if (value.isNotEmpty && i < 5) {
                    _otpFocusNodes[i + 1].requestFocus();
                  }
                  if (value.isEmpty && i > 0) {
                    _otpFocusNodes[i - 1].requestFocus();
                  }
                  if (_otpControllers.every((c) => c.text.isNotEmpty)) {
                    _verifyCode();
                  }
                },
              ),
            );
          }),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Center(child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13))),
        ],
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _loading ? null : _verifyCode,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text('Verify', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: _resendSeconds > 0
              ? Text(
                  'Resend code in ${_resendSeconds}s',
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                )
              : TextButton(
                  onPressed: _loading ? null : _sendCode,
                  child: Text(
                    'Resend code',
                    style: TextStyle(fontSize: 14, color: cs.primary, fontWeight: FontWeight.w500),
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () {
              setState(() {
                _codeSent = false;
                _error = null;
              });
              for (final c in _otpControllers) {
                c.clear();
              }
            },
            child: Text('Change phone number', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
          ),
        ),
      ],
    );
  }
}
