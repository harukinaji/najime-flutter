import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../../data/api_service.dart';
import '../../models/chat.dart';
import '../../models/message.dart';

class ForwardMessageScreen extends StatefulWidget {
  final MessageModel messageToForward;

  const ForwardMessageScreen({super.key, required this.messageToForward});

  @override
  State<ForwardMessageScreen> createState() => _ForwardMessageScreenState();
}

class _ForwardMessageScreenState extends State<ForwardMessageScreen> {
  List<ChatModel> _chats = [];
  bool _loading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Map<String, Uint8List> _avatarCache = {};

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    final raw = await ApiService.getChats();
    if (!mounted) return;

    try {
      _chats = raw.map((c) {
        MessageModel? lastMsg;
        if (c['last_message'] != null) {
          final m = c['last_message'] as Map<String, dynamic>;
          lastMsg = MessageModel(
            id: m['id'] as String? ?? '',
            senderId: m['sender_id'] as String? ?? '',
            content: m['content'] as String? ?? '',
            type: _parseMessageType(m['type'] as String?),
            timestamp:
                DateTime.tryParse(m['timestamp'] as String? ?? '') ??
                DateTime.now(),
            isMe: m['is_me'] as bool? ?? false,
          );
        }
        return ChatModel(
          id: c['id'] as String? ?? '',
          name: c['name'] as String? ?? '',
          avatarUrl: c['avatar_url'] as String?,
          contactId: c['contact_id'] as String?,
          lastMessage: lastMsg,
          unreadCount: (c['unread_count'] as num?)?.toInt() ?? 0,
          isOnline: c['is_online'] as bool? ?? false,
          isGroup: c['is_group'] as bool? ?? false,
          participantIds: (c['participant_ids'] as List?)?.cast<String>() ?? [],
          lastActivity:
              DateTime.tryParse(c['last_activity'] as String? ?? '') ??
              DateTime.now(),
        );
      }).toList();
    } catch (e) {
      _chats = [];
    }
    _loading = false;
    setState(() {});
  }

  MessageType _parseMessageType(String? t) {
    switch (t) {
      case 'image':
        return MessageType.image;
      case 'file':
        return MessageType.file;
      case 'premiumMessage':
        return MessageType.premiumMessage;
      case 'voice':
        return MessageType.voice;
      case 'sticker':
        return MessageType.sticker;
      case 'invoice':
        return MessageType.invoice;
      case 'check':
        return MessageType.check;
      default:
        return MessageType.text;
    }
  }

  List<ChatModel> get _filteredChats {
    if (_searchQuery.isEmpty) return _chats;
    return _chats.where((chat) {
      return chat.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  void _forwardToChat(ChatModel chat) async {
    final msg = widget.messageToForward;
    final content = msg.content;
    final type = msg.type == MessageType.image
        ? 'image'
        : msg.type == MessageType.voice
        ? 'voice'
        : msg.type == MessageType.file
        ? 'file'
        : 'text';

    final result = await ApiService.forwardMessage(
      sourceMessageId: msg.id,
      targetChatId: chat.id,
      content: content,
      type: type,
      fileName: msg.fileName,
      fileSize: msg.fileSize,
      voiceDurationMs: msg.voiceDurationMs,
      voiceWaveform: msg.voiceWaveform != null
          ? msg.voiceWaveform!.map((v) => v.toStringAsFixed(3)).join(',')
          : null,
    );

    if (!mounted) return;

    if (result != null) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Message forwarded to ${chat.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to forward message'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Forward to...'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: cs.onSurface, fontSize: 15),
                cursorColor: cs.primary,
                decoration: InputDecoration(
                  hintText: 'Search chats...',
                  hintStyle: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: cs.onSurfaceVariant,
                    size: 20,
                  ),
                ),
                onChanged: (q) => setState(() => _searchQuery = q.trim()),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _filteredChats.isEmpty
          ? Center(
              child: Text(
                'No chats found',
                style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _filteredChats.length,
              itemBuilder: (context, index) {
                final chat = _filteredChats[index];
                return _buildChatTile(chat, cs);
              },
            ),
    );
  }

  Widget _buildChatTile(ChatModel chat, ColorScheme cs) {
    final hasAvatar = chat.avatarUrl != null && chat.avatarUrl!.isNotEmpty;
    Widget? avatarImage;

    if (hasAvatar) {
      if (chat.avatarUrl!.startsWith('data:image')) {
        final cacheKey = chat.id;
        Uint8List? bytes = _avatarCache[cacheKey];
        if (bytes == null) {
          try {
            final base64Data = chat.avatarUrl!.split(',').last;
            bytes = base64Decode(base64Data);
            _avatarCache[cacheKey] = bytes;
          } catch (_) {}
        }
        if (bytes != null) {
          avatarImage = ClipOval(
            child: Image.memory(
              bytes,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
            ),
          );
        }
      } else {
        avatarImage = ClipOval(
          child: Image.network(
            chat.avatarUrl!,
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildAvatarFallback(chat, cs),
          ),
        );
      }
    }

    avatarImage ??= _buildAvatarFallback(chat, cs);

    return ListTile(
      onTap: () => _forwardToChat(chat),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        children: [
          avatarImage,
          if (chat.isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              chat.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
          ),
          if (chat.isGroup) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Group',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: chat.lastMessage != null
          ? Text(
              chat.lastMessage!.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            )
          : null,
    );
  }

  Widget _buildAvatarFallback(ChatModel chat, ColorScheme cs) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
        ),
      ),
      child: Center(
        child: Text(
          chat.name.isNotEmpty ? chat.name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
