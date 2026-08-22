import 'package:flutter/material.dart';

import '../../utils/platform.dart';
import '../../utils/desktop_chat.dart';
import 'chats_screen.dart';
import 'chat_detail_screen.dart';

class DesktopChatsSplit extends StatefulWidget {
  const DesktopChatsSplit({super.key});

  @override
  State<DesktopChatsSplit> createState() => _DesktopChatsSplitState();
}

class _DesktopChatsSplitState extends State<DesktopChatsSplit> {
  @override
  Widget build(BuildContext context) {
    if (!isDesktop) {
      return const ChatsScreen();
    }

    final cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<DesktopChatSelection?>(
      valueListenable: DesktopChatController.instance.selected,
      builder: (context, selection, _) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 360,
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(
                  right: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
              ),
              child: const ChatsScreen(),
            ),
            Expanded(
              child: selection == null
                  ? _EmptyChatPane(cs: cs)
                  : ChatDetailScreen(
                      key: ValueKey(selection.chatId),
                      chatId: selection.chatId,
                      contactId: selection.contactId,
                      isGroup: selection.isGroup,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyChatPane extends StatelessWidget {
  final ColorScheme cs;

  const _EmptyChatPane({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: cs.surfaceContainerLowest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 44,
                color: cs.primary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Select a chat to start messaging',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
