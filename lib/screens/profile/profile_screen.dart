import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/auth_state.dart';
import '../../data/cache_service.dart';
import '../../models/user.dart';
import '../../widgets/profile_header.dart';
import '../../widgets/qr_profile_card.dart';
import '../../widgets/settings_tile.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _cacheEnabled = CacheService.instance.isEnabled;

  UserModel _userFromAuth() {
    final a = AuthState.instance;
    return UserModel(
      id: a.username ?? 'user',
      displayName: a.displayName ?? a.username ?? 'User',
      username: a.username ?? 'user',
      bio: a.bio ?? '',
      avatarUrl: a.avatarUrl,
      phoneNumber: null,
      isPremium: false,
    );
  }

  void _openEditProfile() async {
    await context.push('/home/profile/edit');
    if (!mounted) return;
    setState(() {});
  }

  void _showQrCode() {
    final user = _userFromAuth();
    QrProfileScreen.show(
      context,
      data: 'najime://profile/${user.username}',
      avatarUrl: user.avatarUrl,
      displayName: user.displayName,
      username: user.username,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ProfileHeader(
              user: _userFromAuth(),
              onEditAvatar: _openEditProfile,
              onQrTap: _showQrCode,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel(cs, 'Account'),
                  SettingsTile(
                    icon: Icons.person_outline,
                    title: 'Edit Profile',
                    onTap: _openEditProfile,
                  ),
                  SettingsTile(
                    icon: Icons.link,
                    title: 'Connected Accounts',
                    onTap: () => context.push('/home/profile/connected-accounts'),
                  ),
                  SettingsTile(
                    icon: Icons.folder_outlined,
                    title: 'Folders',
                    subtitle: 'Organize your chats',
                    onTap: () => context.push('/home/profile/folders'),
                  ),
                  SettingsTile(
                    icon: Icons.smart_toy_outlined,
                    title: 'My Bots',
                    subtitle: 'Create and manage bots',
                    onTap: () => context.push('/home/profile/bots'),
                  ),
                  SettingsTile(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Naji Wallet',
                    subtitle: 'Solana devnet wallet',
                    onTap: () => context.go('/home/wallet'),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel(cs, 'App Settings'),
                SettingsTile(
                  icon: Icons.lock_outline,
                  title: 'Privacy',
                  onTap: () => context.push('/home/profile/privacy'),
                ),
                SettingsTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  onTap: () => context.push('/home/profile/notifications'),
                ),
                SettingsTile(
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  onTap: () => context.push('/home/profile/appearance'),
                ),
                SettingsTile(
                  icon: Icons.cached_outlined,
                  title: 'Cache',
                  subtitle: _cacheEnabled
                      ? 'Chats & images cached (encrypted)'
                      : 'Disabled',
                  trailing: Switch(
                    value: _cacheEnabled,
                    onChanged: (v) async {
                      await CacheService.instance.setEnabled(v);
                      setState(() => _cacheEnabled = v);
                    },
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel(cs, 'Support'),
                SettingsTile(
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  onTap: () {},
                ),
                SettingsTile(
                  icon: Icons.logout,
                  title: 'Log Out',
                  iconColor: cs.error,
                  onTap: () async {
                    await AuthState.instance.logout();
                    if (!context.mounted) return;
                    context.go('/onboarding');
                  },
                ),
              ],
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }

  Widget _sectionLabel(ColorScheme cs, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
