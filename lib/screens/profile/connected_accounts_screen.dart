import 'package:flutter/material.dart';

import '../../data/api_service.dart';
import '../../widgets/google_icon.dart';
import '../../widgets/phone_number_card.dart';
import 'phone_verification_screen.dart';

class ConnectedAccountsScreen extends StatefulWidget {
  const ConnectedAccountsScreen({super.key});

  @override
  State<ConnectedAccountsScreen> createState() =>
      _ConnectedAccountsScreenState();
}

class _ConnectedAccountsScreenState extends State<ConnectedAccountsScreen> {
  bool _loading = true;
  String? _error;
  bool _googleConnected = false;
  String? _googleEmail;
  String? _phone;
  bool _phoneVerified = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ApiService.getConnectedAccounts();

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _loading = false;
        _googleConnected = result.google?['connected'] == true;
        _googleEmail = result.google?['email'] as String?;
        _phone = result.phone?['phone_number'] as String?;
        _phoneVerified = result.phone?['is_verified'] == true;
      });
    } else {
      setState(() {
        _loading = false;
        _error = result.message ?? 'Failed to load accounts';
      });
    }
  }

  Future<void> _toggleGoogle(bool value) async {
    if (value) {
      await _connectGoogle();
    } else {
      await _disconnectGoogle();
    }
  }

  Future<void> _connectGoogle() async {
    // In a real app, use google_sign_in to get the idToken
    // For now, show a dialog explaining the flow
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Connect Google'),
        content: const Text(
          'This would open Google Sign-In. After authenticating, '
          'your Google account will be linked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              // TODO: Implement real Google Sign-In flow using google_sign_in package
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Google Sign-In not yet implemented'),
                  ),
                );
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnectGoogle() async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Disconnect Google?'),
        content: const Text(
          'You will no longer be able to sign in with this Google account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Disconnect', style: TextStyle(color: cs.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final result = await ApiService.unlinkGoogleAccount();
      if (result.success && mounted) {
        _loadAccounts();
      }
    }
  }

  void _openPhoneVerification() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhoneVerificationScreen(
          currentPhone: _phone,
          onVerified: (phone) async {
            await ApiService.linkPhoneAccount(
              phoneNumber: phone,
              isVerified: true,
            );
            if (mounted) _loadAccounts();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Connected Accounts')),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: cs.error),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurface, fontSize: 15),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _loadAccounts,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadAccounts,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    PhoneNumberCard(
                      phoneNumber: _phone,
                      isVerified: _phoneVerified,
                      onEdit: _openPhoneVerification,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Social Accounts',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Link accounts for easier sign-in and recovery.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _GoogleRow(
                                isConnected: _googleConnected,
                                email: _googleEmail,
                                onToggle: (v) => _toggleGoogle(v),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}

class _GoogleRow extends StatelessWidget {
  final bool isConnected;
  final String? email;
  final ValueChanged<bool> onToggle;

  const _GoogleRow({
    required this.isConnected,
    this.email,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF4285F4).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: GoogleIcon(size: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Google',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                if (email != null)
                  Text(
                    email!,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Switch(
            value: isConnected,
            onChanged: onToggle,
            activeColor: Colors.white,
            activeTrackColor: cs.primary,
            inactiveTrackColor: cs.surfaceContainerHighest,
          ),
        ],
      ),
    );
  }
}
