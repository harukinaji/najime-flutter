import 'dart:io';
import 'package:flutter/foundation.dart';
import '../config.dart';
import '../models/story.dart';
import 'api_service.dart';

const _baseUrl = AppConfig.apiBaseUrl;

String _resolveUrl(String path) {
  if (path.startsWith('/')) return '$_baseUrl$path';
  return path;
}

class _StoryUserData {
  final String userId;
  final String userName;
  final String? userAvatar;
  final List<StoryModel> stories;

  _StoryUserData({
    required this.userId,
    required this.userName,
    this.userAvatar,
    required this.stories,
  });
}

class StoryService {
  StoryService._();
  static final instance = StoryService._();

  List<_StoryUserData> _users = [];
  String _myUserId = '';
  String _myUserName = '';
  String? _myAvatarUrl;

  List<StoryModel> get stories {
    final all = <StoryModel>[];
    for (final u in _users) {
      all.addAll(u.stories);
    }
    return all;
  }

  List<StoryModel> get myStories {
    for (final u in _users) {
      if (u.userId == _myUserId) return u.stories;
    }
    return [];
  }

  void setCurrentUser({required String id, required String name, String? avatarUrl}) {
    _myUserId = id;
    _myUserName = name;
    _myAvatarUrl = avatarUrl;
  }

  List<StoryModel> getStoriesForUser(String userId) {
    for (final u in _users) {
      if (u.userId == userId) return u.stories;
    }
    return [];
  }

  List<String> get usersWithStories => _users.map((u) => u.userId).toList();

  String getUserName(String userId) {
    for (final u in _users) {
      if (u.userId == userId) return u.userName;
    }
    return '';
  }

  String? getUserAvatar(String userId) {
    for (final u in _users) {
      if (u.userId == userId) return u.userAvatar;
    }
    return null;
  }

  Future<void> init() async {
    await fetchStories();
  }

  Future<void> fetchStories() async {
    try {
      final data = await ApiService.getStories();
      if (data == null) return;
      _users = data.map((u) {
        final userId = u['user_id'] as String;
        final stories = (u['stories'] as List).map((s) {
          final sMap = s as Map<String, dynamic>;
          final viewerIds = (sMap['viewers'] as List?)
                  ?.map((v) => (v as Map<String, dynamic>)['user_id'] as String)
                  .toList() ??
              [];
          final viewerCount = (sMap['viewer_count'] as int?) ?? 0;
          if (viewerIds.isEmpty && viewerCount > 0 && userId == _myUserId) {
            for (int i = 0; i < viewerCount; i++) viewerIds.add('');
          }
          return StoryModel(
            id: sMap['id'] as String,
            userId: userId,
            userName: u['user_name'] as String? ?? '',
            userAvatar: u['user_avatar'] != null ? _resolveUrl(u['user_avatar'] as String) : null,
            mediaPath: _resolveUrl(sMap['media_path'] as String),
            mediaType: sMap['media_type'] == 'video'
                ? StoryMediaType.video
                : StoryMediaType.image,
            timestamp: DateTime.tryParse(sMap['timestamp'] as String? ?? '') ??
                DateTime.now(),
            caption: sMap['caption'] as String?,
            viewerIds: viewerIds,
          );
        }).toList();
        final rawAvatar = u['user_avatar'] as String?;
        return _StoryUserData(
          userId: userId,
          userName: u['user_name'] as String? ?? '',
          userAvatar: rawAvatar != null ? _resolveUrl(rawAvatar) : null,
          stories: stories,
        );
      }).toList();
    } catch (e) {
      debugPrint('[StoryService] fetch error: $e');
    }
  }

  Future<bool> publishStory({
    required String mediaPath,
    required StoryMediaType mediaType,
    String? caption,
  }) async {
    try {
      final file = File(mediaPath);
      if (!await file.exists()) return false;

      final uploadResult = await ApiService.uploadFile(file, scope: 'public');
      if (uploadResult == null) return false;

      final fileUrl = uploadResult['file_url'] as String?;
      if (fileUrl == null) return false;

      final result = await ApiService.createStory(
        mediaPath: fileUrl,
        mediaType: mediaType == StoryMediaType.video ? 'video' : 'image',
        caption: caption,
      );
      if (result) {
        await fetchStories();
      }
      return result;
    } catch (e) {
      debugPrint('[StoryService] publish error: $e');
      return false;
    }
  }

  Future<void> addViewer(String storyId, String viewerId) async {
    await ApiService.viewStory(storyId);
  }
}
