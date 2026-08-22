import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_colors.dart';
import '../../widgets/settings_tile.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  late bool _showOnline;
  late bool _showReadReceipts;
  late bool _showPhoneNumber;
  late bool _allowGroupInvites;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showOnline = prefs.getBool('privacy_show_online') ?? true;
      _showReadReceipts = prefs.getBool('privacy_show_read_receipts') ?? true;
      _showPhoneNumber = prefs.getBool('privacy_show_phone') ?? false;
      _allowGroupInvites = prefs.getBool('privacy_allow_group_invites') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_show_online', _showOnline);
    await prefs.setBool('privacy_show_read_receipts', _showReadReceipts);
    await prefs.setBool('privacy_show_phone', _showPhoneNumber);
    await prefs.setBool('privacy_allow_group_invites', _allowGroupInvites);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          SettingsTile(
            icon: Icons.circle,
            title: 'Show Online Status',
            subtitle: 'Let others see when you are online',
            iconColor: AppColors.success,
            trailing: Switch(
              value: _showOnline,
              onChanged: (v) {
                setState(() => _showOnline = v);
                _saveSettings();
              },
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.primary,
            ),
          ),
          SettingsTile(
            icon: Icons.done_all_outlined,
            title: 'Show Read Receipts',
            subtitle: 'Let others know you have read their messages',
            iconColor: AppColors.primary,
            trailing: Switch(
              value: _showReadReceipts,
              onChanged: (v) {
                setState(() => _showReadReceipts = v);
                _saveSettings();
              },
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.primary,
            ),
          ),
          SettingsTile(
            icon: Icons.phone_outlined,
            title: 'Show Phone Number',
            subtitle: 'Allow contacts to see your phone number',
            iconColor: AppColors.warning,
            trailing: Switch(
              value: _showPhoneNumber,
              onChanged: (v) {
                setState(() => _showPhoneNumber = v);
                _saveSettings();
              },
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.primary,
            ),
          ),
          SettingsTile(
            icon: Icons.group_add_outlined,
            title: 'Allow Group Invites',
            subtitle: 'Let others add you to group chats',
            iconColor: Colors.purple,
            trailing: Switch(
              value: _allowGroupInvites,
              onChanged: (v) {
                setState(() => _allowGroupInvites = v);
                _saveSettings();
              },
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.primary,
            ),
          ),
          const Divider(height: 1),
          SettingsTile(
            icon: Icons.lock_outline,
            title: 'App Lock',
            subtitle: 'Protect app with PIN or fingerprint',
            iconColor: AppColors.primaryDark,
            onTap: () => context.push('/home/profile/lock'),
          ),
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
                      Icons.info_outline,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Privacy settings control what information is visible to other users. '
                        'Changes take effect immediately.',
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
