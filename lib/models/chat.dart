import 'message.dart';

class ChatModel {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? contactId;
  final MessageModel? lastMessage;
  final int unreadCount;
  final bool isOnline;
  final bool isGroup;
  final List<String> participantIds;
  final DateTime lastActivity;
  final bool hasPublishedStory;
  final bool isMuted;
  final bool isProtected;

  const ChatModel({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.contactId,
    this.lastMessage,
    this.unreadCount = 0,
    this.isOnline = false,
    this.isGroup = false,
    this.isProtected = false,
    this.participantIds = const [],
    required this.lastActivity,
    this.hasPublishedStory = false,
    this.isMuted = false,
  });

  ChatModel copyWith({
    String? name,
    String? avatarUrl,
    String? contactId,
    MessageModel? lastMessage,
    int? unreadCount,
    bool? isOnline,
    bool? hasPublishedStory,
    bool? isMuted,
  }) {
    return ChatModel(
      id: id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      contactId: contactId ?? this.contactId,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
      isGroup: isGroup,
      participantIds: participantIds,
      lastActivity: lastActivity,
      hasPublishedStory: hasPublishedStory ?? this.hasPublishedStory,
      isMuted: isMuted ?? this.isMuted,
    );
  }
}
