import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';

import '../widgets/bottom_nav_bar.dart';

final navStories = [
  Story(
    name: 'Navigation/Bottom Nav - Chats',
    builder: (context) => Scaffold(
      body: const Center(child: Text('Content area')),
      bottomNavigationBar: BottomNavBar(currentIndex: 0, onTap: (_) {}),
    ),
  ),
  Story(
    name: 'Navigation/Bottom Nav - Contacts',
    builder: (context) => Scaffold(
      body: const Center(child: Text('Content area')),
      bottomNavigationBar: BottomNavBar(currentIndex: 1, onTap: (_) {}),
    ),
  ),
  Story(
    name: 'Navigation/Bottom Nav - Calls',
    builder: (context) => Scaffold(
      body: const Center(child: Text('Content area')),
      bottomNavigationBar: BottomNavBar(currentIndex: 2, onTap: (_) {}),
    ),
  ),
  Story(
    name: 'Navigation/Bottom Nav - Profile',
    builder: (context) => Scaffold(
      body: const Center(child: Text('Content area')),
      bottomNavigationBar: BottomNavBar(currentIndex: 3, onTap: (_) {}),
    ),
  ),
];
