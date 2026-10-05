import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/api_service.dart';
import '../../data/auth_state.dart';
import '../../data/cache_service.dart';
import '../../data/chat_read_service.dart';
import '../../data/voice_recording_service.dart';
import '../../data/websocket_service.dart';
import '../../models/message.dart';
import '../../models/call.dart';
import '../calls/call_screen.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/premium_message_card.dart';
import '../../widgets/sticker_picker.dart';
import '../../wallet/services/wallet_access_proxy.dart';
import '../../wallet/services/check_escrow_service.dart';
import '../../wallet/state/app_state.dart';
import 'forward_message_screen.dart';

import 'package:go_router/go_router.dart';

const _sentColor = Color(0xFF18A7B5);

class ChatDetailScreen extends StatefulWidget {
  final String chatId;
  final String? contactId;
  final bool isGroup;

  const ChatDetailScreen({
    super.key,
    required this.chatId,
    this.contactId,
    this.isGroup = false,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  int _scrollToBottomRequest = 0;

  List<MessageModel> _messages = [];
  bool _loading = true;
  bool _messagesRefreshInFlight = false;
  bool _profileSheetOpen = false;
  String _chatName = '';
  String? _chatAvatarUrl;
  String? _chatUsername;
  String? _cachedAvatarSource;
  Uint8List? _cachedAvatarBytes;
  bool _sending = false;
  bool _isOnline = false;
  String? _currentUserId;

  String? _editingMessageId;
  MessageModel? _replyingToMessage;

  // In-chat search state
  bool _isSearchingInChat = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<int> _searchMatchIndices = [];
  int _currentMatchIndex = -1;

  bool _isMuted = false;
  List<Map<String, dynamic>> _pinnedMessages = [];
  List<Map<String, dynamic>> _scheduledMessages = [];

  // Bot start button state
  Map<String, dynamic>? _botInfo;
  bool _startButtonPressed = false;
  final VoiceRecordingService _voiceService = VoiceRecordingService();
  bool _isRecording = false;
  bool _isRecordingLocked = false;
  bool _recordingStarting = false;
  bool _sendOnRecordingStart = false;
  double? _recordingStartY;
  double? _recordingStartX;
  bool _isCancellingRecording = false;
  bool _showStickerPicker = false;
  late final AnimationController _lockHintController;
  late final Animation<double> _lockHintOffset;
  Duration _recordDuration = Duration.zero;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<AmplitudeLevel>? _ampSub;
  List<double> _waveformBars = [];
  static const int _barCount = 40;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockHintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _lockHintOffset = Tween<double>(begin: 0, end: -7).animate(
      CurvedAnimation(parent: _lockHintController, curve: Curves.easeInOut),
    );
    _loadCurrentUser();
    _loadMessages();
    _loadBotInfo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
    WebSocketService.on('new_message', _onWsMessage);
    WebSocketService.on('status', _onStatus);
    WebSocketService.on('reaction_added', _onReactionAdded);
    WebSocketService.on('reaction_removed', _onReactionRemoved);
    WebSocketService.on('message_edited', _onMessageEdited);
    WebSocketService.on('invoice_paid', _onInvoicePaid);
    WebSocketService.on('message_deleted', _onMessageDeleted);
    WebSocketService.on('delivery_update', _onDeliveryUpdate);
    WebSocketService.on('messages_read', _onMessagesRead);
    WebSocketService.on('message_pinned', _onMessagePinned);
    WebSocketService.on('message_unpinned', _onMessageUnpinned);
    WebSocketService.on('callback_answer', _onCallbackAnswer);
    // Reload messages when WebSocket reconnects (handles offline->online)
    WebSocketService.onConnected = _onWsReconnected;
  }

  Future<void> _loadCurrentUser() async {
    final user = await ApiService.getCurrentUser();
    if (user != null && mounted) {
      setState(() => _currentUserId = user['id'] as String?);
    }
  }

  Future<void> _loadBotInfo() async {
    final contactId = widget.contactId;
    if (contactId == null || !contactId.startsWith('bot_')) return;
    final info = await ApiService.getBotInfo(contactId);
    if (info != null && mounted) {
      setState(() {
        _botInfo = info;
        _chatUsername = info['username'] as String?;
      });
    }
  }

  Future<String?> _resolveChatUsername() async {
    final cached = _chatUsername;
    if (cached != null && cached.isNotEmpty) return cached;

    if (AuthState.instance.isDemo) {
      final username = switch (widget.chatId) {
        'demo-alice' => 'alice',
        'demo-wallet' => 'wallet_support',
        _ => null,
      };
      _chatUsername = username;
      return username;
    }

    final contactId = widget.contactId;
    if (contactId == null || widget.isGroup) return null;

    final users = await ApiService.searchUsers(_chatName);
    for (final user in users) {
      if (user['id'] == contactId) {
        final username = user['username'] as String?;
        if (username != null && username.isNotEmpty) {
          _chatUsername = username;
          return username;
        }
      }
    }
    return null;
  }

  void _onStartPressed() {
    if (_botInfo == null) return;
    final command = _botInfo!['start_command'] as String? ?? '/start';
    _messageController.text = command;
    setState(() => _startButtonPressed = true);
    _sendMessage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockHintController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    WebSocketService.onConnected = null;
    WebSocketService.off('new_message', _onWsMessage);
    WebSocketService.off('status', _onStatus);
    WebSocketService.off('reaction_added', _onReactionAdded);
    WebSocketService.off('reaction_removed', _onReactionRemoved);
    WebSocketService.off('message_edited', _onMessageEdited);
    WebSocketService.off('invoice_paid', _onInvoicePaid);
    WebSocketService.off('message_deleted', _onMessageDeleted);
    WebSocketService.off('delivery_update', _onDeliveryUpdate);
    WebSocketService.off('messages_read', _onMessagesRead);
    WebSocketService.off('message_pinned', _onMessagePinned);
    WebSocketService.off('message_unpinned', _onMessageUnpinned);
    WebSocketService.off('callback_answer', _onCallbackAnswer);
    _durationSub?.cancel();
    _ampSub?.cancel();
    _voiceService.dispose();
    super.dispose();
  }

  void _onWsReconnected() {
    if (mounted) {
      _loadMessages();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadMessages();
    }
  }

  void _onStatus(dynamic data) {
    if (data is! Map) return;
    final userId = data['user_id'] as String?;
    final isOnline = data['is_online'] as bool?;
    if (userId == null || isOnline == null) return;
    if (userId == widget.contactId) {
      setState(() => _isOnline = isOnline);
    }
  }

  void _onReactionAdded(dynamic data) {
    if (data is! Map) return;
    final messageId = data['message_id'] as String?;
    final emoji = data['emoji'] as String?;
    final userId = data['user_id'] as String?;
    final displayName = data['display_name'] as String? ?? '';
    final avatarUrl = data['avatar_url'] as String? ?? '';
    if (messageId == null || emoji == null || userId == null) return;

    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;

    setState(() {
      final msg = _messages[idx];
      final reactions = List<Reaction>.from(msg.reactions);
      final rIdx = reactions.indexWhere((r) => r.emoji == emoji);
      if (rIdx >= 0) {
        final existing = reactions[rIdx];
        if (!existing.hasUser(userId)) {
          reactions[rIdx] = Reaction(
            emoji: emoji,
            users: [
              ...existing.users,
              ReactionUser(
                userId: userId,
                displayName: displayName,
                avatarUrl: avatarUrl,
              ),
            ],
          );
        }
      } else {
        reactions.add(
          Reaction(
            emoji: emoji,
            users: [
              ReactionUser(
                userId: userId,
                displayName: displayName,
                avatarUrl: avatarUrl,
              ),
            ],
          ),
        );
      }
      _messages[idx] = msg.copyWith(reactions: reactions);
    });
  }

  void _onReactionRemoved(dynamic data) {
    if (data is! Map) return;
    final messageId = data['message_id'] as String?;
    final emoji = data['emoji'] as String?;
    final userId = data['user_id'] as String?;
    if (messageId == null || emoji == null || userId == null) return;

    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;

    setState(() {
      final msg = _messages[idx];
      final reactions = List<Reaction>.from(msg.reactions);
      final rIdx = reactions.indexWhere((r) => r.emoji == emoji);
      if (rIdx >= 0) {
        final existing = reactions[rIdx];
        final updatedUsers = existing.users
            .where((u) => u.userId != userId)
            .toList();
        if (updatedUsers.isEmpty) {
          reactions.removeAt(rIdx);
        } else {
          reactions[rIdx] = Reaction(emoji: emoji, users: updatedUsers);
        }
      }
      _messages[idx] = msg.copyWith(reactions: reactions);
    });
  }

  Future<void> _handleKeyboardCallback(
    String messageId,
    String callbackData,
  ) async {
    if (kDebugMode)
      debugPrint('[Callback] messageId=$messageId data=$callbackData');
    try {
      final result = await ApiService.sendCallback(messageId, callbackData);
      if (kDebugMode) debugPrint('[Callback] result=$result');
      if (!result && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Callback failed')));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Callback] error=$e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send callback: $e')));
      }
    }
  }

  void _handleKeyboardSendMessage(String text) {
    _messageController.text = text;
    _sendMessage();
  }

  Future<void> _handleReaction(String messageId, String emoji) async {
    final msg = _messages.firstWhere((m) => m.id == messageId);
    final hasReacted = msg.reactions.any(
      (r) => r.emoji == emoji && r.hasUser(_currentUserId),
    );

    if (hasReacted) {
      await ApiService.removeReaction(messageId, emoji);
    } else {
      await ApiService.addReaction(messageId, emoji);
    }
  }

  void _onMessageEdited(dynamic data) {
    if (data is! Map) return;
    final messageId = data['message_id'] as String?;
    final newContent = data['content'] as String?;
    if (messageId == null || newContent == null) return;

    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;

    setState(() {
      _messages[idx] = _messages[idx].copyWith(
        content: newContent,
        isEdited: true,
      );
    });
  }

  void _onInvoicePaid(dynamic data) {
    if (data is! Map) return;
    final messageId = data['message_id'] as String?;
    final newContent = data['content'] as String?;
    if (messageId == null || newContent == null) return;

    _updateMessageContent(messageId, newContent);
  }

  void _updateMessageContent(String messageId, String newContent) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    setState(() {
      _messages[idx] = _messages[idx].copyWith(content: newContent);
    });
    unawaited(
      CacheService.instance.updateChatMessageContent(
        widget.chatId,
        messageId,
        newContent,
      ),
    );
  }

  void _onCallbackAnswer(dynamic data) {
    if (data is! Map) return;
    final text = data['text'] as String? ?? '';
    final showAlert = data['show_alert'] as bool? ?? false;
    if (text.isEmpty) return;

    if (mounted) {
      if (showAlert) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            content: Text(text),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  void _onMessageDeleted(dynamic data) {
    if (data is! Map) return;
    final messageId = data['message_id'] as String?;
    if (messageId == null) return;

    setState(() {
      _messages.removeWhere((m) => m.id == messageId);
    });
  }

  void _onMessagePinned(dynamic data) {
    if (data is! Map) return;
    final chatId = data['chat_id'] as String?;
    if (chatId != widget.chatId) return;

    final messageId = data['message_id'] as String?;
    if (messageId == null) return;

    setState(() {
      final idx = _messages.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(isPinned: true);
      }
      // Add to pinned list if not already there
      if (!_pinnedMessages.any((p) => p['message_id'] == messageId)) {
        _pinnedMessages.insert(0, {
          'message_id': messageId,
          'pinned_by': data['pinned_by'] ?? '',
          'pinned_by_name': data['pinned_by_name'] ?? '',
          'pinned_at': data['pinned_at'] ?? '',
        });
      }
    });
  }

  void _onMessageUnpinned(dynamic data) {
    if (data is! Map) return;
    final chatId = data['chat_id'] as String?;
    if (chatId != widget.chatId) return;

    final messageId = data['message_id'] as String?;
    if (messageId == null) return;

    setState(() {
      final idx = _messages.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(isPinned: false);
      }
      _pinnedMessages.removeWhere((p) => p['message_id'] == messageId);
    });
  }

  Future<void> _pinMessage(MessageModel message) async {
    final success = await ApiService.pinMessage(widget.chatId, message.id);
    if (!mounted) return;
    if (success) {
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == message.id);
        if (idx != -1) {
          _messages[idx] = _messages[idx].copyWith(isPinned: true);
        }
        if (!_pinnedMessages.any((p) => p['message_id'] == message.id)) {
          _pinnedMessages.insert(0, {
            'message_id': message.id,
            'content': message.content,
          });
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message pinned'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _unpinMessage(MessageModel message) async {
    final success = await ApiService.unpinMessage(widget.chatId, message.id);
    if (!mounted) return;
    if (success) {
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == message.id);
        if (idx != -1) {
          _messages[idx] = _messages[idx].copyWith(isPinned: false);
        }
        _pinnedMessages.removeWhere((p) => p['message_id'] == message.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message unpinned'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _loadScheduledMessages() async {
    final scheduled = await ApiService.getScheduledMessages(widget.chatId);
    if (!mounted) return;
    setState(() {
      _scheduledMessages = scheduled;
    });
  }

  Future<void> _scheduleCurrentMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;

    final scheduledAt = DateTime(
      picked.year,
      picked.month,
      picked.day,
      time.hour,
      time.minute,
    );

    if (scheduledAt.isBefore(now)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scheduled time must be in the future'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final scheduledAtISO = scheduledAt.toUtc().toIso8601String();
    final replyTo = _replyingToMessage;

    final result = await ApiService.scheduleMessage(
      widget.chatId,
      text,
      replyToId: replyTo?.id,
      scheduledAt: scheduledAtISO,
    );

    if (!mounted) return;

    if (result != null) {
      _messageController.clear();
      setState(() => _replyingToMessage = null);
      _loadScheduledMessages();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Message scheduled for ${_formatScheduledDate(scheduledAt)}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to schedule message'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatScheduledDate(DateTime dt) {
    final now = DateTime.now();
    String day;
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      day = 'today';
    } else if (dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day + 1) {
      day = 'tomorrow';
    } else {
      day =
          '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    }
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$day at $time';
  }

  void _showScheduledMessagesSheet(ColorScheme cs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (ctx, scrollController) {
            return StatefulBuilder(
              builder: (ctx, setSheetState) {
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.schedule, size: 20, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Scheduled Messages',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_scheduledMessages.length}',
                            style: TextStyle(
                              fontSize: 14,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _scheduledMessages.isEmpty
                          ? Center(
                              child: Text(
                                'No scheduled messages',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: _scheduledMessages.length,
                              itemBuilder: (ctx, index) {
                                final msg = _scheduledMessages[index];
                                final content = msg['content'] as String? ?? '';
                                final scheduledAt =
                                    msg['scheduled_at'] as String? ?? '';
                                final msgType =
                                    msg['type'] as String? ?? 'text';

                                DateTime? dt;
                                try {
                                  dt = DateTime.parse(scheduledAt).toLocal();
                                } catch (_) {}

                                return ListTile(
                                  leading: Icon(
                                    msgType == 'voice'
                                        ? Icons.mic
                                        : msgType == 'image'
                                        ? Icons.photo
                                        : msgType == 'file'
                                        ? Icons.attach_file
                                        : Icons.message,
                                    color: cs.primary,
                                  ),
                                  title: Text(
                                    msgType == 'image'
                                        ? '📷 Photo'
                                        : msgType == 'voice'
                                        ? '🎤 Voice message'
                                        : msgType == 'file'
                                        ? '📎 File'
                                        : content,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  subtitle: dt != null
                                      ? Text(
                                          'Scheduled: ${_formatScheduledDate(dt)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        )
                                      : null,
                                  trailing: IconButton(
                                    icon: Icon(
                                      Icons.cancel_outlined,
                                      size: 20,
                                      color: cs.error,
                                    ),
                                    onPressed: () async {
                                      final msgId = msg['id'] as String?;
                                      if (msgId == null) return;
                                      final success =
                                          await ApiService.cancelScheduledMessage(
                                            msgId,
                                          );
                                      if (success && mounted) {
                                        setState(() {
                                          _scheduledMessages.removeAt(index);
                                        });
                                        setSheetState(() {});
                                        if (_scheduledMessages.isEmpty &&
                                            mounted) {
                                          Navigator.pop(ctx);
                                        }
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _onDeliveryUpdate(dynamic data) {
    if (data is! Map) return;
    final messageId = data['message_id'] as String?;
    final status = data['status'] as String?;
    if (messageId == null || status == null) return;

    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;

    setState(() {
      _messages[idx] = _messages[idx].copyWith(
        deliveryStatus: _parseDeliveryStatus(status),
      );
    });
  }

  void _onMessagesRead(dynamic data) {
    if (data is! Map) return;
    final chatId = data['chat_id'] as String?;
    if (chatId != widget.chatId) return;

    setState(() {
      _messages = _messages.map((m) {
        if (m.isMe && m.deliveryStatus != DeliveryStatus.read) {
          return m.copyWith(deliveryStatus: DeliveryStatus.read);
        }
        return m;
      }).toList();
    });
  }

  DeliveryStatus _parseDeliveryStatus(String s) {
    switch (s) {
      case 'sending':
        return DeliveryStatus.sending;
      case 'sent':
        return DeliveryStatus.sent;
      case 'delivered':
        return DeliveryStatus.delivered;
      case 'read':
        return DeliveryStatus.read;
      default:
        return DeliveryStatus.sent;
    }
  }

  void _sendReadReceipt() {
    WebSocketService.sendSignal('message_read', {
      'chat_id': widget.chatId,
      'contact_id': widget.contactId ?? '',
    });
  }

  void _startEditMessage(MessageModel message) {
    setState(() {
      _editingMessageId = message.id;
      _replyingToMessage = null;
      _messageController.text = message.content;
    });
    _messageFocusNode.requestFocus();
  }

  void _cancelEdit() {
    setState(() {
      _editingMessageId = null;
      _messageController.clear();
    });
  }

  void _startReply(MessageModel message) {
    setState(() {
      _replyingToMessage = message;
      _editingMessageId = null;
    });
    _messageFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyingToMessage = null);
  }

  Future<void> _editMessage() async {
    final text = _messageController.text.trim();
    final editId = _editingMessageId;
    if (text.isEmpty || editId == null || _sending) return;

    _sending = true;
    _messageController.clear();
    _messageFocusNode.requestFocus();

    final result = await ApiService.editMessage(editId, text);
    if (!mounted) return;

    if (result != null) {
      final idx = _messages.indexWhere((m) => m.id == editId);
      if (idx != -1) {
        setState(() {
          _messages[idx] = _messages[idx].copyWith(
            content: result['content'] as String? ?? text,
            isEdited: true,
          );
        });
      }
    }

    setState(() => _editingMessageId = null);
    _sending = false;
  }

  Future<void> _deleteMessage(MessageModel message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This message will be deleted for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final success = await ApiService.deleteMessage(message.id);
    if (!mounted) return;

    if (success) {
      setState(() {
        _messages.removeWhere((m) => m.id == message.id);
      });
    }
  }

  void _copyMessage(MessageModel message) {
    Clipboard.setData(ClipboardData(text: message.content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _forwardMessage(MessageModel message) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForwardMessageScreen(messageToForward: message),
      ),
    );
  }

  Future<void> _onWsMessage(dynamic data) async {
    if (data is Map && data['chat_id'] == widget.chatId) {
      final t = data['type'] as String?;
      MessageType type = MessageType.text;
      if (t == 'voice') type = MessageType.voice;
      if (t == 'image') type = MessageType.image;
      if (t == 'file') type = MessageType.file;
      if (t == 'sticker') type = MessageType.sticker;
      if (t == 'invoice') type = MessageType.invoice;
      if (t == 'premiumMessage') type = MessageType.premiumMessage;

      String content = data['content'] as String? ?? '';

      final msg = MessageModel(
        id: data['id'] as String,
        senderId: data['sender_id'] as String,
        content: content,
        type: type,
        timestamp: DateTime.parse(data['timestamp'] as String),
        isMe: false,
        premiumInfo: data['premium_info'] is Map
            ? PremiumUnlockInfo.fromJson(
                Map<String, dynamic>.from(data['premium_info'] as Map),
              )
            : null,
        voiceDurationMs: data['voice_duration_ms'] as int?,
        voiceWaveform: _parseWaveform(data['voice_waveform'] as String?),
        replyToId: data['reply_to_id'] as String?,
        replyToContent: data['reply_to_content'] as String?,
        replyToSenderName: data['reply_to_sender_name'] as String?,
        forwardedFrom: _parseForwardedFrom(
          data['forwarded_from'] as Map<String, dynamic>?,
        ),
        keyboard: data['keyboard'] != null
            ? InlineKeyboard.fromJson(data['keyboard'])
            : null,
      );
      if (mounted) {
        setState(() => _messages.add(msg));
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        // Auto-send delivery receipt
        WebSocketService.sendSignal('message_delivered', {
          'message_id': msg.id,
          'contact_id': msg.senderId,
        });
      }
    }
  }

  Future<void> _loadMessages({bool backgroundRefresh = false}) async {
    if (!mounted) return;
    if (_messagesRefreshInFlight) return;
    if (_messages.isNotEmpty) backgroundRefresh = true;
    _messagesRefreshInFlight = true;
    final messagesAtRefreshStart = List<MessageModel>.of(_messages);
    final messageIdsAtRefreshStart = _messages
        .map((message) => message.id)
        .toSet();
    if (!backgroundRefresh && _messages.isEmpty) {
      setState(() => _loading = true);
    }
    Map<String, dynamic>? data;
    var loadedFromCache = false;
    if (AuthState.instance.isDemo) {
      final now = DateTime.now();
      final isTeam = widget.chatId == 'demo-team';
      final name = switch (widget.chatId) {
        'demo-alice' => 'Alice',
        'demo-team' => 'NajiMe Team',
        'demo-wallet' => 'Wallet Support',
        _ => 'Demo Chat',
      };
      data = {
        'success': true,
        'chat_name': name,
        'messages': [
          {
            'id': '${widget.chatId}-welcome',
            'sender_id': isTeam ? 'demo-bob' : widget.chatId,
            'content': isTeam ? 'This is a demo group chat.' : 'This is a demo message. Use this chat to explore the interface.',
            'type': 'text',
            'timestamp': now
                .subtract(const Duration(minutes: 5))
                .toIso8601String(),
            'is_me': false,
          },
          {
            'id': '${widget.chatId}-reply',
            'sender_id': 'demo_user',
            'content': 'Message sent from the demo account.',
            'type': 'text',
            'timestamp': now
                .subtract(const Duration(minutes: 2))
                .toIso8601String(),
            'is_me': true,
          },
        ],
      };
      final cachedDemo = await CacheService.instance.loadChatMessages(
        widget.chatId,
      );
      if (cachedDemo != null) {
        final cachedMessages = cachedDemo['messages'];
        if (cachedMessages is List) {
          for (final message in cachedMessages) {
            if (message is! Map) continue;
            message['content'] = switch (message['content']) {
              'Это тестовая групповая переписка.' =>
                'This is a demo group chat.',
              'Это тестовое сообщение. Здесь можно проверить интерфейс чата.' => 'This is a demo message. Use this chat to explore the interface.',
              'Сообщение отправлено из демо-аккаунта.' =>
                'Message sent from the demo account.',
              final content => content,
            };
          }
        }
        data = cachedDemo;
      }
    } else {
      if (!backgroundRefresh) {
        data = await CacheService.instance.loadChatMessages(widget.chatId);
        loadedFromCache = data != null;
      }
      if (backgroundRefresh || data == null) {
        final serverData = await ApiService.getMessages(widget.chatId);
        if (serverData != null) {
          data = serverData;
          loadedFromCache = false;
        } else if (backgroundRefresh) {
          _messagesRefreshInFlight = false;
          return;
        } else {
          data = await CacheService.instance.loadChatMessages(widget.chatId);
          loadedFromCache = data != null;
        }
      }
    }
    if (!mounted) {
      _messagesRefreshInFlight = false;
      return;
    }

    if (data == null) {
      _messagesRefreshInFlight = false;
      _loading = false;
      setState(() {});
      return;
    }

    // Load mute status from local storage
    final prefs = await SharedPreferences.getInstance();
    _messagesRefreshInFlight = false;
    final mutedChats = prefs.getStringList('muted_chats') ?? [];
    _isMuted = mutedChats.contains(widget.chatId);

    _chatName = data['chat_name'] as String? ?? 'Chat';
    _chatAvatarUrl = data['avatar_url'] as String?;

    if (_chatName.isEmpty && widget.isGroup) {
      _chatName = 'Group Chat';
    }

    final msgs = data['messages'] as List? ?? [];
    if (data['success'] == true) {
      unawaited(CacheService.instance.saveChatMessages(widget.chatId, data));
    }
    final messagesArrivedDuringRefresh = backgroundRefresh
        ? _messages
              .where(
                (message) => !messageIdsAtRefreshStart.contains(message.id),
              )
              .toList()
        : const <MessageModel>[];
    _messages = [];
    for (final m in msgs) {
      final msg = m as Map<String, dynamic>;
      MessageType type = MessageType.text;
      final t = msg['type'] as String?;
      switch (t) {
        case 'image':
          type = MessageType.image;
          break;
        case 'file':
          type = MessageType.file;
          break;
        case 'premiumMessage':
          type = MessageType.premiumMessage;
          break;
        case 'voice':
          type = MessageType.voice;
          break;
        case 'sticker':
          type = MessageType.sticker;
          break;
        case 'invoice':
          type = MessageType.invoice;
          break;
        case 'check':
          type = MessageType.check;
          break;
      }
      String content = msg['content'] as String? ?? '';
      _messages.add(
        MessageModel(
          id: msg['id'] as String,
          senderId: msg['sender_id'] as String,
          content: content,
          type: type,
          timestamp: DateTime.parse(msg['timestamp'] as String),
          isMe: msg['is_me'] as bool? ?? false,
          fileName: msg['file_name'] as String?,
          fileSize: msg['file_size'] as String?,
          premiumInfo: msg['premium_info'] is Map
              ? PremiumUnlockInfo.fromJson(
                  Map<String, dynamic>.from(msg['premium_info'] as Map),
                )
              : null,
          voiceDurationMs: msg['voice_duration_ms'] as int?,
          voiceWaveform: _parseWaveform(msg['voice_waveform'] as String?),
          reactions: _parseReactions(msg['reactions']),
          isEdited: msg['is_edited'] as bool? ?? false,
          replyToId: msg['reply_to_id'] as String?,
          replyToContent: msg['reply_to_content'] as String?,
          replyToSenderName: msg['reply_to_sender_name'] as String?,
          deliveryStatus: _parseDeliveryStatus(
            msg['delivery_status'] as String? ?? 'sent',
          ),
          forwardedFrom: _parseForwardedFrom(
            msg['forwarded_from'] as Map<String, dynamic>?,
          ),
          isPinned: msg['is_pinned'] as bool? ?? false,
          keyboard: msg['keyboard'] != null
              ? InlineKeyboard.fromJson(msg['keyboard'])
              : null,
        ),
      );
    }
    if (backgroundRefresh) {
      for (final message in messagesAtRefreshStart.where(
        (message) => message.id.startsWith('temp_'),
      )) {
        if (!_messages.any((loaded) => loaded.id == message.id)) {
          _messages.add(message);
        }
      }
      for (final message in messagesArrivedDuringRefresh) {
        if (!_messages.any((loaded) => loaded.id == message.id)) {
          _messages.add(message);
        }
      }
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
    _loading = false;
    setState(() {});

    if (loadedFromCache && !backgroundRefresh && !AuthState.instance.isDemo) {
      unawaited(_loadMessages(backgroundRefresh: true));
    }

    // Load pinned messages
    if (!backgroundRefresh) {
      _loadPinnedMessages();
      // Load scheduled messages
      _loadScheduledMessages();

      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      // Send delivery receipts for all messages from others (handles offline->online case)
      _sendDeliveryReceiptsForUndelivered();
      // Send read receipt for this chat
      _sendReadReceipt();
      // Clear the unread badge on the chats list + mark read on the server
      ApiService.markChatRead(widget.chatId);
      ChatReadService.instance.markRead(widget.chatId);
    }
  }

  void _sendDeliveryReceiptsForUndelivered() {
    for (final msg in _messages) {
      if (!msg.isMe && msg.deliveryStatus == DeliveryStatus.sent) {
        WebSocketService.sendSignal('message_delivered', {
          'message_id': msg.id,
          'contact_id': msg.senderId,
        });
      }
    }
  }

  Future<void> _loadPinnedMessages() async {
    final pinned = await ApiService.getPinnedMessages(widget.chatId);
    if (!mounted) return;
    setState(() {
      _pinnedMessages = pinned;
    });
  }

  Future<void> _scrollToBottom() async {
    final request = ++_scrollToBottomRequest;
    for (var attempt = 0; attempt < 3; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || request != _scrollToBottomRequest) return;
      if (!_scrollController.hasClients) continue;

      final position = _scrollController.position;
      final target = position.maxScrollExtent;
      if (target - position.pixels <= 2) continue;
      await _scrollController.animateTo(
        target,
        duration: Duration(milliseconds: attempt == 0 ? 240 : 100),
        curve: Curves.easeOut,
      );
    }

    if (mounted &&
        request == _scrollToBottomRequest &&
        _scrollController.hasClients) {
      final position = _scrollController.position;
      if (position.maxScrollExtent - position.pixels > 2) {
        _scrollController.jumpTo(position.maxScrollExtent);
      }
    }
  }

  Future<void> _saveDemoMessages() async {
    if (!AuthState.instance.isDemo) return;
    await CacheService.instance.saveChatMessages(widget.chatId, {
      'success': true,
      'chat_name': _chatName,
      'messages': _messages
          .map(
            (m) => {
              'id': m.id,
              'sender_id': m.senderId,
              'content': m.content,
              'type': m.type.name,
              'timestamp': m.timestamp.toIso8601String(),
              'is_me': m.isMe,
              'file_name': m.fileName,
              'file_size': m.fileSize,
              'voice_duration_ms': m.voiceDurationMs,
              'voice_waveform': m.voiceWaveform?.join(','),
            },
          )
          .toList(),
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    _sending = true;
    if (!_startButtonPressed) {
      setState(() => _startButtonPressed = true);
    }
    final replyTo = _replyingToMessage;
    _messageController.clear();
    _messageFocusNode.requestFocus();
    setState(() => _replyingToMessage = null);

    // Optimistic: add message immediately with 'sending' status
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMsg = MessageModel(
      id: tempId,
      senderId: _currentUserId ?? '',
      content: text,
      type: MessageType.text,
      timestamp: DateTime.now(),
      isMe: true,
      deliveryStatus: DeliveryStatus.sending,
      replyToId: replyTo?.id,
      replyToContent: replyTo?.content,
      replyToSenderName: replyTo?.isMe == true ? 'You' : null,
    );
    setState(() => _messages.add(optimisticMsg));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    if (AuthState.instance.isDemo) {
      final sent = optimisticMsg.copyWith(deliveryStatus: DeliveryStatus.sent);
      setState(() {
        _messages.removeWhere((m) => m.id == tempId);
        _messages.add(sent);
        _sending = false;
      });
      await _saveDemoMessages();
      return;
    }

    final result = await ApiService.sendMessage(
      widget.chatId,
      text,
      replyToId: replyTo?.id,
    );
    if (!mounted) return;

    if (result != null) {
      setState(() {
        _messages.removeWhere((m) => m.id == tempId);
        _messages.add(
          MessageModel(
            id: result['id'] as String,
            senderId: result['sender_id'] as String,
            content: result['content'] as String? ?? '',
            type: MessageType.text,
            timestamp: DateTime.parse(result['timestamp'] as String),
            isMe: true,
            deliveryStatus: _parseDeliveryStatus(
              result['delivery_status'] as String? ?? 'sent',
            ),
            replyToId: replyTo?.id,
            replyToContent: replyTo?.content,
            replyToSenderName: replyTo?.isMe == true ? 'You' : null,
          ),
        );
      });
    } else {
      setState(() => _messages.removeWhere((m) => m.id == tempId));
    }
    _sending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _sendSticker(String stickerUrl) async {
    if (_sending) return;
    _sending = true;
    setState(() => _showStickerPicker = false);

    final replyTo = _replyingToMessage;
    setState(() => _replyingToMessage = null);

    // Optimistic: add message immediately
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMsg = MessageModel(
      id: tempId,
      senderId: _currentUserId ?? '',
      content: stickerUrl,
      type: MessageType.sticker,
      timestamp: DateTime.now(),
      isMe: true,
      deliveryStatus: DeliveryStatus.sending,
      replyToId: replyTo?.id,
      replyToContent: replyTo?.content,
      replyToSenderName: replyTo?.isMe == true ? 'You' : null,
    );
    setState(() => _messages.add(optimisticMsg));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    final result = await ApiService.sendMessage(
      widget.chatId,
      stickerUrl,
      type: 'sticker',
      replyToId: replyTo?.id,
    );
    if (!mounted) return;

    if (result != null) {
      setState(() {
        _messages.removeWhere((m) => m.id == tempId);
        _messages.add(
          MessageModel(
            id: result['id'] as String,
            senderId: result['sender_id'] as String,
            content: result['content'] as String? ?? stickerUrl,
            type: MessageType.sticker,
            timestamp: DateTime.parse(result['timestamp'] as String),
            isMe: true,
            deliveryStatus: _parseDeliveryStatus(
              result['delivery_status'] as String? ?? 'sent',
            ),
            replyToId: replyTo?.id,
            replyToContent: replyTo?.content,
            replyToSenderName: replyTo?.isMe == true ? 'You' : null,
          ),
        );
      });
    } else {
      setState(() {
        _messages.removeWhere((m) => m.id == tempId);
      });
    }
    _sending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickAndSendFile() async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Photo'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAndSend(source: ImageSource.gallery, isImage: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAndSend(source: ImageSource.camera, isImage: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Video'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAndSend(source: ImageSource.gallery, isImage: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('File'),
              subtitle: const Text('Any file up to 4 GiB'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAndSendDocument();
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Invoice'),
              onTap: () async {
                Navigator.pop(ctx);
                await _showInvoiceComposer();
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Premium message'),
              subtitle: const Text('Unlock with a verified SOL payment'),
              onTap: () async {
                Navigator.pop(ctx);
                await _showPremiumComposer();
              },
            ),
            ListTile(
              leading: const Icon(Icons.card_giftcard),
              title: const Text('Check'),
              onTap: () async {
                Navigator.pop(ctx);
                await _showCheckComposer();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPremiumComposer() async {
    final contentController = TextEditingController();
    final amountController = TextEditingController();
    final draft = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Premium message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: contentController,
              minLines: 3,
              maxLines: 8,
              maxLength: 10000,
              decoration: const InputDecoration(
                labelText: 'Locked content',
                alignLabelWithHint: true,
              ),
            ),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Price in SOL',
                hintText: '0.01',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, {
              'content': contentController.text.trim(),
              'amount': amountController.text.trim(),
            }),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    contentController.dispose();
    amountController.dispose();
    if (draft == null || !mounted) return;
    final amount = double.tryParse(draft['amount'] ?? '');
    final content = draft['content'] ?? '';
    if (content.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter content and a positive SOL price')),
      );
      return;
    }
    final result = await ApiService.sendMessage(
      widget.chatId,
      jsonEncode({'content': content, 'amount': amount, 'currency': 'SOL'}),
      type: 'premiumMessage',
    );
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verify your wallet before selling premium content'),
        ),
      );
      return;
    }
    final premium = result['premium_info'] is Map
        ? PremiumUnlockInfo.fromJson(
            Map<String, dynamic>.from(result['premium_info'] as Map),
          )
        : null;
    setState(() {
      _messages.add(
        MessageModel(
          id: result['id'] as String,
          senderId: result['sender_id'] as String,
          content: result['content'] as String? ?? content,
          type: MessageType.premiumMessage,
          timestamp: DateTime.parse(result['timestamp'] as String),
          isMe: true,
          premiumInfo: premium,
        ),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _pickAndSendDocument() async {
    try {
      final picked = await openFile();
      if (picked == null) return;
      final file = File(picked.path);
      final size = await file.length();
      const maxSize = 4 * 1024 * 1024 * 1024;
      if (size > maxSize) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The maximum file size is 4 GiB')),
        );
        return;
      }

      final replyTo = _replyingToMessage;
      if (!mounted) return;
      setState(() {
        _sending = true;
        _replyingToMessage = null;
      });

      final sizeLabel = _formatFileSize(size);
      final audioMetadata = await _readAudioMetadata(file, picked.name);
      if (AuthState.instance.isDemo) {
        setState(() {
          _messages.add(
            MessageModel(
              id: 'demo_${DateTime.now().microsecondsSinceEpoch}',
              senderId: _currentUserId ?? 'demo_user',
              content: audioMetadata == null
                  ? picked.path
                  : jsonEncode({
                      'kind': 'audio',
                      'url': picked.path,
                      'metadata': audioMetadata,
                    }),
              type: MessageType.file,
              timestamp: DateTime.now(),
              isMe: true,
              fileName: picked.name,
              fileSize: sizeLabel,
            ),
          );
          _sending = false;
        });
        await _saveDemoMessages();
        return;
      }

      final uploadResult = await ApiService.uploadFile(file);
      if (!mounted) return;
      if (uploadResult == null) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to upload file')));
        return;
      }

      final fileUrl = uploadResult['file_url'] as String? ?? '';
      final serverSize = uploadResult['file_size'] as String? ?? sizeLabel;
      final messageContent = audioMetadata == null
          ? fileUrl
          : jsonEncode({
              'kind': 'audio',
              'url': fileUrl,
              'metadata': audioMetadata,
            });
      final sendResult = await ApiService.sendMessage(
        widget.chatId,
        messageContent,
        type: 'file',
        fileName: picked.name,
        fileSize: serverSize,
        replyToId: replyTo?.id,
      );
      if (!mounted) return;
      if (sendResult != null) {
        setState(() {
          _messages.add(
            MessageModel(
              id: sendResult['id'] as String,
              senderId: sendResult['sender_id'] as String,
              content: messageContent,
              type: MessageType.file,
              timestamp: DateTime.parse(sendResult['timestamp'] as String),
              isMe: true,
              fileName: picked.name,
              fileSize: serverSize,
              deliveryStatus: _parseDeliveryStatus(
                sendResult['delivery_status'] as String? ?? 'sent',
              ),
              replyToId: replyTo?.id,
              replyToContent: replyTo?.content,
              replyToSenderName: replyTo?.isMe == true ? 'You' : null,
            ),
          );
        });
      }
      setState(() => _sending = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to send file: $error')));
    }
  }

  String _formatFileSize(int bytes) {
    const units = ['B', 'KiB', 'MiB', 'GiB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return unit == 0
        ? '${value.toStringAsFixed(0)} ${units[unit]}'
        : '${value.toStringAsFixed(1)} ${units[unit]}';
  }

  Future<Map<String, dynamic>?> _readAudioMetadata(
    File file,
    String fileName,
  ) async {
    final extension = fileName.contains('.')
        ? '.${fileName.split('.').last.toLowerCase()}'
        : '';
    if (!supportedFileExtensions.contains(extension)) return null;
    try {
      return await compute(_readAudioMetadataInIsolate, file.path);
    } catch (_) {
      return {
        'title': fileName.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        'artist': '',
      };
    }
  }

  Future<void> _pickAndSend({
    required ImageSource source,
    required bool isImage,
  }) async {
    try {
      final XFile? picked;
      if (isImage) {
        picked = await _picker.pickImage(source: source, imageQuality: 80);
      } else {
        picked = await _picker.pickVideo(source: source);
      }
      if (picked == null) return;

      final file = File(picked.path);
      final fileName = picked.name;
      final replyTo = _replyingToMessage;

      if (!mounted) return;
      setState(() {
        _sending = true;
        _replyingToMessage = null;
      });

      if (AuthState.instance.isDemo) {
        final msg = MessageModel(
          id: 'demo_${DateTime.now().microsecondsSinceEpoch}',
          senderId: _currentUserId ?? 'demo_user',
          content: picked.path,
          type: isImage ? MessageType.image : MessageType.file,
          timestamp: DateTime.now(),
          isMe: true,
          fileName: fileName,
          fileSize: '${await file.length()} bytes',
        );
        setState(() {
          _messages.add(msg);
          _sending = false;
        });
        await _saveDemoMessages();
        return;
      }

      final uploadResult = await ApiService.uploadFile(file);
      if (!mounted) return;

      if (uploadResult != null) {
        final fileUrl = uploadResult['file_url'] as String?;
        final type = isImage ? 'image' : 'file';
        final sizeStr = uploadResult['file_size'] as String? ?? '';

        final sendResult = await ApiService.sendMessage(
          widget.chatId,
          fileUrl ?? '',
          type: type,
          fileName: fileName,
          fileSize: sizeStr,
          replyToId: replyTo?.id,
        );

        if (sendResult != null && mounted) {
          MessageType msgType = isImage ? MessageType.image : MessageType.file;
          setState(() {
            _messages.add(
              MessageModel(
                id: sendResult['id'] as String,
                senderId: sendResult['sender_id'] as String,
                content: fileUrl ?? '',
                type: msgType,
                timestamp: DateTime.parse(sendResult['timestamp'] as String),
                isMe: true,
                fileName: fileName,
                fileSize: sizeStr,
                deliveryStatus: _parseDeliveryStatus(
                  sendResult['delivery_status'] as String? ?? 'sent',
                ),
                replyToId: replyTo?.id,
                replyToContent: replyTo?.content,
                replyToSenderName: replyTo?.isMe == true ? 'You' : null,
              ),
            );
          });
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToBottom(),
          );
        }
      }
    } catch (e) {
      debugPrint('[Chat] File pick error: $e');
    }
    if (mounted) setState(() => _sending = false);
  }

  /// Opens the invoice composer (amount / currency / recipient / memo) and, on
  /// confirm, sends the invoice as a chat message with `type: 'invoice'`. The
  /// recipient defaults to the connected wallet ("Мой кошелёк") so the user
  /// can request payment to themselves, or a custom base58 address.
  Future<void> _showInvoiceComposer() async {
    final amountCtrl = TextEditingController(text: '0.005');
    final memoCtrl = TextEditingController();
    String currency = 'SOL';
    String recipientMode = 'self';
    final recipientCtrl = TextEditingController();
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return AlertDialog(
              title: const Text('New invoice'),
              content: SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: currency,
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'SOL', child: Text('SOL')),
                          DropdownMenuItem(value: 'USDC', child: Text('USDC')),
                          DropdownMenuItem(value: 'USDT', child: Text('USDT')),
                          DropdownMenuItem(
                            value: 'PYUSD',
                            child: Text('PYUSD'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setSheet(() => currency = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: recipientMode,
                        decoration: const InputDecoration(
                          labelText: 'Recipient',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'self',
                            child: Text('My wallet'),
                          ),
                          DropdownMenuItem(
                            value: 'custom',
                            child: Text('Custom address'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setSheet(() => recipientMode = v);
                        },
                      ),
                      if (recipientMode == 'custom') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: recipientCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Recipient address (base58)',
                            border: OutlineInputBorder(),
                          ),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: memoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Memo (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx, {
                      'amount': amountCtrl.text.trim(),
                      'currency': currency,
                      'recipient_mode': recipientMode,
                      'recipient': recipientCtrl.text.trim(),
                      'memo': memoCtrl.text.trim(),
                    });
                  },
                  child: const Text('Send'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null) return;

    final amount = double.tryParse(result['amount'] as String? ?? '');
    final coin = (result['currency'] as String?) ?? 'SOL';
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }

    String recipient;
    if (result['recipient_mode'] == 'self') {
      final binding = await const WalletAccessProxy().getBinding();
      if (!binding.bound || binding.publicKey == null) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('Wallet not connected')));
        return;
      }
      recipient = binding.publicKey!;
    } else {
      final r = (result['recipient'] as String?)?.trim() ?? '';
      if (r.isEmpty || r.length < 16) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Enter a valid recipient address')),
        );
        return;
      }
      recipient = r;
    }

    final memoRaw = (result['memo'] as String?)?.trim() ?? '';
    final invoice = InvoiceData(
      amount: amount,
      currency: coin,
      recipient: recipient,
      memo: memoRaw.isNotEmpty ? memoRaw : null,
    );

    await _sendInvoice(invoice);
  }

  Future<void> _sendInvoice(InvoiceData invoice) async {
    if (_sending) return;
    _sending = true;
    setState(() {});
    final replyTo = _replyingToMessage;
    setState(() => _replyingToMessage = null);

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimistic = MessageModel(
      id: tempId,
      senderId: _currentUserId ?? '',
      content: invoice.encode(),
      type: MessageType.invoice,
      timestamp: DateTime.now(),
      isMe: true,
      deliveryStatus: DeliveryStatus.sending,
      replyToId: replyTo?.id,
      replyToContent: replyTo?.content,
      replyToSenderName: replyTo?.isMe == true ? 'You' : null,
    );
    setState(() => _messages.add(optimistic));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    if (AuthState.instance.isDemo) {
      setState(() {
        _messages.removeWhere((m) => m.id == tempId);
        _messages.add(optimistic.copyWith(deliveryStatus: DeliveryStatus.sent));
        _sending = false;
      });
      await _saveDemoMessages();
      return;
    }

    final result = await ApiService.sendMessage(
      widget.chatId,
      invoice.encode(),
      type: 'invoice',
      replyToId: replyTo?.id,
    );
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _messages.removeWhere((m) => m.id == tempId);
        _messages.add(
          MessageModel(
            id: result['id'] as String,
            senderId: result['sender_id'] as String,
            content: result['content'] as String? ?? invoice.encode(),
            type: MessageType.invoice,
            timestamp: DateTime.parse(result['timestamp'] as String),
            isMe: true,
            deliveryStatus: _parseDeliveryStatus(
              result['delivery_status'] as String? ?? 'sent',
            ),
            replyToId: replyTo?.id,
            replyToContent: replyTo?.content,
            replyToSenderName: replyTo?.isMe == true ? 'You' : null,
          ),
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } else {
      setState(() => _messages.removeWhere((m) => m.id == tempId));
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _showCheckComposer() async {
    final amountCtrl = TextEditingController(text: '0.01');
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return AlertDialog(
              title: const Text('Create check'),
              content: SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount (SOL)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Devnet alpha: the SOL will be held in escrow and any chat participant can redeem this check.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx, {'amount': amountCtrl.text.trim()});
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null) return;

    final amount = double.tryParse(result['amount'] as String? ?? '');
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }

    // The open-redeem alpha contract does not assign a user wallet. A valid,
    // non-signer placeholder is stored in the create instruction; redemption
    // is authorized by the alpha contract for any signer.
    await _sendCheck(amount, '11111111111111111111111111111111');
  }

  Future<void> _sendCheck(double amount, String recipientAddress) async {
    if (_sending) return;

    final state = AppState.instance;
    if (state.wallet == null) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Wallet not connected')));
      return;
    }

    _sending = true;
    setState(() {});
    final replyTo = _replyingToMessage;
    setState(() => _replyingToMessage = null);

    final lamports = (amount * 1e9).round();
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final senderId = _currentUserId ?? '';
    // Usernames in the demo account can be shorter than eight characters.
    // Keep the check id deterministic without slicing past the string end.
    final idSuffix = senderId.length > 8 ? senderId.substring(0, 8) : senderId;
    final checkId = '${ts}_$idSuffix';

    String txSig = '';
    String pdaAddress = '';
    try {
      final escrowService = CheckEscrowService(state.solana.client);
      final (pda, tx) = await escrowService.createCheck(
        wallet: state.wallet,
        wcClient: state.walletConnectClient,
        feePayerAddress: state.wallet!.address,
        checkId: checkId,
        lamports: lamports,
        recipientAddress: recipientAddress,
      );
      pdaAddress = pda;
      txSig = tx;
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('Failed to create check: $e')));
      return;
    }

    // Demo chats still use a real Solana devnet escrow transaction. Only the
    // server-side registration is skipped because the demo account has no
    // backend identity; the signed transaction and local message are real.
    if (AuthState.instance.isDemo) {
      final checkData = CheckData(
        amount: amount,
        currency: 'SOL',
        creatorId: 'demo_user',
        status: 'active',
        txSignature: txSig,
        // Store the on-chain PDA in the chat payload. `checkId` above is only
        // the seed and may contain characters that are invalid in Base58.
        checkId: pdaAddress,
        creatorAddress: state.wallet!.address,
        recipientAddress: recipientAddress,
      );
      setState(() {
        _messages.add(
          MessageModel(
            id: 'demo_${DateTime.now().microsecondsSinceEpoch}',
            senderId: 'demo_user',
            content: checkData.encode(),
            type: MessageType.check,
            timestamp: DateTime.now(),
            isMe: true,
            deliveryStatus: DeliveryStatus.sent,
          ),
        );
        _sending = false;
      });
      await _saveDemoMessages();
      return;
    }

    Map<String, dynamic>? registered;
    for (var attempt = 0; attempt < 8; attempt++) {
      registered = await ApiService.createCheck(
        chatId: widget.chatId,
        pdaAddress: pdaAddress,
        recipientAddress: recipientAddress,
        amountLamports: lamports,
        currency: 'SOL',
        txSignature: txSig,
      );
      if (registered?['success'] == true) break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (registered?['success'] != true) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'Deposit submitted, registration pending. Check: $pdaAddress; transaction: $txSig',
            ),
          ),
        );
      }
      return;
    }

    final checkData = CheckData(
      amount: amount,
      currency: 'SOL',
      creatorId: _currentUserId ?? '',
      status: 'active',
      txSignature: txSig,
      checkId: pdaAddress,
      creatorAddress: state.wallet!.address,
      recipientAddress: recipientAddress,
    );

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimistic = MessageModel(
      id: tempId,
      senderId: _currentUserId ?? '',
      content: checkData.encode(),
      type: MessageType.check,
      timestamp: DateTime.now(),
      isMe: true,
      deliveryStatus: DeliveryStatus.sending,
      replyToId: replyTo?.id,
      replyToContent: replyTo?.content,
      replyToSenderName: replyTo?.isMe == true ? 'You' : null,
    );
    setState(() => _messages.add(optimistic));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    final result = await ApiService.sendMessage(
      widget.chatId,
      checkData.encode(),
      type: 'check',
      replyToId: replyTo?.id,
    );
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _messages.removeWhere((m) => m.id == tempId);
        _messages.add(
          MessageModel(
            id: result['id'] as String,
            senderId: result['sender_id'] as String,
            content: result['content'] as String? ?? checkData.encode(),
            type: MessageType.check,
            timestamp: DateTime.parse(result['timestamp'] as String),
            isMe: true,
            deliveryStatus: _parseDeliveryStatus(
              result['delivery_status'] as String? ?? 'sent',
            ),
            replyToId: replyTo?.id,
            replyToContent: replyTo?.content,
            replyToSenderName: replyTo?.isMe == true ? 'You' : null,
          ),
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } else {
      setState(() => _messages.removeWhere((m) => m.id == tempId));
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _startRecording(LongPressStartDetails details) async {
    if (_isRecording || _recordingStarting) return;

    setState(() {
      _recordingStarting = true;
      _isRecordingLocked = false;
      _sendOnRecordingStart = false;
      _recordingStartY = details.globalPosition.dy;
      _recordingStartX = details.globalPosition.dx;
      _isCancellingRecording = false;
    });
    final started = await _voiceService.startRecording();
    if (!started || !mounted) {
      if (mounted) setState(() => _recordingStarting = false);
      return;
    }

    _durationSub?.cancel();
    _durationSub = _voiceService.durationStream.listen((d) {
      if (mounted) setState(() => _recordDuration = d);
    });

    _waveformBars = List<double>.filled(_barCount, 0.0, growable: true);

    _ampSub?.cancel();
    _ampSub = _voiceService.amplitudeStream.listen((amp) {
      if (!mounted) return;
      final normalized = _normalizeAmplitude(amp.current);
      setState(() {
        _waveformBars.removeAt(0);
        _waveformBars.add(normalized);
      });
    });

    setState(() {
      _isRecording = true;
      _recordingStarting = false;
      _recordDuration = Duration.zero;
    });

    if (_sendOnRecordingStart && !_isRecordingLocked) {
      _sendOnRecordingStart = false;
      await _stopRecordingAndSend();
    }
  }

  void _handleRecordingPointerMove(PointerMoveEvent event) {
    final startY = _recordingStartY;
    final startX = _recordingStartX;
    if (startY == null ||
        startX == null ||
        _isRecordingLocked ||
        _isCancellingRecording ||
        (!_isRecording && !_recordingStarting)) {
      return;
    }

    if (startX - event.position.dx >= 64) {
      HapticFeedback.mediumImpact();
      setState(() => _isCancellingRecording = true);
      _cancelRecording();
      return;
    }

    // A short upward swipe while holding the microphone fixes the recording.
    if (startY - event.position.dy >= 56) {
      HapticFeedback.mediumImpact();
      setState(() => _isRecordingLocked = true);
    }
  }

  void _handleRecordingPointerUp(PointerUpEvent event) {
    _recordingStartY = null;
    _recordingStartX = null;
    if (_isCancellingRecording) return;
    if (_isRecordingLocked) return;

    if (_recordingStarting) {
      _sendOnRecordingStart = true;
    } else if (_isRecording) {
      _stopRecordingAndSend();
    }
  }

  double _normalizeAmplitude(double dB) {
    if (dB < -60) return 0.05;
    if (dB > 0) return 1.0;
    return ((dB + 60) / 60).clamp(0.05, 1.0);
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_isRecording) return;

    final path = await _voiceService.stopRecording();
    _durationSub?.cancel();
    _ampSub?.cancel();

    final durationMs = _recordDuration.inMilliseconds > 0
        ? _recordDuration.inMilliseconds
        : 1000;

    final waveform = List<double>.from(_waveformBars);

    if (mounted) {
      setState(() {
        _isRecording = false;
        _isRecordingLocked = false;
        _recordingStarting = false;
        _sendOnRecordingStart = false;
        _recordingStartY = null;
        _recordingStartX = null;
        _isCancellingRecording = false;
        _recordDuration = Duration.zero;
        _waveformBars = [];
      });
    }

    if (path == null || !mounted) return;

    await _sendVoiceMessage(File(path), durationMs, waveform);
  }

  Future<void> _cancelRecording() async {
    await _voiceService.cancelRecording();
    _durationSub?.cancel();
    _ampSub?.cancel();

    if (mounted) {
      setState(() {
        _isRecording = false;
        _isRecordingLocked = false;
        _recordingStarting = false;
        _sendOnRecordingStart = false;
        _recordingStartY = null;
        _recordingStartX = null;
        _isCancellingRecording = false;
        _recordDuration = Duration.zero;
        _waveformBars = [];
      });
    }
  }

  Future<void> _sendVoiceMessage(
    File audioFile,
    int durationMs,
    List<double> waveform,
  ) async {
    if (!mounted) return;
    final replyTo = _replyingToMessage;
    setState(() {
      _sending = true;
      _replyingToMessage = null;
    });

    if (AuthState.instance.isDemo) {
      final msg = MessageModel(
        id: 'demo_${DateTime.now().microsecondsSinceEpoch}',
        senderId: _currentUserId ?? 'demo_user',
        content: audioFile.path,
        type: MessageType.voice,
        timestamp: DateTime.now(),
        isMe: true,
        fileName: 'voice_message.m4a',
        fileSize: '${await audioFile.length()} bytes',
        voiceDurationMs: durationMs,
        voiceWaveform: waveform,
      );
      setState(() {
        _messages.add(msg);
        _sending = false;
      });
      await _saveDemoMessages();
      return;
    }

    try {
      final uploadResult = await ApiService.uploadFile(audioFile);
      if (!mounted) return;

      if (uploadResult != null) {
        final fileUrl = uploadResult['file_url'] as String?;
        final sizeStr = uploadResult['file_size'] as String? ?? '';

        final waveformJson = waveform
            .map((v) => v.toStringAsFixed(3))
            .join(',');

        final sendResult = await ApiService.sendMessage(
          widget.chatId,
          fileUrl ?? '',
          type: 'voice',
          fileName: 'voice_message.m4a',
          fileSize: sizeStr,
          voiceDurationMs: durationMs,
          voiceWaveform: waveformJson,
          replyToId: replyTo?.id,
        );

        if (sendResult != null && mounted) {
          final sentWaveform = _parseWaveform(
            sendResult['voice_waveform'] as String?,
          );
          setState(() {
            _messages.add(
              MessageModel(
                id: sendResult['id'] as String,
                senderId: sendResult['sender_id'] as String,
                content: fileUrl ?? '',
                type: MessageType.voice,
                timestamp: DateTime.parse(sendResult['timestamp'] as String),
                isMe: true,
                fileName: 'voice_message.m4a',
                fileSize: sizeStr,
                voiceDurationMs:
                    sendResult['voice_duration_ms'] as int? ?? durationMs,
                voiceWaveform: sentWaveform,
                deliveryStatus: _parseDeliveryStatus(
                  sendResult['delivery_status'] as String? ?? 'sent',
                ),
                replyToId: replyTo?.id,
                replyToContent: replyTo?.content,
                replyToSenderName: replyTo?.isMe == true ? 'You' : null,
              ),
            );
          });
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToBottom(),
          );
        }
      }
    } catch (e) {
      debugPrint('[Chat] Voice send error: $e');
    }

    if (mounted) setState(() => _sending = false);
  }

  List<double>? _parseWaveform(String? data) {
    if (data == null || data.isEmpty) return null;
    try {
      return data.split(',').map((s) => double.parse(s)).toList();
    } catch (_) {
      return null;
    }
  }

  List<Reaction> _parseReactions(dynamic data) {
    if (data == null || data is! List) return [];
    return data
        .map((r) {
          final reaction = r as Map<String, dynamic>;
          final usersList = (reaction['users'] as List?) ?? [];
          return Reaction(
            emoji: reaction['emoji'] as String? ?? '',
            users: usersList.map((u) {
              final user = u as Map<String, dynamic>;
              return ReactionUser(
                userId: user['user_id'] as String? ?? '',
                displayName: user['display_name'] as String? ?? '',
                avatarUrl: user['avatar_url'] as String? ?? '',
              );
            }).toList(),
          );
        })
        .where((r) => r.emoji.isNotEmpty)
        .toList();
  }

  ForwardedFromInfo? _parseForwardedFrom(Map<String, dynamic>? data) {
    if (data == null) return null;
    final senderId = data['original_sender_id'] as String?;
    final senderName = data['original_sender_name'] as String?;
    if (senderId == null || senderName == null) return null;
    return ForwardedFromInfo(
      originalSenderId: senderId,
      originalSenderName: senderName,
      originalChatName: data['original_chat_name'] as String?,
    );
  }

  // ── In-chat search ──────────────────────────────────────────────────

  void _toggleSearch() {
    setState(() {
      _isSearchingInChat = !_isSearchingInChat;
      if (_isSearchingInChat) {
        _searchFocusNode.requestFocus();
      } else {
        _closeSearch();
      }
    });
  }

  void _closeSearch() {
    setState(() {
      _isSearchingInChat = false;
      _searchQuery = '';
      _searchController.clear();
      _searchMatchIndices = [];
      _currentMatchIndex = -1;
    });
  }

  Future<void> _toggleMute() async {
    final prefs = await SharedPreferences.getInstance();
    final mutedChats = prefs.getStringList('muted_chats') ?? [];

    setState(() {
      _isMuted = !_isMuted;
      if (_isMuted) {
        mutedChats.add(widget.chatId);
        ApiService.muteChat(widget.chatId);
      } else {
        mutedChats.remove(widget.chatId);
        ApiService.unmuteChat(widget.chatId);
      }
    });

    await prefs.setStringList('muted_chats', mutedChats);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isMuted ? 'Notifications muted' : 'Notifications unmuted',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _onSearchQueryChanged(String q) {
    final query = q.trim().toLowerCase();
    setState(() {
      _searchQuery = q.trim();
      if (query.isEmpty) {
        _searchMatchIndices = [];
        _currentMatchIndex = -1;
        return;
      }
      _searchMatchIndices = [];
      for (int i = 0; i < _messages.length; i++) {
        if (_messages[i].content.toLowerCase().contains(query)) {
          _searchMatchIndices.add(i);
        }
      }
      _currentMatchIndex = _searchMatchIndices.isNotEmpty ? 0 : -1;
    });
    if (_searchMatchIndices.isNotEmpty) {
      _scrollToMatch(_searchMatchIndices[_currentMatchIndex]);
    }
  }

  void _nextMatch() {
    if (_searchMatchIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex + 1) % _searchMatchIndices.length;
    });
    _scrollToMatch(_searchMatchIndices[_currentMatchIndex]);
  }

  void _prevMatch() {
    if (_searchMatchIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex - 1 + _searchMatchIndices.length) %
          _searchMatchIndices.length;
    });
    _scrollToMatch(_searchMatchIndices[_currentMatchIndex]);
  }

  void _scrollToMatch(int messageIndex) {
    if (!_scrollController.hasClients) return;
    const double itemHeight = 72.0;
    final viewportHeight = _scrollController.position.viewportDimension;
    // Position the message near the bottom of the viewport (above input)
    final messageBottom = (messageIndex + 1) * itemHeight;
    final targetOffset = (messageBottom - viewportHeight + itemHeight).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Widget _buildSearchBar(ColorScheme cs) {
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: _closeSearch,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            Expanded(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: true,
                  style: TextStyle(fontSize: 14, color: cs.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    hintStyle: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onChanged: _onSearchQueryChanged,
                ),
              ),
            ),
            if (_searchMatchIndices.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                '${_currentMatchIndex + 1}/${_searchMatchIndices.length}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                onPressed: _prevMatch,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                onPressed: _nextMatch,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ] else if (_searchQuery.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                '0',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  void _startCall(CallType callType) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          contactId: widget.contactId ?? '',
          contactName: _chatName,
          callType: callType,
          useSFU: widget.isGroup,
          roomId: widget.chatId,
        ),
      ),
    );
  }

  Future<void> _openChatProfile() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final cs = Theme.of(context).colorScheme;
    final Future<Map<String, dynamic>?>? profileFuture =
        !widget.isGroup &&
            widget.contactId != null &&
            widget.contactId!.isNotEmpty &&
            !widget.contactId!.startsWith('bot_')
        ? ApiService.getUserProfile(widget.contactId!)
        : null;

    setState(() => _profileSheetOpen = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildAvatar(size: 88, showOnline: true),
                    const SizedBox(height: 14),
                    Text(
                      _chatName.isNotEmpty ? _chatName : 'Chat',
                      textAlign: TextAlign.center,
                      style: Theme.of(sheetContext).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    if (!widget.isGroup)
                      FutureBuilder<String?>(
                        future: _resolveChatUsername(),
                        builder: (context, snapshot) {
                          final username = snapshot.data;
                          if (username == null || username.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '@$username',
                              style: TextStyle(color: cs.primary),
                            ),
                          );
                        },
                      ),
                    Text(
                      widget.isGroup
                          ? 'Group chat'
                          : (_isOnline ? 'online' : 'offline'),
                      style: TextStyle(
                        color: !widget.isGroup && _isOnline
                            ? const Color(0xFF22C55E)
                            : cs.onSurfaceVariant,
                      ),
                    ),
                    if (profileFuture != null) ...[
                      const SizedBox(height: 14),
                      _buildProfileBioAndSongs(profileFuture, cs),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ProfileAction(
                          icon: Icons.chat_bubble_outline,
                          label: 'Message',
                          onTap: () => Navigator.pop(sheetContext),
                        ),
                        _ProfileAction(
                          icon: Icons.call_outlined,
                          label: 'Call',
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _startCall(CallType.voice);
                          },
                        ),
                        _ProfileAction(
                          icon: Icons.videocam_outlined,
                          label: 'Video',
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _startCall(CallType.video);
                          },
                        ),
                        _ProfileAction(
                          icon: _isMuted
                              ? Icons.notifications_outlined
                              : Icons.notifications_off_outlined,
                          label: _isMuted ? 'Unmute' : 'Mute',
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _toggleMute();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _profileSheetOpen = false);
    }
  }

  Widget _buildProfileBioAndSongs(
    Future<Map<String, dynamic>?> profileFuture,
    ColorScheme colorScheme,
  ) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          );
        }
        final profile = snapshot.data;
        if (profile == null) return const SizedBox.shrink();

        final bio = (profile['bio'] as String? ?? '').trim();
        final songs = (profile['songs'] as List? ?? const [])
            .whereType<Map>()
            .map((song) => Map<String, dynamic>.from(song))
            .toList();
        if (bio.isEmpty && songs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (bio.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'About',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(bio, style: Theme.of(context).textTheme.bodyMedium),
              ),
            ],
            if (songs.isNotEmpty) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Music',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 4),
              for (final song in songs)
                _buildProfileSongTile(song, colorScheme),
            ],
          ],
        );
      },
    );
  }

  Widget _buildProfileSongTile(
    Map<String, dynamic> song,
    ColorScheme colorScheme,
  ) {
    final title = song['title'] as String? ?? 'Untitled';
    final artist = song['artist'] as String? ?? '';
    final url = song['source_url'] as String? ?? '';
    final durationMs = (song['duration_ms'] as num?)?.toInt() ?? 0;
    Uint8List? artwork;
    final encoded = song['artwork_base64'] as String? ?? '';
    if (encoded.isNotEmpty) {
      try {
        artwork = base64Decode(encoded);
      } catch (_) {}
    }
    final duration = Duration(milliseconds: durationMs);
    final durationLabel =
        '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 46,
          child: artwork == null
              ? ColoredBox(
                  color: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.music_note_rounded,
                    color: colorScheme.primary,
                  ),
                )
              : Image.memory(
                  artwork,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => ColoredBox(
                    color: colorScheme.primaryContainer,
                    child: Icon(
                      Icons.music_note_rounded,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (artist.isNotEmpty) artist,
          if (durationMs > 0) durationLabel,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: ValueListenableBuilder<int>(
        valueListenable: musicPlayerRevision,
        builder: (context, _, __) => Icon(
          isProfileSongPlaying(url)
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          color: colorScheme.primary,
        ),
      ),
      onTap: url.isEmpty
          ? null
          : () => playProfileSong(
              url: url,
              title: title,
              artist: artist,
              durationMs: durationMs,
              artwork: artwork,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Semantics(
          button: true,
          label: 'Open chat profile',
          child: InkWell(
            onTap: _openChatProfile,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  _buildAvatar(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _chatName.isNotEmpty ? _chatName : 'Chat',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.contactId != null)
                          Text(
                            _isOnline ? 'online' : 'offline',
                            style: TextStyle(
                              fontSize: 12,
                              color: _isOnline
                                  ? const Color(0xFF22C55E)
                                  : Colors.white54,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            onPressed: () => _startCall(CallType.voice),
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () => _startCall(CallType.video),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'search') _toggleSearch();
              if (value == 'mute') _toggleMute();
              if (value == 'pinned')
                _showPinnedMessagesSheet(Theme.of(context).colorScheme);
              if (value == 'scheduled')
                _showScheduledMessagesSheet(Theme.of(context).colorScheme);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'search', child: Text('Search')),
              if (_pinnedMessages.isNotEmpty)
                PopupMenuItem(
                  value: 'pinned',
                  child: Row(
                    children: [
                      Icon(Icons.push_pin, size: 20),
                      const SizedBox(width: 12),
                      Text('Pinned (${_pinnedMessages.length})'),
                    ],
                  ),
                ),
              if (_scheduledMessages.isNotEmpty)
                PopupMenuItem(
                  value: 'scheduled',
                  child: Row(
                    children: [
                      Icon(Icons.schedule, size: 20),
                      const SizedBox(width: 12),
                      Text('Scheduled (${_scheduledMessages.length})'),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'mute',
                child: Row(
                  children: [
                    Icon(
                      _isMuted
                          ? Icons.notifications_active
                          : Icons.notifications_off,
                      size: 20,
                      color: _isMuted ? Colors.green : null,
                    ),
                    const SizedBox(width: 12),
                    Text(_isMuted ? 'Unmute' : 'Mute'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_pinnedMessages.isNotEmpty) _buildPinnedBanner(cs),
          if (_isSearchingInChat) _buildSearchBar(cs),
          Expanded(
            child: Stack(
              children: [
                Image.asset(
                  Theme.of(context).brightness == Brightness.dark
                      ? 'assets/images/dark_fruits.jpg'
                      : 'assets/images/light_fruits.jpg',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
                Positioned.fill(
                  child: Container(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                SafeArea(
                  top: !_isSearchingInChat,
                  bottom: false,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : _messages.isEmpty
                            ? _buildEmptyMessages(cs)
                            : _buildMessageList(),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          ignoring: _profileSheetOpen,
                          child: AnimatedSlide(
                            offset: _profileSheetOpen
                                ? const Offset(0, -0.35)
                                : Offset.zero,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            child: AnimatedOpacity(
                              opacity: _profileSheetOpen ? 0 : 1,
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOut,
                              child: const GlobalMusicMiniPlayer(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_botInfo != null && !_startButtonPressed && _messages.isEmpty)
            _buildBotStartButton(cs)
          else
            _buildMessageInput(cs),
        ],
      ),
    );
  }

  Widget _buildAvatar({double size = 36, bool showOnline = true}) {
    final avatarUrl = _chatAvatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    Widget? avatarImage;

    if (hasAvatar) {
      if (avatarUrl.startsWith('data:image')) {
        try {
          if (_cachedAvatarSource != avatarUrl) {
            final base64Data = avatarUrl.split(',').last;
            _cachedAvatarBytes = base64Decode(base64Data);
            _cachedAvatarSource = avatarUrl;
          }
          final bytes = _cachedAvatarBytes;
          if (bytes != null) {
            avatarImage = ClipOval(
              child: Image.memory(
                bytes,
                key: ValueKey(avatarUrl),
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            );
          }
        } catch (_) {}
      } else {
        avatarImage = ClipOval(
          child: Image.network(
            avatarUrl,
            key: ValueKey(avatarUrl),
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        );
      }
    }

    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: avatarImage != null ? Colors.transparent : Colors.white24,
          ),
          clipBehavior: Clip.antiAlias,
          child:
              avatarImage ??
              Center(
                child: Text(
                  _chatName.isNotEmpty ? _chatName[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.42,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
        ),
        if (showOnline && _isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        if (message.type == MessageType.premiumMessage &&
            message.premiumInfo != null) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: PremiumMessageCard(
              messageId: message.id,
              premiumInfo: message.premiumInfo!,
              content: message.content,
              onUnlocked: (content) {
                if (!mounted) return;
                setState(() {
                  final i = _messages.indexWhere((m) => m.id == message.id);
                  if (i >= 0) {
                    _messages[i] = _messages[i].copyWith(
                      content: content,
                      premiumInfo: message.premiumInfo!.copyWith(
                        isUnlocked: true,
                      ),
                    );
                  }
                });
              },
            ),
          );
        }
        return MessageBubble(
          message: message,
          currentUserId: _currentUserId,
          onReaction: (emoji) => _handleReaction(message.id, emoji),
          onEdit: () => _startEditMessage(message),
          onDelete: () => _deleteMessage(message),
          onCopy: () => _copyMessage(message),
          onReply: () => _startReply(message),
          onForward: () => _forwardMessage(message),
          onPin: () => _pinMessage(message),
          onUnpin: () => _unpinMessage(message),
          onKeyboardButton: (callbackData) =>
              _handleKeyboardCallback(message.id, callbackData),
          onKeyboardSendMessage: (text) => _handleKeyboardSendMessage(text),
          onInvoicePaid: (messageId, newContent) {
            _updateMessageContent(messageId, newContent);
          },
          searchQuery: _isSearchingInChat ? _searchQuery : null,
          isCurrentSearchMatch:
              _isSearchingInChat &&
              _currentMatchIndex >= 0 &&
              _currentMatchIndex < _searchMatchIndices.length &&
              _searchMatchIndices[_currentMatchIndex] == index,
        );
      },
    );
  }

  Widget _buildPinnedBanner(ColorScheme cs) {
    final latestPin = _pinnedMessages.first;
    final content = latestPin['content'] as String? ?? 'Pinned message';
    final pinnedByName = latestPin['pinned_by_name'] as String?;

    return GestureDetector(
      onTap: () => _showPinnedMessagesSheet(cs),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.08),
          border: Border(
            bottom: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.push_pin, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    content,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (pinnedByName != null && pinnedByName.isNotEmpty)
                    Text(
                      'Pinned by $pinnedByName',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (_pinnedMessages.length > 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_pinnedMessages.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showPinnedMessagesSheet(ColorScheme cs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (ctx, scrollController) {
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.push_pin, size: 20, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Pinned Messages',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_pinnedMessages.length}',
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _pinnedMessages.length,
                    itemBuilder: (ctx, index) {
                      final pin = _pinnedMessages[index];
                      final content = pin['content'] as String? ?? '';
                      final pinnedByName =
                          pin['pinned_by_name'] as String? ?? '';
                      final isMe = pin['is_me'] as bool? ?? false;
                      final msgType = pin['type'] as String? ?? 'text';

                      return ListTile(
                        leading: Container(
                          width: 3,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isMe ? _sentColor : cs.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        title: Text(
                          msgType == 'image'
                              ? '📷 Photo'
                              : msgType == 'voice'
                              ? '🎤 Voice message'
                              : msgType == 'file'
                              ? '📎 File'
                              : content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: cs.onSurface),
                        ),
                        subtitle: pinnedByName.isNotEmpty
                            ? Text(
                                'Pinned by $pinnedByName',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              )
                            : null,
                        trailing: IconButton(
                          icon: Icon(
                            Icons.push_pin,
                            size: 18,
                            color: cs.onSurfaceVariant,
                          ),
                          onPressed: () async {
                            final msgId = pin['message_id'] as String?;
                            if (msgId == null) return;
                            await ApiService.unpinMessage(widget.chatId, msgId);
                            if (!mounted) return;
                            setState(() {
                              _pinnedMessages.removeAt(index);
                              final msgIdx = _messages.indexWhere(
                                (m) => m.id == msgId,
                              );
                              if (msgIdx != -1) {
                                _messages[msgIdx] = _messages[msgIdx].copyWith(
                                  isPinned: false,
                                );
                              }
                            });
                            if (_pinnedMessages.isEmpty && mounted) {
                              Navigator.pop(ctx);
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyMessages(ColorScheme cs) {
    final isBot = _botInfo != null;
    final miniAppUrl = isBot ? (_botInfo!['mini_app_url'] as String?) : null;
    final hasMiniApp = miniAppUrl != null && miniAppUrl.trim().isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isBot) ...[
            Icon(
              Icons.smart_toy_outlined,
              size: 48,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              _botInfo!['display_name'] as String? ?? 'Bot',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _botInfo!['description'] as String? ??
                  'Press the button below to start',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
            if (hasMiniApp) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  context.push(
                    '/mini-app',
                    extra: {
                      'url': miniAppUrl,
                      'title':
                          _botInfo!['display_name'] as String? ?? 'Mini App',
                    },
                  );
                },
                icon: const Icon(Icons.open_in_browser, size: 20),
                label: const Text('Open Mini App'),
              ),
            ],
          ] else ...[
            Text(
              'No messages yet\nStart a conversation!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBotStartButton(ColorScheme cs) {
    final btnText = _botInfo!['start_button_text'] as String? ?? 'Start';
    final miniAppUrl = _botInfo!['mini_app_url'] as String?;
    final hasMiniApp = miniAppUrl != null && miniAppUrl.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasMiniApp)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {
                    context.push(
                      '/mini-app',
                      extra: {
                        'url': miniAppUrl,
                        'title':
                            _botInfo!['display_name'] as String? ?? 'Mini App',
                      },
                    );
                  },
                  icon: const Icon(Icons.open_in_browser, size: 20),
                  label: Text(
                    'Open Mini App',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            if (hasMiniApp) const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _onStartPressed,
                icon: const Icon(Icons.play_arrow, size: 22),
                label: Text(
                  btnText,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput(ColorScheme cs) {
    final hasText = _messageController.text.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showStickerPicker)
          StickerPicker(onStickerSelected: (url) => _sendSticker(url)),
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerMove: _handleRecordingPointerMove,
          onPointerUp: _handleRecordingPointerUp,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              bottom: true,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                reverseDuration: const Duration(milliseconds: 120),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(
                      begin: 0.98,
                      end: 1,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                child: (_isRecording || _recordingStarting)
                    ? KeyedSubtree(
                        key: const ValueKey('recording-input'),
                        child: _buildRecordingUI(cs),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('message-input'),
                        child: _buildNormalInput(cs, hasText),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNormalInput(ColorScheme cs, bool hasText) {
    final isEditing = _editingMessageId != null;
    final isReplying = _replyingToMessage != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isEditing)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              border: Border(left: BorderSide(color: cs.primary, width: 3)),
            ),
            child: Row(
              children: [
                Icon(Icons.edit, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Editing message',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: cs.primary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _cancelEdit,
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        if (isReplying)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.06),
              border: Border(left: BorderSide(color: cs.primary, width: 3)),
            ),
            child: Row(
              children: [
                Icon(Icons.reply, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _replyingToMessage!.isMe
                            ? 'Replying to yourself'
                            : 'Replying to message',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                      Text(
                        _replyingToMessage!.content,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _cancelReply,
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            if (_botInfo != null &&
                (_botInfo!['mini_app_url'] as String?)?.trim().isNotEmpty ==
                    true)
              IconButton(
                icon: Icon(Icons.open_in_browser, color: cs.primary),
                onPressed: (_sending || isEditing)
                    ? null
                    : () {
                        context.push(
                          '/mini-app',
                          extra: {
                            'url': _botInfo!['mini_app_url'],
                            'title':
                                _botInfo!['display_name'] as String? ??
                                'Mini App',
                          },
                        );
                      },
              )
            else
              IconButton(
                icon: Icon(Icons.attach_file, color: cs.onSurfaceVariant),
                onPressed: (_sending || isEditing) ? null : _pickAndSendFile,
              ),
            IconButton(
              icon: Icon(
                Icons.emoji_emotions_outlined,
                color: _showStickerPicker ? cs.primary : cs.onSurfaceVariant,
              ),
              onPressed: (_sending || isEditing)
                  ? null
                  : () => setState(() {
                      _showStickerPicker = !_showStickerPicker;
                      if (_showStickerPicker) {
                        _messageFocusNode.unfocus();
                      }
                    }),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  focusNode: _messageFocusNode,
                  textInputAction: TextInputAction.newline,
                  maxLines: 4,
                  minLines: 1,
                  style: TextStyle(fontSize: 15, color: cs.onSurface),
                  onChanged: (_) => setState(() {}),
                  onTap: () {
                    if (_showStickerPicker) {
                      setState(() => _showStickerPicker = false);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: isEditing
                        ? 'Edit message...'
                        : isReplying
                        ? 'Reply...'
                        : 'Message...',
                    hintStyle: TextStyle(color: cs.onSurfaceVariant),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (hasText) ...[
              GestureDetector(
                onLongPress: _scheduleCurrentMessage,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.schedule, color: cs.primary, size: 20),
                    onPressed: _scheduleCurrentMessage,
                    padding: EdgeInsets.zero,
                    tooltip: 'Schedule message',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: isEditing ? _editMessage : _sendMessage,
                  padding: EdgeInsets.zero,
                ),
              ),
            ] else if (!isEditing)
              GestureDetector(
                onLongPressStart: _startRecording,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mic, color: Colors.white, size: 20),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecordingUI(ColorScheme cs) {
    final isPreparing = _recordingStarting && !_isRecording;

    return Row(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.65, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          child: Text(
            isPreparing
                ? '00:00'
                : VoiceRecordingService.formatDuration(_recordDuration),
            key: ValueKey(isPreparing),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: isPreparing ? 0 : 1,
                child: SizedBox(
                  height: 32,
                  child: _waveformBars.isEmpty
                      ? const SizedBox.shrink()
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: List.generate(_waveformBars.length, (i) {
                            final height = _waveformBars[i] * 28.0 + 4.0;
                            return Expanded(
                              child: Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 130),
                                  curve: Curves.easeOutCubic,
                                  width: 2.5,
                                  height: height,
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: isPreparing
                    ? Text(
                        'Starting microphone…',
                        key: const ValueKey('preparing'),
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(Icons.delete_outline, color: cs.error),
          onPressed: isPreparing ? null : _cancelRecording,
        ),
        const SizedBox(width: 4),
        Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: isPreparing ? null : _stopRecordingAndSend,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isPreparing
                      ? cs.primary.withValues(alpha: 0.45)
                      : cs.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
            if (!isPreparing && !_isRecordingLocked)
              Positioned(
                right: 6,
                bottom: 45,
                child: AnimatedBuilder(
                  animation: _lockHintOffset,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, _lockHintOffset.value),
                    child: child,
                  ),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      color: cs.primary,
                      size: 17,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

Map<String, dynamic> _readAudioMetadataInIsolate(String path) {
  final metadata = readMetadata(File(path), getImage: true);
  final result = <String, dynamic>{};

  void putText(String key, String? value) {
    final normalized = value?.trim();
    if (normalized != null && normalized.isNotEmpty) result[key] = normalized;
  }

  putText('title', metadata.title);
  putText('artist', metadata.artist);
  putText('album', metadata.album);
  putText('album_artist', metadata.albumArtist);
  if (metadata.duration != null) {
    result['duration_ms'] = metadata.duration!.inMilliseconds;
  }
  if (metadata.year != null) result['year'] = metadata.year!.year;
  if (metadata.trackNumber != null) {
    result['track_number'] = metadata.trackNumber;
  }
  if (metadata.trackTotal != null) result['track_total'] = metadata.trackTotal;
  if (metadata.bitrate != null) result['bitrate'] = metadata.bitrate;
  if (metadata.sampleRate != null) result['sample_rate'] = metadata.sampleRate;

  if (metadata.pictures.isNotEmpty) {
    final cover = metadata.pictures.firstWhere(
      (picture) => picture.pictureType == PictureType.coverFront,
      orElse: () => metadata.pictures.first,
    );
    // Store a small UI thumbnail, not a multi-megabyte embedded cover scan.
    final decoded = img.decodeImage(cover.bytes);
    if (decoded != null) {
      final thumbnail = img.copyResize(
        decoded,
        width: 256,
        height: 256,
        interpolation: img.Interpolation.average,
      );
      final encoded = img.encodeJpg(thumbnail, quality: 82);
      result['art_base64'] = base64Encode(encoded);
      result['art_mime'] = 'image/jpeg';
    }
  }
  return result;
}
