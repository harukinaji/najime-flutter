import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';

import '../models/message.dart';
import '../widgets/premium_message_card.dart';

final _lockedInfo = const PremiumUnlockInfo(
  assetSymbol: 'NAJI',
  amount: 5.0,
  isUnlocked: false,
);

final _unlockedInfo = const PremiumUnlockInfo(
  assetSymbol: 'NAJI',
  amount: 5.0,
  isUnlocked: true,
);

final premiumStories = [
  Story(
    name: 'Premium/Card - Locked',
    builder: (context) => Padding(
      padding: const EdgeInsets.all(16),
      child: PremiumMessageCard(
        premiumInfo: _lockedInfo,
        content:
            'This is exclusive premium content that is locked behind a payment wall.',
      ),
    ),
  ),
  Story(
    name: 'Premium/Card - Unlocked',
    builder: (context) => Padding(
      padding: const EdgeInsets.all(16),
      child: PremiumMessageCard(
        premiumInfo: _unlockedInfo,
        content: 'Thank you for unlocking this exclusive premium content!',
      ),
    ),
  ),
];
