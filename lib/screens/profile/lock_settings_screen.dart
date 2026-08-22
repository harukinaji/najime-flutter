import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/lock_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/settings_tile.dart';

class LockSettingsScreen extends StatefulWidget {
  const LockSettingsScreen({super.key});

  @override
  State<LockSettingsScreen> createState() => _LockSettingsScreenState();
}

class _LockSettingsScreenState extends State<LockSettingsScreen> {
  bool _isLoading = true;
  bool _lockEnabled = false;
  LockMethod _method = LockMethod.none;
  bool _biometricSupported = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final lock = LockService.instance;
    final biometric = await lock.canCheckBiometrics();
    if (!mounted) return;
    setState(() {
      _lockEnabled = lock.isEnabled;
      _method = lock.method;
      _biometricSupported = biometric;
      _isLoading = false;
    });
  }

  Future<void> _toggleLock(bool value) async {
    if (value) {
      _showSetPinDialog();
    } else {
      _showDisableDialog();
    }
  }

  void _showSetPinDialog() {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    bool obscure1 = true;
    bool obscure2 = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('Set PIN Code'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: pinController,
                    obscureText: obscure1,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: 'Enter PIN (4-8 digits)',
                      counterText: '',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure1 ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () =>
                            setDialogState(() => obscure1 = !obscure1),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: obscure2,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: 'Confirm PIN',
                      counterText: '',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure2 ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () =>
                            setDialogState(() => obscure2 = !obscure2),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final pin = pinController.text;
                    final confirm = confirmController.text;
                    if (pin.length < 4) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('PIN must be at least 4 digits'),
                        ),
                      );
                      return;
                    }
                    if (pin != confirm) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('PINs do not match')),
                      );
                      return;
                    }

                    await LockService.instance.setPin(pin);
                    await LockService.instance.enable(method: LockMethod.pin);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }
                    if (mounted) {
                      _loadState();
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDisableDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Disable App Lock?'),
          content: const Text(
            'Your messages will no longer be protected by PIN or fingerprint.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () async {
                await LockService.instance.disable();
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
                  _loadState();
                }
              },
              child: const Text('Disable'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _changeBiometric(bool enabled) async {
    debugPrint('[LockSettings] _changeBiometric: enabled=$enabled');
    if (enabled) {
      try {
        debugPrint('[LockSettings] calling authenticateWithBiometric...');
        final authenticated = await LockService.instance
            .authenticateWithBiometric();
        debugPrint('[LockSettings] authenticated=$authenticated');
        if (!authenticated) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Biometrics are not available on this device. Use a PIN code.',
                ),
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
        await LockService.instance.changeMethod(LockMethod.both);
        debugPrint('[LockSettings] method changed to both');
      } catch (e) {
        debugPrint('[LockSettings] exception: $e');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Biometric error: $e')));
        }
        return;
      }
    } else {
      await LockService.instance.changeMethod(LockMethod.pin);
    }
    if (mounted) _loadState();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('App Lock')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 8),
                SettingsTile(
                  icon: Icons.lock_outline,
                  title: 'Lock App',
                  subtitle: _lockEnabled ? 'Enabled' : 'Disabled',
                  iconColor: _lockEnabled
                      ? AppColors.success
                      : cs.onSurfaceVariant,
                  trailing: Switch(
                    value: _lockEnabled,
                    onChanged: _toggleLock,
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.primary,
                  ),
                ),
                if (_lockEnabled) ...[
                  SettingsTile(
                    icon: Icons.pin_outlined,
                    title: 'Change PIN',
                    subtitle: 'Update your PIN code',
                    iconColor: AppColors.primary,
                    onTap: _showSetPinDialog,
                  ),
                  if (_biometricSupported)
                    SettingsTile(
                      icon: Icons.fingerprint,
                      title: 'Fingerprint',
                      subtitle: _method == LockMethod.both
                          ? 'Enabled'
                          : 'Disabled',
                      iconColor: _method == LockMethod.both
                          ? AppColors.success
                          : cs.onSurfaceVariant,
                      trailing: Switch(
                        value: _method == LockMethod.both,
                        onChanged: _changeBiometric,
                        activeThumbColor: Colors.white,
                        activeTrackColor: AppColors.primary,
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.shield_outlined,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'App Lock protects your messages with a PIN code '
                              'or fingerprint when you return to the app.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
