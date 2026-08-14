import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'api_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static const _channel = MethodChannel('com.naji.najimessenger/notifications');

  static void Function(RemoteMessage)? onMessageOpenedApp;
  static void Function(String chatId, String reply)? onReply;

  Future<void> init() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    _setupBackgroundHandler();
    _setupForegroundHandler();
    _setupTokenRefresh();
    _setupNativeReplyListener();
    _checkInitialReply();
    await _registerToken();
  }

  void _setupNativeReplyListener() {
    _channel.setMethodCallHandler((call) async {
      debugPrint('[FCM] Native call: ${call.method}');
      if (call.method == 'onReply') {
        final args = call.arguments as Map;
        final chatId = args['chat_id'] as String?;
        final replyText = args['reply_text'] as String?;
        debugPrint('[FCM] Reply from native: chatId=$chatId text=$replyText');
        if (chatId != null && replyText != null && onReply != null) {
          onReply!(chatId, replyText);
        }
      }
      return null;
    });
  }

  void _checkInitialReply() async {
    try {
      final result = await _channel.invokeMethod('getInitialReply');
      if (result != null && result is Map) {
        final chatId = result['chat_id'] as String?;
        final replyText = result['reply_text'] as String?;
        debugPrint('[FCM] Initial reply: chatId=$chatId text=$replyText');
        if (chatId != null && replyText != null && onReply != null) {
          onReply!(chatId, replyText);
        }
      }
    } catch (e) {
      debugPrint('[FCM] getInitialReply error: $e');
    }
  }

  void _setupBackgroundHandler() {
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleMessageData(message.data);
    });
  }

  void _setupForegroundHandler() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final data = message.data;
      final type = data['type'] as String?;

      if (type == 'new_message') {
        final messageId = data['message_id'] as String?;
        if (messageId != null) {
          _sendDeliveryReceiptForeground(messageId);
        }

        // Check if notifications are enabled
        final prefs = await SharedPreferences.getInstance();
        final messagesEnabled = prefs.getBool('notif_messages') ?? true;
        final groupMessagesEnabled = prefs.getBool('notif_group_messages') ?? true;
        final isGroup = data['is_group'] == true || data['is_group'] == 'true';

        if (!messagesEnabled || (isGroup && !groupMessagesEnabled)) {
          debugPrint('[FCM] Notification suppressed by user settings');
          return;
        }

        // Check if this specific chat is muted
        final chatId = data['chat_id'] as String?;
        if (chatId != null) {
          final mutedChats = prefs.getStringList('muted_chats') ?? [];
          if (mutedChats.contains(chatId)) {
            debugPrint('[FCM] Chat $chatId is muted, skipping notification');
            return;
          }
        }
      }
    });
  }

  Future<void> _sendDeliveryReceiptForeground(String messageId) async {
    try {
      final success = await ApiService.markMessageDelivered(messageId);
      debugPrint('[FCM] Foreground delivery receipt sent for $messageId: $success');
    } catch (e) {
      debugPrint('[FCM] Failed to send foreground delivery receipt: $e');
    }
  }

  void _setupTokenRefresh() {
    _messaging.onTokenRefresh.listen((token) {
      debugPrint('[FCM] Token refreshed');
      _sendTokenToServer(token);
    });
  }

  Future<void> _registerToken() async {
    final token = await _messaging.getToken();
    if (token != null) {
      if (kDebugMode) debugPrint('[FCM] Token registered');
      await _sendTokenToServer(token);
    }
  }

  Future<void> _sendTokenToServer(String token) async {
    try {
      await ApiService.registerFcmToken(token);
      debugPrint('[FCM] Token registered on server');
    } catch (e) {
      debugPrint('[FCM] Failed to register token: $e');
    }
  }

  Future<void> reRegisterToken() async {
    final token = await _messaging.getToken();
    if (token != null) {
      debugPrint('[FCM] Re-registering token after login');
      await _sendTokenToServer(token);
    }
  }

  void _handleMessageData(Map<String, dynamic> data) {
    final chatId = data['chat_id'] as String?;
    final type = data['type'] as String?;

    if (type == 'new_message' && chatId != null && onMessageOpenedApp != null) {
      onMessageOpenedApp!(RemoteMessage(data: data));
    }
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background handler START: ${message.messageId}');

  final data = message.data;
  debugPrint('[FCM] Background data: $data');

  final type = data['type'] as String?;
  debugPrint('[FCM] Background type: $type');

  if (type == 'new_message') {
    final messageId = data['message_id'] as String?;
    debugPrint('[FCM] Background messageId=$messageId');

    // Only send delivery receipt for this specific message
    // Read receipt is sent when user OPENS the chat
    if (messageId != null) {
      debugPrint('[FCM] Sending delivery receipt for $messageId');
      await _sendDeliveryReceiptBackground(messageId);
    }
  }
  debugPrint('[FCM] Background handler END');
}

Future<void> _sendDeliveryReceiptBackground(String messageId) async {
  try {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'auth_token');
    if (token == null) return;

    await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/messages/$messageId/delivered'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    debugPrint('[FCM] Delivery receipt sent for $messageId');
  } catch (e) {
    debugPrint('[FCM] Failed to send delivery receipt: $e');
  }
}

void setupBackgroundMessaging() {
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
}
