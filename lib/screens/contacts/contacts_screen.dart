import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as perm;

import '../../data/api_service.dart';
import '../../data/contacts_service.dart';
import '../../data/websocket_service.dart';
import '../../models/call.dart';
import '../../utils/desktop_chat.dart';
import '../calls/call_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<DeviceContactInfo> _contacts = [];
  List<DeviceContactInfo> _filtered = [];
  bool _loading = true;
  bool _noPermission = false;
  bool _permanentlyDenied = false;
  final Map<String, bool> _onlineStatus = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadContacts();
    WebSocketService.on('status', _onStatus);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    WebSocketService.off('status', _onStatus);
    super.dispose();
  }

  void _onStatus(dynamic data) {
    if (data is! Map) return;
    final userId = data['user_id'] as String?;
    final isOnline = data['is_online'] as bool?;
    if (userId == null || isOnline == null) return;
    setState(() => _onlineStatus[userId] = isOnline);
  }

  Future<void> _loadContacts() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final contacts = await NajiContactsService.fetchAndCheck();
    if (!mounted) return;

    if (await NajiContactsService.hasPermission()) {
      _contacts = contacts;
      _filtered = contacts;
      _noPermission = false;
      _permanentlyDenied = false;
    } else {
      _noPermission = true;
      final status = await perm.Permission.contacts.status;
      _permanentlyDenied = status.isPermanentlyDenied;
    }
    _loading = false;
    setState(() {});
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      setState(() => _filtered = _contacts);
    } else {
      setState(() => _filtered = NajiContactsService.searchLocal(q));
    }
  }

  int get _najiMeCount => _contacts.where((c) => c.isOnNajiMe).length;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: _contacts.isNotEmpty
            ? TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search contacts...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
              )
            : const Text('Contacts'),
        actions: [
          if (_contacts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => _searchController.clear(),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _noPermission
          ? _buildNoPermission(cs)
          : _contacts.isEmpty
          ? _buildEmpty(cs)
          : _buildContactList(cs),
      floatingActionButton: null,
    );
  }

  Widget _buildContactList(ColorScheme cs) {
    final najiMeCount = _najiMeCount;

    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No contacts match your search',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              '$najiMeCount on NajiMe',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '$najiMeCount of ${_contacts.length} contacts on NajiMe',
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: _filtered.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              indent: 72,
              endIndent: 16,
              color: cs.outlineVariant,
            ),
            itemBuilder: (context, index) {
              final contact = _filtered[index];
              return _buildContactTile(contact, cs);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildContactTile(DeviceContactInfo contact, ColorScheme cs) {
    if (contact.isOnNajiMe) {
      return ListTile(
        onTap: () => _showNajimeContactSheet(contact),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _buildNajiAvatar(contact, cs, showStatus: true),
        title: Row(
          children: [
            Flexible(
              child: Text(
                contact.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF18A7B5).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'NajiMe',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF18A7B5),
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          contact.najiMeUsername != null
              ? contact.najiMeUsername!
              : contact.phoneNumber,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _buildInitialAvatar(contact.name, cs),
      title: Text(
        contact.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: cs.onSurface,
        ),
      ),
      subtitle: Text(
        contact.phoneNumber.isNotEmpty
            ? contact.phoneNumber
            : 'No phone number',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _buildNajiAvatar(
    DeviceContactInfo contact,
    ColorScheme cs, {
    double size = 48,
    bool showStatus = false,
  }) {
    final isOnline =
        contact.najiMeUserId != null && _onlineStatus[contact.najiMeUserId] == true;
    Widget? avatarImage;

    if (contact.najiMeAvatarUrl != null &&
        contact.najiMeAvatarUrl!.isNotEmpty) {
      if (contact.najiMeAvatarUrl!.startsWith('data:image')) {
        try {
          final base64Data = contact.najiMeAvatarUrl!.split(',').last;
          final bytes = base64Decode(base64Data);
          avatarImage = ClipOval(
            child: Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  _buildInitialAvatar(contact.name, cs, size: size),
            ),
          );
        } catch (_) {}
      } else {
        avatarImage = ClipOval(
          child: Image.network(
            contact.najiMeAvatarUrl!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildInitialAvatar(contact.name, cs),
          ),
        );
      }
    }

    avatarImage ??= _buildInitialAvatar(contact.name, cs, size: size);

    if (showStatus) {
      final double dotSize = size * 0.3;
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatarImage,
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: isOnline
                      ? const Color(0xFF22C55E)
                      : const Color(0xFF787880),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cs.surface,
                    width: 2.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return avatarImage;
  }

  Widget _buildInitialAvatar(String name, ColorScheme cs, {double size = 44}) {
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _showNajimeContactSheet(DeviceContactInfo contact) {
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            _buildNajiAvatar(contact, cs, size: 64, showStatus: true),
            const SizedBox(height: 12),
            Text(
              contact.name,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            if (contact.najiMeUsername != null) ...[
              const SizedBox(height: 4),
              Text(
                contact.najiMeUsername!,
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: _buildActionChip(
                      cs: cs,
                      icon: Icons.chat_bubble_outline,
                      label: 'Message',
                      onTap: () async {
                        Navigator.pop(context);
                        final result = await ApiService.findOrCreateChat(
                          contact.najiMeUserId!,
                        );
                        if (!context.mounted) return;
                        if (result != null) {
                          openChat(context, chatId: result['chat_id']);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActionChip(
                      cs: cs,
                      icon: Icons.call_outlined,
                      label: 'Call',
                      onTap: () {
                        Navigator.pop(context);
                        if (contact.najiMeUserId != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CallScreen(
                                contactId: contact.najiMeUserId!,
                                contactName: contact.name,
                                contactAvatar: contact.najiMeAvatarUrl,
                                callType: CallType.voice,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActionChip(
                      cs: cs,
                      icon: Icons.videocam_outlined,
                      label: 'Video',
                      onTap: () {
                        Navigator.pop(context);
                        if (contact.najiMeUserId != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CallScreen(
                                contactId: contact.najiMeUserId!,
                                contactName: contact.name,
                                contactAvatar: contact.najiMeAvatarUrl,
                                callType: CallType.video,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip({
    required ColorScheme cs,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: cs.primary, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoPermission(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.contacts_outlined,
              size: 64,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              _permanentlyDenied
                  ? 'Contacts access is blocked'
                  : 'Contact access required',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _permanentlyDenied
                  ? 'Enable contacts access in Settings to find your friends on NajiMe'
                  : 'Grant contact access to find your friends on NajiMe',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _permanentlyDenied
                  ? () async {
                      await NajiContactsService.openSettings();
                    }
                  : () async {
                      final contacts =
                          await NajiContactsService.fetchAndCheck();
                      if (!mounted) return;
                      if (await NajiContactsService.hasPermission()) {
                        _contacts = contacts;
                        _filtered = contacts;
                        _noPermission = false;
                        _permanentlyDenied = false;
                      } else {
                        final status = await perm.Permission.contacts.status;
                        _permanentlyDenied = status.isPermanentlyDenied;
                      }
                      setState(() {});
                    },
              icon: Icon(_permanentlyDenied ? Icons.settings : Icons.contacts),
              label: Text(
                _permanentlyDenied ? 'Open Settings' : 'Grant Access',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF18A7B5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_outline,
            size: 64,
            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No contacts found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
