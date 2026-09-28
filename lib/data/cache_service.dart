import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat.dart';
import '../models/message.dart';

class CacheService {
  CacheService._();
  static final instance = CacheService._();

  static const _keyPref = 'cache_enabled';
  static const _keyAesKey = 'cache_aes_key';

  final _storage = const FlutterSecureStorage();
  encrypt_lib.Key? _aesKey;
  bool _enabled = true;
  Directory? _cacheDir;
  Future<void>? _initFuture;

  bool get isEnabled => _enabled;

  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_keyPref) ?? true;
    if (!_enabled) return;

    await _loadOrGenerateKey();
    _cacheDir = await getApplicationCacheDirectory();
  }

  Future<void> get ready async {
    await (_initFuture ??= _init());
  }

  Future<void> setEnabled(bool value) async {
    await ready;
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPref, value);
    if (!value) {
      await clearAll();
    }
  }

  Future<void> _loadOrGenerateKey() async {
    final stored = await _storage.read(key: _keyAesKey);
    if (stored != null) {
      _aesKey = encrypt_lib.Key.fromBase64(stored);
    } else {
      _aesKey = encrypt_lib.Key.fromSecureRandom(32);
      await _storage.write(key: _keyAesKey, value: _aesKey!.base64);
    }
  }

  String _encrypt(String plainText) {
    if (_aesKey == null) return plainText;
    final iv = encrypt_lib.IV.fromSecureRandom(16);
    final encrypter = encrypt_lib.Encrypter(
      encrypt_lib.AES(_aesKey!, mode: encrypt_lib.AESMode.sic),
    );
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  String _decrypt(String cipherText) {
    if (_aesKey == null) return cipherText;
    try {
      final parts = cipherText.split(':');
      if (parts.length != 2) return cipherText;
      final iv = encrypt_lib.IV.fromBase64(parts[0]);
      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(_aesKey!, mode: encrypt_lib.AESMode.sic),
      );
      return encrypter.decrypt64(parts[1], iv: iv);
    } catch (_) {
      return cipherText;
    }
  }

  Uint8List encryptBytes(Uint8List bytes) {
    if (_aesKey == null) return bytes;
    final iv = encrypt_lib.IV.fromSecureRandom(16);
    final encrypter = encrypt_lib.Encrypter(
      encrypt_lib.AES(_aesKey!, mode: encrypt_lib.AESMode.sic),
    );
    final encrypted = encrypter.encryptBytes(bytes.toList(), iv: iv);
    // Prepend IV (16 bytes) to encrypted data
    final result = Uint8List(iv.bytes.length + encrypted.bytes.length);
    result.setRange(0, iv.bytes.length, iv.bytes);
    result.setRange(iv.bytes.length, result.length, encrypted.bytes);
    return result;
  }

  Uint8List decryptBytes(Uint8List data) {
    if (_aesKey == null) return data;
    try {
      final iv = encrypt_lib.IV(data.sublist(0, 16));
      final encrypted = encrypt_lib.Encrypted(data.sublist(16));
      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(_aesKey!, mode: encrypt_lib.AESMode.sic),
      );
      return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
    } catch (_) {
      return data;
    }
  }

  // ─── Chat list cache ───────────────────────────────────────

  Future<void> saveChats(List<ChatModel> chats) async {
    await ready;
    if (!_enabled || _cacheDir == null) return;
    try {
      final data = chats.map((c) => _chatToJson(c)).toList();
      final json = jsonEncode(data);
      final encrypted = _encrypt(json);
      final file = File('${_cacheDir!.path}/chats.enc');
      await file.writeAsString(encrypted);
    } catch (e) {
      debugPrint('[Cache] saveChats error: $e');
    }
  }

  Future<List<ChatModel>> loadChats() async {
    await ready;
    if (!_enabled || _cacheDir == null) return [];
    try {
      final file = File('${_cacheDir!.path}/chats.enc');
      if (!await file.exists()) return [];
      final encrypted = await file.readAsString();
      final json = _decrypt(encrypted);
      final data = jsonDecode(json) as List;
      return data.map((c) => _chatFromJson(c as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[Cache] loadChats error: $e');
      return [];
    }
  }

  Future<void> saveChatMessages(
    String chatId,
    Map<String, dynamic> data,
  ) async {
    await ready;
    if (!_enabled || _cacheDir == null || chatId.isEmpty) return;
    try {
      final file = File('${_cacheDir!.path}/messages_${chatId.hashCode}.enc');
      await file.writeAsString(_encrypt(jsonEncode(data)));
    } catch (e) {
      debugPrint('[Cache] saveChatMessages error: $e');
    }
  }

  Future<Map<String, dynamic>?> loadChatMessages(String chatId) async {
    await ready;
    if (!_enabled || _cacheDir == null || chatId.isEmpty) return null;
    try {
      final file = File('${_cacheDir!.path}/messages_${chatId.hashCode}.enc');
      if (!await file.exists()) return null;
      final decoded = jsonDecode(_decrypt(await file.readAsString()));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      debugPrint('[Cache] loadChatMessages error: $e');
      return null;
    }
  }

  /// Updates a message payload in the encrypted per-chat cache. Used for
  /// chain-derived check status so it survives app restarts and offline opens.
  Future<void> updateChatMessageContent(
    String chatId,
    String messageId,
    String content,
  ) async {
    final data = await loadChatMessages(chatId);
    if (data == null || data['messages'] is! List) return;
    final messages = (data['messages'] as List).map((entry) {
      if (entry is Map && entry['id'] == messageId) {
        return <String, dynamic>{
          ...Map<String, dynamic>.from(entry),
          'content': content,
        };
      }
      return entry;
    }).toList();
    await saveChatMessages(chatId, {...data, 'messages': messages});
  }

  Future<void> saveStories(List<Map<String, dynamic>> stories) async {
    await ready;
    if (!_enabled || _cacheDir == null) return;
    try {
      final file = File('${_cacheDir!.path}/stories.enc');
      await file.writeAsString(_encrypt(jsonEncode(stories)));
    } catch (e) {
      debugPrint('[Cache] saveStories error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> loadStories() async {
    await ready;
    if (!_enabled || _cacheDir == null) return [];
    try {
      final file = File('${_cacheDir!.path}/stories.enc');
      if (!await file.exists()) return [];
      final decoded = jsonDecode(_decrypt(await file.readAsString()));
      if (decoded is! List) return [];
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('[Cache] loadStories error: $e');
      return [];
    }
  }

  Map<String, dynamic> _chatToJson(ChatModel c) => {
    'id': c.id,
    'name': c.name,
    'avatarUrl': c.avatarUrl,
    'contactId': c.contactId,
    'unreadCount': c.unreadCount,
    'isOnline': c.isOnline,
    'isGroup': c.isGroup,
    'participantIds': c.participantIds,
    'lastActivity': c.lastActivity.toIso8601String(),
    'hasPublishedStory': c.hasPublishedStory,
    'isMuted': c.isMuted,
    'lastMessage': c.lastMessage != null
        ? {
            'id': c.lastMessage!.id,
            'senderId': c.lastMessage!.senderId,
            'content': c.lastMessage!.content,
            'type': c.lastMessage!.type.name,
            'timestamp': c.lastMessage!.timestamp.toIso8601String(),
            'isMe': c.lastMessage!.isMe,
            'fileName': c.lastMessage!.fileName,
            'fileSize': c.lastMessage!.fileSize,
          }
        : null,
  };

  ChatModel _chatFromJson(Map<String, dynamic> m) {
    MessageModel? lastMsg;
    if (m['lastMessage'] != null) {
      final lm = m['lastMessage'] as Map<String, dynamic>;
      lastMsg = MessageModel(
        id: lm['id'] as String? ?? '',
        senderId: lm['senderId'] as String? ?? '',
        content: lm['content'] as String? ?? '',
        type: MessageType.values.firstWhere(
          (t) => t.name == lm['type'],
          orElse: () => MessageType.text,
        ),
        timestamp:
            DateTime.tryParse(lm['timestamp'] as String? ?? '') ??
            DateTime.now(),
        isMe: lm['isMe'] as bool? ?? false,
        fileName: lm['fileName'] as String?,
        fileSize: lm['fileSize'] as String?,
      );
    }
    return ChatModel(
      id: m['id'] as String? ?? '',
      name: m['name'] as String? ?? '',
      avatarUrl: m['avatarUrl'] as String?,
      contactId: m['contactId'] as String?,
      lastMessage: lastMsg,
      unreadCount: (m['unreadCount'] as num?)?.toInt() ?? 0,
      isOnline: m['isOnline'] as bool? ?? false,
      isGroup: m['isGroup'] as bool? ?? false,
      participantIds: (m['participantIds'] as List?)?.cast<String>() ?? [],
      lastActivity:
          DateTime.tryParse(m['lastActivity'] as String? ?? '') ??
          DateTime.now(),
      hasPublishedStory: m['hasPublishedStory'] as bool? ?? false,
      isMuted: m['isMuted'] as bool? ?? false,
    );
  }

  // ─── Image cache ───────────────────────────────────────────

  Future<void> saveImage(String url, Uint8List bytes) async {
    await ready;
    if (!_enabled || _cacheDir == null) return;
    try {
      final dir = Directory('${_cacheDir!.path}/images');
      if (!await dir.exists()) await dir.create(recursive: true);
      final fileName = '${url.hashCode}.enc';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(encryptBytes(bytes));
    } catch (e) {
      debugPrint('[Cache] saveImage error: $e');
    }
  }

  Future<Uint8List?> loadImage(String url) async {
    await ready;
    if (!_enabled || _cacheDir == null) return null;
    try {
      final dir = Directory('${_cacheDir!.path}/images');
      final fileName = '${url.hashCode}.enc';
      final file = File('${dir.path}/$fileName');
      if (!await file.exists()) return null;
      final encrypted = await file.readAsBytes();
      return decryptBytes(encrypted);
    } catch (e) {
      debugPrint('[Cache] loadImage error: $e');
      return null;
    }
  }

  Future<void> clearAll() async {
    await ready;
    if (_cacheDir == null) return;
    try {
      final chatsFile = File('${_cacheDir!.path}/chats.enc');
      if (await chatsFile.exists()) await chatsFile.delete();
      final storiesFile = File('${_cacheDir!.path}/stories.enc');
      if (await storiesFile.exists()) await storiesFile.delete();
      final messageFiles = _cacheDir!.listSync().whereType<File>().where(
        (f) => f.path.contains('/messages_') && f.path.endsWith('.enc'),
      );
      for (final file in messageFiles) {
        await file.delete();
      }
      final imgDir = Directory('${_cacheDir!.path}/images');
      if (await imgDir.exists()) await imgDir.delete(recursive: true);
    } catch (_) {}
  }
}
