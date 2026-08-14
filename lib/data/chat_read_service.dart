import 'package:flutter/foundation.dart';

/// Global notifier used to clear the unread badge in the chats list as soon
/// as a chat is opened (read). Emits the chat id that was just read.
class ChatReadService {
  ChatReadService._();

  static final ChatReadService instance = ChatReadService._();

  final ValueNotifier<String?> lastReadChatId = ValueNotifier(null);

  void markRead(String chatId) {
    lastReadChatId.value = chatId;
  }
}
