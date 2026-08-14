import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../widgets/chat_tile.dart';
import '../widgets/message_bubble.dart';

final _now = DateTime.now();

final _sampleMessage = MessageModel(
  id: 'msg1',
  senderId: 'user2',
  content: 'Hey! How are you doing?',
  type: MessageType.text,
  timestamp: _now.subtract(const Duration(minutes: 5)),
  isMe: false,
  deliveryStatus: DeliveryStatus.read,
);

final _myMessage = MessageModel(
  id: 'msg2',
  senderId: 'me',
  content: 'I\'m great, thanks! Just working on the new feature.',
  type: MessageType.text,
  timestamp: _now.subtract(const Duration(minutes: 3)),
  isMe: true,
  deliveryStatus: DeliveryStatus.read,
  isEdited: true,
);

final _imageMessage = MessageModel(
  id: 'msg3',
  senderId: 'user2',
  content: '/uploads/photos/sample.jpg',
  type: MessageType.image,
  timestamp: _now.subtract(const Duration(minutes: 2)),
  isMe: false,
  deliveryStatus: DeliveryStatus.delivered,
);

final _voiceMessage = MessageModel(
  id: 'msg4',
  senderId: 'me',
  content: '/uploads/voice/sample.ogg',
  type: MessageType.voice,
  timestamp: _now.subtract(const Duration(minutes: 1)),
  isMe: true,
  voiceDurationMs: 15000,
  deliveryStatus: DeliveryStatus.sent,
);

final _pinnedMessage = MessageModel(
  id: 'msg5',
  senderId: 'user2',
  content: 'This is an important pinned message!',
  type: MessageType.text,
  timestamp: _now.subtract(const Duration(hours: 1)),
  isMe: false,
  isPinned: true,
  deliveryStatus: DeliveryStatus.delivered,
);

final _forwardedMessage = MessageModel(
  id: 'msg6',
  senderId: 'user2',
  content: 'Check this out!',
  type: MessageType.text,
  timestamp: _now.subtract(const Duration(minutes: 10)),
  isMe: false,
  forwardedFrom: const ForwardedFromInfo(
    originalSenderId: 'user3',
    originalSenderName: 'Alice',
  ),
  deliveryStatus: DeliveryStatus.delivered,
);

final _replyMessage = MessageModel(
  id: 'msg7',
  senderId: 'me',
  content: 'Sure, I\'ll take a look.',
  type: MessageType.text,
  timestamp: _now.subtract(const Duration(minutes: 8)),
  isMe: true,
  replyToId: 'msg1',
  replyToContent: 'Hey! How are you doing?',
  replyToSenderName: 'Bob',
  deliveryStatus: DeliveryStatus.read,
);

final _premiumMessage = MessageModel(
  id: 'msg8',
  senderId: 'user2',
  content: 'This is a premium locked message with exclusive content.',
  type: MessageType.premiumMessage,
  timestamp: _now.subtract(const Duration(minutes: 15)),
  isMe: false,
  premiumInfo: const PremiumUnlockInfo(
    assetSymbol: 'NAJI',
    amount: 5.0,
    isUnlocked: false,
  ),
  deliveryStatus: DeliveryStatus.delivered,
);

final _stickerMessage = MessageModel(
  id: 'msg9',
  senderId: 'me',
  content: '/uploads/stickers/cute-cat.webm',
  type: MessageType.sticker,
  timestamp: _now.subtract(const Duration(minutes: 30)),
  isMe: true,
  deliveryStatus: DeliveryStatus.read,
);

final _sampleChat = ChatModel(
  id: 'chat1',
  name: 'Alice Johnson',
  lastMessage: _sampleMessage,
  unreadCount: 3,
  isOnline: true,
  lastActivity: _now.subtract(const Duration(minutes: 5)),
  hasPublishedStory: true,
);

final _groupChat = ChatModel(
  id: 'chat2',
  name: 'Flutter Devs Group',
  isGroup: true,
  unreadCount: 12,
  isOnline: false,
  lastMessage: MessageModel(
    id: 'm1',
    senderId: 'user5',
    content: 'Has anyone tried the new widget?',
    type: MessageType.text,
    timestamp: _now.subtract(const Duration(hours: 2)),
    isMe: false,
  ),
  lastActivity: _now.subtract(const Duration(hours: 2)),
  isMuted: true,
);

final _mutedChat = ChatModel(
  id: 'chat3',
  name: 'Spam Channel',
  lastActivity: _now.subtract(const Duration(days: 1)),
  unreadCount: 0,
  isMuted: true,
  lastMessage: MessageModel(
    id: 'm2',
    senderId: 'user6',
    content: 'Special offer! 50% off!',
    type: MessageType.text,
    timestamp: _now.subtract(const Duration(days: 1)),
    isMe: false,
  ),
);

final chatStories = [
  Story(
    name: 'Chat/Chat Tile - Unread',
    builder: (context) => Padding(
      padding: const EdgeInsets.all(8),
      child: ChatTile(chat: _sampleChat),
    ),
  ),
  Story(
    name: 'Chat/Chat Tile - Group Muted',
    builder: (context) => Padding(
      padding: const EdgeInsets.all(8),
      child: ChatTile(chat: _groupChat),
    ),
  ),
  Story(
    name: 'Chat/Chat Tile - No Unread Muted',
    builder: (context) => Padding(
      padding: const EdgeInsets.all(8),
      child: ChatTile(chat: _mutedChat),
    ),
  ),
  Story(
    name: 'Chat/Message Bubble - Received Text',
    builder: (context) => Padding(
      padding: const EdgeInsets.all(8),
      child: MessageBubble(message: _sampleMessage),
    ),
  ),
  Story(
    name: 'Chat/Message Bubble - Sent Text (edited)',
    builder: (context) => Padding(
      padding: const EdgeInsets.all(8),
      child: MessageBubble(message: _myMessage),
    ),
  ),
  Story(
    name: 'Chat/Message Bubble - Pinned',
    builder: (context) => Padding(
      padding: const EdgeInsets.all(8),
      child: MessageBubble(message: _pinnedMessage),
    ),
  ),
  Story(
    name: 'Chat/Message Bubble - Forwarded',
    builder: (context) => Padding(
      padding: const EdgeInsets.all(8),
      child: MessageBubble(message: _forwardedMessage),
    ),
  ),
  Story(
    name: 'Chat/Message Bubble - With Reply',
    builder: (context) => Padding(
      padding: const EdgeInsets.all(8),
      child: MessageBubble(message: _replyMessage),
    ),
  ),
  Story(
    name: 'Chat/Message Bubble - Premium Locked',
    builder: (context) => Padding(
      padding: const EdgeInsets.all(8),
      child: MessageBubble(message: _premiumMessage),
    ),
  ),
  Story(
    name: 'Chat/Message Bubble - Sticker',
    builder: (context) => Padding(
      padding: const EdgeInsets.all(8),
      child: MessageBubble(message: _stickerMessage),
    ),
  ),
  Story(
    name: 'Chat/Message Bubble - Voice',
    builder: (context) => Padding(
      padding: const EdgeInsets.all(8),
      child: MessageBubble(message: _voiceMessage),
    ),
  ),
  Story(
    name: 'Chat/Message Bubble - Image',
    builder: (context) => Padding(
      padding: const EdgeInsets.all(8),
      child: MessageBubble(message: _imageMessage),
    ),
  ),
];
