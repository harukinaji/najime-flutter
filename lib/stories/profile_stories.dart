import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';

import '../models/user.dart';
import '../widgets/profile_header.dart';
import '../widgets/qr_profile_card.dart';

final _sampleUser = UserModel(
  id: 'user1',
  displayName: 'Alice Johnson',
  username: 'alicej',
  bio: 'Flutter developer & coffee enthusiast',
  isOnline: true,
);

final _noBioUser = UserModel(
  id: 'user2',
  displayName: 'Bob Smith',
  username: 'bobsmith',
  bio: '',
);

final profileStories = [
  Story(
    name: 'Profile/ProfileHeader - With Bio',
    builder: (context) => ProfileHeader(user: _sampleUser),
  ),
  Story(
    name: 'Profile/ProfileHeader - No Bio',
    builder: (context) => ProfileHeader(user: _noBioUser),
  ),
  Story(
    name: 'Profile/QR Profile Card',
    builder: (context) => Center(
      child: QrProfileCard(
        data: 'najime://user/alicej',
        displayName: 'Alice Johnson',
        username: 'alicej',
      ),
    ),
  ),
  Story(
    name: 'Profile/QR Profile Card - Small',
    builder: (context) => Center(
      child: QrProfileCard(
        data: 'najime://user/bobsmith',
        displayName: 'Bob Smith',
        username: 'bobsmith',
        size: 200,
      ),
    ),
  ),
];
