import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class WidgetService {
  static const _channel = MethodChannel('com.naji.najimessenger/widget');

  static Future<bool> updateWidget({
    required List<String> names,
    required List<String> messages,
    required List<String> unreads,
    required List<String> timestamps,
    required List<bool> onlineStatuses,
    required List<String> avatarUrls,
  }) async {
    try {
      final avatarPaths = await _cacheAvatars(avatarUrls);
      final result = await _channel.invokeMethod('updateWidget', {
        'names': names,
        'messages': messages,
        'unreads': unreads,
        'timestamps': timestamps,
        'onlineStatuses': onlineStatuses,
        'avatarPaths': avatarPaths,
      });
      return result == true;
    } catch (e) {
      return false;
    }
  }

  static Future<List<String>> _cacheAvatars(List<String> urls) async {
    final cacheDir = await getTemporaryDirectory();
    final avatarDir = Directory('${cacheDir.path}/widget_avatars');
    if (!await avatarDir.exists()) {
      await avatarDir.create(recursive: true);
    }

    final paths = <String>[];
    for (int i = 0; i < urls.length; i++) {
      final url = urls[i];
      if (url.isEmpty) {
        paths.add('');
        continue;
      }

      final fileName = 'avatar_$i.jpg';
      final file = File('${avatarDir.path}/$fileName');

      if (await file.exists()) {
        paths.add(file.path);
        continue;
      }

      try {
        final uri = Uri.parse(url);
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          await file.writeAsBytes(response.bodyBytes);
          paths.add(file.path);
        } else {
          paths.add('');
        }
      } catch (_) {
        paths.add('');
      }
    }
    return paths;
  }
}
