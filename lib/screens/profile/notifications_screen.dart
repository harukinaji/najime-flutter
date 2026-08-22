import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_colors.dart';
import '../../widgets/settings_tile.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late bool _messageNotifications;
  late bool _callNotifications;
  late bool _groupMessageNotifications;
  late bool _sound;
  late bool _vibration;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _messageNotifications = true;
    _callNotifications = true;
    _groupMessageNotifications = true;
    _sound = true;
    _vibration = true;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _messageNotifications = prefs.getBool('notif_messages') ?? true;
      _callNotifications = prefs.getBool('notif_calls') ?? true;
      _groupMessageNotifications =
          prefs.getBool('notif_group_messages') ?? true;
      _sound = prefs.getBool('notif_sound') ?? true;
      _vibration = prefs.getBool('notif_vibration') ?? true;
      _loading = false;
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 8),
                SettingsTile(
                  icon: Icons.message_outlined,
                  title: 'Message Notifications',
                  subtitle: 'Get notified for new messages',
                  iconColor: AppColors.primary,
                  trailing: Switch(
                    value: _messageNotifications,
                    onChanged: (v) {
                      setState(() => _messageNotifications = v);
                      _saveSetting('notif_messages', v);
                    },
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.primary,
                  ),
                ),
                SettingsTile(
                  icon: Icons.call_outlined,
                  title: 'Call Notifications',
                  subtitle: 'Get notified for incoming calls',
                  iconColor: AppColors.success,
                  trailing: Switch(
                    value: _callNotifications,
                    onChanged: (v) {
                      setState(() => _callNotifications = v);
                      _saveSetting('notif_calls', v);
                    },
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.primary,
                  ),
                ),
                SettingsTile(
                  icon: Icons.forum_outlined,
                  title: 'Group Message Notifications',
                  subtitle: 'Get notified for group messages',
                  iconColor: Colors.purple,
                  trailing: Switch(
                    value: _groupMessageNotifications,
                    onChanged: (v) {
                      setState(() => _groupMessageNotifications = v);
                      _saveSetting('notif_group_messages', v);
                    },
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.primary,
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SettingsTile(
                  icon: Icons.volume_up_outlined,
                  title: 'Sound',
                  subtitle: 'Play sound for notifications',
                  iconColor: AppColors.warning,
                  trailing: Switch(
                    value: _sound,
                    onChanged: (v) {
                      setState(() => _sound = v);
                      _saveSetting('notif_sound', v);
                    },
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.primary,
                  ),
                ),
                SettingsTile(
                  icon: Icons.vibration,
                  title: 'Vibration',
                  subtitle: 'Vibrate for notifications',
                  iconColor: AppColors.error,
                  trailing: Switch(
                    value: _vibration,
                    onChanged: (v) {
                      setState(() => _vibration = v);
                      _saveSetting('notif_vibration', v);
                    },
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.primary,
                  ),
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
                              'Notification preferences are saved locally on this device. '
                              'Push notifications require system-level permissions.',
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
