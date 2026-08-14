import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'platform.dart';

class DesktopChatSelection {
  final String chatId;
  final String? contactId;
  final bool isGroup;

  const DesktopChatSelection({
    required this.chatId,
    this.contactId,
    this.isGroup = false,
  });
}

class DesktopChatController {
  DesktopChatController._();
  static final DesktopChatController instance = DesktopChatController._();

  final ValueNotifier<DesktopChatSelection?> selected = ValueNotifier(null);

  void open({
    required String chatId,
    String? contactId,
    bool isGroup = false,
  }) {
    selected.value = DesktopChatSelection(
      chatId: chatId,
      contactId: contactId,
      isGroup: isGroup,
    );
  }

  void clear() => selected.value = null;
}

void openChat(
  BuildContext context, {
  required String chatId,
  String? contactId,
  bool isGroup = false,
}) {
  if (isDesktop) {
    context.go('/home/chats');
    DesktopChatController.instance.open(
      chatId: chatId,
      contactId: contactId,
      isGroup: isGroup,
    );
  } else {
    context.push('/home/chats/$chatId', extra: {
      'contactId': contactId,
      'isGroup': isGroup,
    });
  }
}
