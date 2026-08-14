import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';

import '../widgets/google_icon.dart';
import '../widgets/phone_number_card.dart';
import '../widgets/settings_tile.dart';
import '../widgets/token_badge.dart';
import '../widgets/user_card.dart';

final commonStories = [
  Story(
    name: 'Common/TokenBadge',
    builder: (context) => const Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          TokenBadge(symbol: 'NAJI', balance: 1250.5),
          SizedBox(width: 12),
          TokenBadge(symbol: 'BTC', balance: 0.0523),
        ],
      ),
    ),
  ),
  Story(
    name: 'Common/SettingsTile',
    builder: (context) => const Column(
      children: [
        SettingsTile(
          icon: Icons.notifications,
          title: 'Notifications',
          subtitle: 'Manage your notification preferences',
        ),
        SettingsTile(
          icon: Icons.lock_outline,
          title: 'Privacy & Security',
          subtitle: 'Control your privacy settings',
        ),
        SettingsTile(
          icon: Icons.palette_outlined,
          title: 'Appearance',
        ),
      ],
    ),
  ),
  Story(
    name: 'Common/GoogleIcon',
    builder: (context) => const Padding(
      padding: EdgeInsets.all(16),
      child: GoogleIcon(size: 48),
    ),
  ),
  Story(
    name: 'Common/PhoneNumberCard - Empty',
    builder: (context) => const PhoneNumberCard(),
  ),
  Story(
    name: 'Common/PhoneNumberCard - Verified',
    builder: (context) => const PhoneNumberCard(
      phoneNumber: '+1 (555) 123-4567',
      isVerified: true,
    ),
  ),
  Story(
    name: 'Common/PhoneNumberCard - Unverified',
    builder: (context) => const PhoneNumberCard(
      phoneNumber: '+1 (555) 987-6543',
      isVerified: false,
    ),
  ),
  Story(
    name: 'Common/UserCard - With Avatar',
    builder: (context) => const UserCard(
      displayName: 'Alice Johnson',
      username: 'alicej',
      subtitle: 'Online',
    ),
  ),
  Story(
    name: 'Common/UserCard - No Username',
    builder: (context) => const UserCard(
      displayName: 'Bob Smith',
      subtitle: 'Last seen recently',
    ),
  ),
];
