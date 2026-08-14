import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_service.dart';
import '../../models/contact.dart';
import '../../utils/desktop_chat.dart';
import '../../utils/platform.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _nameFocusNode = FocusNode();

  List<ContactModel> _searchResults = [];
  final List<ContactModel> _selectedContacts = [];
  bool _searchLoading = false;
  bool _creating = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _nameController.dispose();
    _nameFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _searchLoading = true);
      final users = await ApiService.searchUsers(q);
      if (!mounted) return;
      _searchLoading = false;
      _searchResults = users
          .where((u) => !_selectedContacts.any((s) => s.id == u['id']))
          .map(
            (u) => ContactModel(
              id: u['id'] as String,
              displayName: (u['display_name'] as String?) ?? '',
              username: u['username'] as String? ?? '',
              avatarUrl: u['avatar_url'] as String?,
              isBot: u['is_bot'] == true,
              description: u['description'] as String?,
            ),
          )
          .toList();
      setState(() {});
    });
  }

  void _toggleContact(ContactModel contact) {
    setState(() {
      final idx = _selectedContacts.indexWhere((c) => c.id == contact.id);
      if (idx >= 0) {
        _selectedContacts.removeAt(idx);
      } else {
        _selectedContacts.add(contact);
      }
    });
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a group name')),
      );
      return;
    }

    setState(() => _creating = true);

    final participantIds = _selectedContacts.map((c) => c.id).toList();
    final result = await ApiService.createGroupChat(
      name: name,
      participantIds: participantIds,
    );

    if (!mounted) return;

    setState(() => _creating = false);

    if (result != null) {
      final chatId = result['chat_id'] as String?;
      if (chatId != null) {
        if (isDesktop) {
          openChat(context, chatId: chatId, isGroup: true);
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        } else {
          context.pushReplacement('/home/chats/$chatId');
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to create group')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Group'),
        actions: [
          if (_selectedContacts.isNotEmpty)
            TextButton(
              onPressed: _creating ? null : _createGroup,
              child: _creating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Create',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildNameInput(cs),
          if (_selectedContacts.isNotEmpty) _buildSelectedChips(cs),
          _buildSearchField(cs),
          Expanded(
            child: _searchLoading
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? _buildEmptyState(cs)
                    : _buildSearchResults(cs),
          ),
        ],
      ),
    );
  }

  Widget _buildNameInput(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _nameController,
        focusNode: _nameFocusNode,
        style: TextStyle(fontSize: 16, color: cs.onSurface),
        decoration: InputDecoration(
          hintText: 'Group name',
          hintStyle: TextStyle(color: cs.onSurfaceVariant),
          border: InputBorder.none,
          prefixIcon: Icon(Icons.group, color: cs.onSurfaceVariant, size: 22),
        ),
      ),
    );
  }

  Widget _buildSelectedChips(ColorScheme cs) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedContacts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final contact = _selectedContacts[index];
          return Chip(
            avatar: _buildSmallAvatar(contact, cs),
            label: Text(
              contact.displayName,
              style: TextStyle(fontSize: 13, color: cs.onSurface),
            ),
            deleteIcon: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
            onDeleted: () => _toggleContact(contact),
            backgroundColor: cs.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          );
        },
      ),
    );
  }

  Widget _buildSmallAvatar(ContactModel contact, ColorScheme cs) {
    if (contact.avatarUrl != null && contact.avatarUrl!.isNotEmpty) {
      if (contact.avatarUrl!.startsWith('data:image')) {
        try {
          final base64Data = contact.avatarUrl!.split(',').last;
          final bytes = base64Decode(base64Data);
          return ClipOval(
            child: Image.memory(bytes, width: 24, height: 24, fit: BoxFit.cover),
          );
        } catch (_) {}
      } else {
        return ClipOval(
          child: Image.network(
            contact.avatarUrl!,
            width: 24,
            height: 24,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildAvatarFallback(contact, cs, size: 24),
          ),
        );
      }
    }
    return _buildAvatarFallback(contact, cs, size: 24);
  }

  Widget _buildSearchField(ColorScheme cs) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: cs.surface,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: TextStyle(color: cs.onSurface, fontSize: 15),
          cursorColor: cs.primary,
          decoration: InputDecoration(
            hintText: 'Search contacts...',
            hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults(ColorScheme cs) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchResults.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        indent: 72,
        endIndent: 16,
        color: cs.outlineVariant,
      ),
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        final isSelected = _selectedContacts.any((c) => c.id == user.id);
        return ListTile(
          onTap: () => _toggleContact(user),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: _buildUserAvatar(user, cs, size: 44),
          title: Text(
            user.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
          ),
          subtitle: Text(
            user.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          trailing: Icon(
            isSelected ? Icons.check_circle : Icons.add_circle_outline,
            color: isSelected ? cs.primary : cs.onSurfaceVariant,
            size: 28,
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.group_add,
            size: 56,
            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Search for contacts to add',
            style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildUserAvatar(
    ContactModel user,
    ColorScheme cs, {
    double size = 44,
  }) {
    if (user.avatarUrl != null && user.avatarUrl!.isNotEmpty) {
      if (user.avatarUrl!.startsWith('data:image')) {
        try {
          final base64Data = user.avatarUrl!.split(',').last;
          final bytes = base64Decode(base64Data);
          return ClipOval(
            child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover),
          );
        } catch (_) {}
      } else {
        return ClipOval(
          child: Image.network(
            user.avatarUrl!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildAvatarFallback(user, cs, size: size),
          ),
        );
      }
    }
    return _buildAvatarFallback(user, cs, size: size);
  }

  Widget _buildAvatarFallback(
    ContactModel user,
    ColorScheme cs, {
    double size = 44,
  }) {
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
          user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
