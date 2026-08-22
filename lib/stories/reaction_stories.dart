import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';

import '../models/message.dart';
import '../widgets/reaction_picker.dart';
import '../widgets/reaction_display.dart';

final _reactions = [
  Reaction(
    emoji: '👍',
    users: const [
      ReactionUser(userId: 'u1', displayName: 'Alice', avatarUrl: ''),
      ReactionUser(userId: 'u2', displayName: 'Bob', avatarUrl: ''),
    ],
  ),
  Reaction(
    emoji: '❤️',
    users: const [
      ReactionUser(userId: 'u3', displayName: 'Charlie', avatarUrl: ''),
    ],
  ),
  Reaction(
    emoji: '😂',
    users: const [
      ReactionUser(userId: 'u4', displayName: 'Diana', avatarUrl: ''),
      ReactionUser(userId: 'u5', displayName: 'Eve', avatarUrl: ''),
      ReactionUser(userId: 'u6', displayName: 'Frank', avatarUrl: ''),
    ],
  ),
];

final reactionStories = [
  Story(
    name: 'Reactions/Picker',
    builder: (context) => const Center(
      child: ReactionPicker(messageId: 'test1', onReaction: _noopStr),
    ),
  ),
  Story(
    name: 'Reactions/Display - Multiple',
    builder: (context) => Padding(
      padding: const EdgeInsets.all(16),
      child: ReactionDisplay(
        reactions: _reactions,
        isMe: false,
        onTap: _noopStr,
      ),
    ),
  ),
  Story(
    name: 'Reactions/Display - Own Message',
    builder: (context) => Padding(
      padding: const EdgeInsets.all(16),
      child: ReactionDisplay(
        reactions: _reactions,
        isMe: true,
        onTap: _noopStr,
      ),
    ),
  ),
  Story(
    name: 'Reactions/Display - Empty',
    builder: (context) => const Padding(
      padding: EdgeInsets.all(16),
      child: ReactionDisplay(reactions: [], isMe: false, onTap: _noopStr),
    ),
  ),
];

void _noopStr(String _) {}
