import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';

import 'auth_stories.dart';
import 'chat_stories.dart';
import 'common_stories.dart';
import 'nav_stories.dart';
import 'premium_stories.dart';
import 'profile_stories.dart';
import 'reaction_stories.dart';
import 'sticker_stories.dart';

class StorybookScreen extends StatelessWidget {
  const StorybookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Storybook(
      initialStory: 'Common/SettingsTile',
      stories: [
        ...authStories,
        ...navStories,
        ...chatStories,
        ...commonStories,
        ...profileStories,
        ...stickerStories,
        ...reactionStories,
        ...premiumStories,
      ],
    );
  }
}

void openStorybook(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const StorybookScreen(),
    ),
  );
}
