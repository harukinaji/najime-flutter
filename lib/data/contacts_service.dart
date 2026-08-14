import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart' as perm;

import 'api_service.dart';
import '../models/contact.dart';

class DeviceContactInfo {
  final String name;
  final String phoneNumber;
  final bool isOnNajiMe;
  final String? najiMeUserId;
  final String? najiMeUsername;
  final String? najiMeAvatarUrl;

  DeviceContactInfo({
    required this.name,
    required this.phoneNumber,
    this.isOnNajiMe = false,
    this.najiMeUserId,
    this.najiMeUsername,
    this.najiMeAvatarUrl,
  });
}

class NajiContactsService {
  static List<DeviceContactInfo> _cachedContacts = [];

  static List<DeviceContactInfo> get cachedContacts => _cachedContacts;

  static Future<bool> hasPermission() async {
    return await perm.Permission.contacts.status.isGranted;
  }

  static Future<bool> requestPermission() async {
    final status = await perm.Permission.contacts.request();
    return status.isGranted;
  }

  static Future<bool> openSettings() async {
    return await perm.openAppSettings();
  }

  static Future<List<DeviceContactInfo>> fetchAndCheck() async {
    _cachedContacts = [];

    if (!await hasPermission()) {
      final granted = await requestPermission();
      if (!granted) return [];
    }

    List<Contact> deviceContacts;
    try {
      deviceContacts = await FlutterContacts.getContacts(withProperties: true);
    } catch (_) {
      return [];
    }

    final phoneNumbers = <String>[];
    final phoneToDevice = <String, String>{};

    for (final c in deviceContacts) {
      for (final phone in c.phones) {
        if (phone.number.isEmpty) continue;
        final normalized = _normalizePhone(phone.number);
        if (normalized.length < 10) continue;
        phoneNumbers.add(normalized);
        phoneToDevice[normalized] = c.displayName.isNotEmpty
            ? c.displayName
            : '';
      }
    }

    final najiMeMap = <String, Map<String, dynamic>>{};
    if (phoneNumbers.isNotEmpty) {
      final result = await ApiService.checkContacts(phoneNumbers);
      if (result != null) {
        for (final u in result) {
          final phone = u['phone_number'] as String? ?? '';
          if (phone.isNotEmpty) {
            najiMeMap[phone] = u;
          }
        }
      }
    }

    final seen = <String>{};
    _cachedContacts = [];
    for (final c in deviceContacts) {
      final name = c.displayName.isNotEmpty ? c.displayName : 'Unknown';
      for (final phone in c.phones) {
        if (phone.number.isEmpty) continue;
        final normalized = _normalizePhone(phone.number);
        if (normalized.length < 10 || seen.contains(normalized)) continue;
        seen.add(normalized);

        final najiMeUser = najiMeMap[normalized];
        _cachedContacts.add(
          DeviceContactInfo(
            name: name,
            phoneNumber: normalized,
            isOnNajiMe: najiMeUser != null,
            najiMeUserId: najiMeUser?['id'] as String?,
            najiMeUsername: najiMeUser?['username'] as String?,
            najiMeAvatarUrl: najiMeUser?['avatar_url'] as String?,
          ),
        );
      }
      if (c.phones.isEmpty) {
        _cachedContacts.add(DeviceContactInfo(name: name, phoneNumber: ''));
      }
    }

    _cachedContacts.sort((a, b) => a.name.compareTo(b.name));
    return _cachedContacts;
  }

  static String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length >= 10) {
      return '+' + digits;
    }
    return digits;
  }

  static List<DeviceContactInfo> searchLocal(String query) {
    if (query.isEmpty) return _cachedContacts;
    final q = query.toLowerCase();
    return _cachedContacts.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.phoneNumber.contains(q) ||
          (c.najiMeUsername?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  static void clearCache() {
    _cachedContacts = [];
  }
}
