import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/api_service.dart';
import '../../data/auth_state.dart';
import '../../data/cache_service.dart';
import '../../data/chat_read_service.dart';
import '../../data/notification_service.dart';
import '../../data/story_service.dart';
import '../../data/websocket_service.dart';
import '../../models/chat.dart';
import '../../models/contact.dart';
import '../../models/message.dart';
import '../../models/story.dart';
import '../../utils/desktop_chat.dart';
import '../../utils/platform.dart';
import '../../widgets/chat_tile.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  String? _selectedFolderId;
  List<ContactModel> _searchResults = [];
  List<Map<String, dynamic>> _groupSearchResults = [];
  List<Map<String, dynamic>> _messageSearchResults = [];
  bool _searchLoading = false;
  Timer? _debounce;
  final Map<String, Uint8List> _avatarCache = {};

  List<ChatModel> _chats = [];
  bool _chatsLoading = true;
  List<Map<String, dynamic>> _foldersRaw = [];
  final Map<String, bool> _onlineStatus = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadChats();
    _loadFolders();
    _refreshStories();
    WebSocketService.on('new_message', _onNewMessage);
    WebSocketService.on('new_story', _onNewStory);
    WebSocketService.on('story_viewed', _onNewStory);
    WebSocketService.on('status', _onStatus);
    NotificationService.onMessageOpenedApp = _onNotificationTap;
    ChatReadService.instance.lastReadChatId.addListener(_onChatRead);
  }

  void _onChatRead() {
    final chatId = ChatReadService.instance.lastReadChatId.value;
    if (chatId == null || !mounted) return;
    setState(() {
      for (int i = 0; i < _chats.length; i++) {
        if (_chats[i].id == chatId && _chats[i].unreadCount != 0) {
          _chats[i] = _chats[i].copyWith(unreadCount: 0);
        }
      }
    });
  }

  void _refreshStories() {
    StoryService.instance.fetchStories().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    WebSocketService.off('new_message', _onNewMessage);
    WebSocketService.off('new_story', _onNewStory);
    WebSocketService.off('story_viewed', _onNewStory);
    WebSocketService.off('status', _onStatus);
    NotificationService.onMessageOpenedApp = null;
    ChatReadService.instance.lastReadChatId.removeListener(_onChatRead);
    super.dispose();
  }

  void _onNewMessage(dynamic data) {
    _loadChats();
  }

  void _onNewStory(dynamic data) {
    StoryService.instance.fetchStories().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _onNotificationTap(dynamic message) {
    final data = message.data;
    final chatId = data['chat_id'] as String?;
    final isGroup = data['is_group'] == true;
    final contactId = data['contact_id'] as String?;
    if (chatId != null && mounted) {
      openChat(context,
          chatId: chatId, contactId: contactId, isGroup: isGroup);
    }
  }

  void _onStatus(dynamic data) {
    if (data is! Map) return;
    final userId = data['user_id'] as String?;
    final isOnline = data['is_online'] as bool?;
    if (userId == null || isOnline == null) return;
    setState(() {
      _onlineStatus[userId] = isOnline;
      for (int i = 0; i < _chats.length; i++) {
        if (_chats[i].contactId == userId) {
          _chats[i] = _chats[i].copyWith(isOnline: isOnline);
        }
      }
    });
  }

  Future<void> _loadChats() async {
    if (!mounted) return;
    final isInitial = _chats.isEmpty;
    if (isInitial) {
      setState(() => _chatsLoading = true);
      // Load from cache first for instant display
      final cached = await CacheService.instance.loadChats();
      if (cached.isNotEmpty && mounted) {
        _chats = cached;
        setState(() {});
      }
    }
    final raw = await ApiService.getChats();
    if (!mounted) return;

    // Load muted chat IDs from local storage
    final prefs = await SharedPreferences.getInstance();
    final mutedChats = prefs.getStringList('muted_chats') ?? [];

    try {
      debugPrint('getChats returned ${raw.length} chats');
      _chats = raw.map((c) {
        debugPrint('parsing chat: $c');
        MessageModel? lastMsg;
        if (c['last_message'] != null) {
          final m = c['last_message'] as Map<String, dynamic>;
          lastMsg = MessageModel(
            id: m['id'] as String? ?? '',
            senderId: m['sender_id'] as String? ?? '',
            content: m['content'] as String? ?? '',
            type: _parseMessageType(m['type'] as String?),
            timestamp: DateTime.tryParse(m['timestamp'] as String? ?? '') ?? DateTime.now(),
            isMe: m['is_me'] as bool? ?? false,
            fileName: m['file_name'] as String?,
            fileSize: m['file_size'] as String?,
          );
        }
        final chatId = c['id'] as String? ?? '';
        return ChatModel(
          id: chatId,
          name: c['name'] as String? ?? '',
          avatarUrl: c['avatar_url'] as String?,
          contactId: c['contact_id'] as String?,
          lastMessage: lastMsg,
          unreadCount: (c['unread_count'] as num?)?.toInt() ?? 0,
          isOnline: c['is_online'] as bool? ?? false,
          isGroup: c['is_group'] as bool? ?? false,
          isProtected: c['is_protected'] as bool? ?? false,
          participantIds: (c['participant_ids'] as List?)?.cast<String>() ?? [],
          lastActivity: DateTime.tryParse(c['last_activity'] as String? ?? '') ?? DateTime.now(),
          hasPublishedStory: c['has_story'] as bool? ?? false,
          isMuted: (c['is_muted'] as bool? ?? false) || mutedChats.contains(chatId),
        );
      }).toList();
      // Save to cache
      CacheService.instance.saveChats(_chats);
    } catch (e) {
      debugPrint('error parsing chats: $e');
      if (_chats.isEmpty) _chats = [];
    }
    _chatsLoading = false;
    setState(() {});
  }

  Future<void> _loadFolders() async {
    _foldersRaw = await ApiService.getFolders();
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

  List<ChatModel> get _folderChats {
    if (_selectedFolderId == null) return _chats;
    final folder = _foldersRaw
        .where((f) => f['id'] == _selectedFolderId)
        .firstOrNull;
    if (folder == null) return _chats;
    final chatIds = (folder['chat_ids'] as List).cast<String>();
    return _chats.where((c) => chatIds.contains(c.id)).toList();
  }

  List<ChatModel> get _filteredChats {
    final source = _folderChats;
    final filtered = _searchQuery.isEmpty
        ? source
        : source.where((chat) {
            return chat.name.toLowerCase().contains(_searchQuery.toLowerCase());
          }).toList();
    // Sort by last message time (most recent first)
    filtered.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    return filtered;
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      _searchQuery = '';
      _searchResults = [];
      _groupSearchResults = [];
      _messageSearchResults = [];
      if (mounted) setState(() {});
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _searchLoading = true);
      final usersFuture = ApiService.searchUsers(q);
      final groupsFuture = ApiService.searchGroups(q);
      final messagesFuture = ApiService.searchMessages(q);
      final results = await Future.wait([usersFuture, groupsFuture, messagesFuture]);
      if (!mounted) return;
      _searchQuery = q;
      _searchLoading = false;
      _searchResults = (results[0] as List)
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
      _groupSearchResults = (results[1] as List).cast<Map<String, dynamic>>();
      _messageSearchResults = (results[2] as List).cast<Map<String, dynamic>>();
      setState(() {});
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchQuery = '';
        _searchResults = [];
        _groupSearchResults = [];
        _messageSearchResults = [];
      } else {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching ? _buildSearchField() : const Text('NajiMe'),
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _toggleSearch,
              )
            : null,
        actions: [
          if (isDesktop && !_isSearching) ...[
            IconButton(
              icon: const Icon(Icons.group_add),
              tooltip: 'New group',
              onPressed: () => context.push('/home/chats/create-group'),
            ),
          ],
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: _toggleSearch,
            ),
        ],
      ),
      floatingActionButton: isDesktop
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: 'group',
                  mini: true,
                  backgroundColor: cs.primaryContainer,
                  foregroundColor: cs.onPrimaryContainer,
                  onPressed: () => context.push('/home/chats/create-group'),
                  child: const Icon(Icons.group_add, size: 20),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'chat',
                  backgroundColor: const Color(0xFF18A7B5),
                  foregroundColor: Colors.white,
                  onPressed: _toggleSearch,
                  child: const Icon(Icons.add),
                ),
              ],
            ),
      body: _isSearching && _searchQuery.isNotEmpty
          ? _buildSearchResults(cs)
          : _chatsLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildStoriesBar(cs),
                _buildFolderBar(cs),
                Expanded(
                  child: _filteredChats.isEmpty
                      ? _buildEmptyState(cs)
                      : _buildChatList(),
                ),
              ],
            ),
    );
  }

  Widget _buildSearchResults(ColorScheme cs) {
    if (_searchLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty && _groupSearchResults.isEmpty && _messageSearchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 56,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    // Build sections: Messages first, then Groups, then Users
    final sections = <Widget>[];

    if (_messageSearchResults.isNotEmpty) {
      sections.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Messages',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: cs.primary,
            ),
          ),
        ),
      );
      for (final msg in _messageSearchResults) {
        sections.add(_buildMessageSearchTile(msg, cs));
      }
    }

    if (_groupSearchResults.isNotEmpty) {
      sections.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Groups',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: cs.primary,
            ),
          ),
        ),
      );
      for (final group in _groupSearchResults) {
        sections.add(_buildGroupSearchTile(group, cs));
      }
    }

    if (_searchResults.isNotEmpty) {
      sections.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Users',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: cs.primary,
            ),
          ),
        ),
      );
    }

    final totalItems = sections.length + _searchResults.length;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        if (index < sections.length) {
          return sections[index];
        }
        final userIndex = index - sections.length;
        final user = _searchResults[userIndex];
        final isOnline = _onlineStatus[user.id] == true;
        return ListTile(
          onTap: () async {
            final result = await ApiService.findOrCreateChat(user.id);
            if (!mounted) return;
            if (result != null) {
              _searchController.clear();
              _searchQuery = '';
              _searchResults = [];
              _groupSearchResults = [];
              _messageSearchResults = [];
              _isSearching = false;
              openChat(context,
                  chatId: result['chat_id'], contactId: user.id);
            }
          },
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: _buildUserAvatar(user, cs, size: 44, isOnline: isOnline),
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
          subtitle: Row(
            children: [
              Text(
                user.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              if (user.isBot) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'bot',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
              if (!user.isBot) ...[
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isOnline
                        ? const Color(0xFF22C55E)
                        : cs.onSurfaceVariant.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  isOnline ? 'online' : 'offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: isOnline
                        ? const Color(0xFF22C55E)
                        : cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildGroupSearchTile(Map<String, dynamic> group, ColorScheme cs) {
    final name = group['name'] as String? ?? '';
    final avatarUrl = group['avatar_url'] as String?;
    final memberCount = group['member_count'] as int? ?? 0;
    final chatId = group['id'] as String?;

    return ListTile(
      onTap: () {
        if (chatId == null) return;
        _searchController.clear();
        _searchQuery = '';
        _searchResults = [];
        _groupSearchResults = [];
        _messageSearchResults = [];
        _isSearching = false;
        openChat(context, chatId: chatId, isGroup: true);
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.primary.withValues(alpha: 0.15),
        ),
        clipBehavior: Clip.antiAlias,
        child: avatarUrl != null && avatarUrl.isNotEmpty
            ? Image.network(avatarUrl, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _buildGroupIcon(cs))
            : _buildGroupIcon(cs),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
          ),
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
      ),
      subtitle: Text(
        '$memberCount members',
        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _buildGroupIcon(ColorScheme cs) {
    return Center(
      child: Icon(Icons.group, color: cs.primary, size: 22),
    );
  }

  Widget _buildMessageSearchTile(Map<String, dynamic> result, ColorScheme cs) {
    final content = result['content'] as String? ?? '';
    final senderName = result['sender_name'] as String? ?? '';
    final chatName = result['chat_name'] as String? ?? '';
    final chatId = result['chat_id'] as String?;
    final timestamp = result['timestamp'] as String?;

    String timeStr = '';
    if (timestamp != null) {
      try {
        final dt = DateTime.parse(timestamp);
        final now = DateTime.now();
        if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
          timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        } else {
          timeStr = '${dt.day}/${dt.month}';
        }
      } catch (_) {}
    }

    return ListTile(
      onTap: () {
        if (chatId == null) return;
        _searchController.clear();
        _searchQuery = '';
        _searchResults = [];
        _groupSearchResults = [];
        _messageSearchResults = [];
        _isSearching = false;
        openChat(context, chatId: chatId);
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.primary.withValues(alpha: 0.1),
        ),
        child: Icon(Icons.message, color: cs.primary, size: 20),
      ),
      title: Text(
        content,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14, color: cs.onSurface),
      ),
      subtitle: Text(
        '$senderName in $chatName',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
      trailing: Text(
        timeStr,
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _buildSearchField() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 40,
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
          hintText: 'Search users...',
          hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant, size: 20),
        ),
      ),
    );
  }

  Widget _buildStoriesBar(ColorScheme cs) {
    final svc = StoryService.instance;
    final usersWithStories = svc.usersWithStories;
    final myStories = svc.myStories;

    return Container(
      height: 108,
      color: cs.surface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: usersWithStories.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildMyStoryButton(cs, myStories.isNotEmpty);
          }
          final userId = usersWithStories[index - 1];
          final userStories = svc.getStoriesForUser(userId);
          final s = userStories.first;
          final chat = _chats.where((c) => c.contactId == userId).firstOrNull;
          return _buildStoryAvatar(s, chat, cs);
        },
      ),
    );
  }

  Widget _buildFolderBar(ColorScheme cs) {
    final chips = _buildFolderChips(cs);

    return Container(
      height: 44,
      color: cs.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const pad = 12.0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: pad, vertical: 6),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth - 2 * pad,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: chips,
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildFolderChips(ColorScheme cs) {
    final chips = <Widget>[];

    final isAll = _selectedFolderId == null;
    chips.add(
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: const Text('All'),
          selected: isAll,
          onSelected: (_) => setState(() => _selectedFolderId = null),
          selectedColor: cs.primary,
          labelStyle: TextStyle(
            color: isAll ? Colors.white : cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          checkmarkColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          side: BorderSide(color: isAll ? cs.primary : cs.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );

    for (final folder in _foldersRaw) {
      final isSelected = _selectedFolderId == folder['id'];
      chips.add(
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(folder['name'] as String? ?? ''),
            selected: isSelected,
            onSelected: (_) => setState(() => _selectedFolderId = folder['id']),
            selectedColor: cs.primary,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
            checkmarkColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            side: BorderSide(
              color: isSelected ? cs.primary : cs.outlineVariant,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      );
    }

    return chips;
  }

  Widget _buildMyStoryButton(ColorScheme cs, bool hasStories) {
    final auth = AuthState.instance;
    final hasAvatar = auth.avatarUrl != null && auth.avatarUrl!.isNotEmpty;
    Widget? avatarImage;

    if (hasAvatar) {
      if (auth.avatarUrl!.startsWith('data:image')) {
        try {
          final base64Data = auth.avatarUrl!.split(',').last;
          final bytes = base64.decode(base64Data);
          avatarImage = ClipOval(
            child: Image.memory(bytes, width: 56, height: 56, fit: BoxFit.cover),
          );
        } catch (_) {}
      } else {
        avatarImage = ClipOval(
          child: Image.network(auth.avatarUrl!, width: 56, height: 56, fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () async {
          final result = await context.push<bool>('/story/create');
          if (result == true && mounted) setState(() {});
        },
        onLongPress: hasStories
            ? () => _openStoryViewer(AuthState.instance.username ?? '', cs)
            : null,
        child: SizedBox(
          width: 68,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: hasStories ? const Color(0xFF18A7B5) : cs.outlineVariant,
                        width: hasStories ? 2.5 : 2,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: avatarImage ??
                        Center(
                          child: Icon(
                            Icons.person,
                            color: cs.onSurfaceVariant,
                            size: 28,
                          ),
                        ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.surface, width: 2),
                      ),
                      child: Icon(
                        hasStories ? Icons.remove_red_eye_outlined : Icons.add,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                hasStories ? 'My Story' : 'Add Story',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoryAvatar(StoryModel story, ChatModel? chat, ColorScheme cs) {
    final hasAvatar = story.userAvatar != null && story.userAvatar!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () => _openStoryViewer(story.userId, cs),
        child: SizedBox(
          width: 68,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surface,
                  border: Border.all(
                    color: const Color(0xFF18A7B5),
                    width: 2.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasAvatar
                    ? ClipOval(
                        child: Image.network(story.userAvatar!, width: 56, height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _storyAvatarFallback(story, cs),
                        ),
                      )
                    : _storyAvatarFallback(story, cs),
              ),
              const SizedBox(height: 4),
              Text(
                story.userName.split(' ').first,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _storyAvatarFallback(StoryModel story, ColorScheme cs) {
    return Center(
      child: Text(
        story.userName.isNotEmpty ? story.userName[0].toUpperCase() : '?',
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _openStoryViewer(String userId, ColorScheme cs) {
    final svc = StoryService.instance;
    final userIds = svc.usersWithStories.toList();
    final myId = AuthState.instance.username ?? '';
    if (svc.myStories.isNotEmpty && !userIds.contains(myId)) {
      userIds.insert(0, myId);
    }
    if (!userIds.contains(userId)) return;
    context.push('/story/view', extra: {
      'initialUserId': userId,
      'userIds': userIds,
    }).then((_) {
      if (mounted) setState(() {});
    });
  }

  Widget _buildUserAvatar(
    ContactModel user,
    ColorScheme cs, {
    double size = 44,
    bool isOnline = false,
  }) {
    Widget? avatar;
    if (user.avatarUrl != null && user.avatarUrl!.isNotEmpty) {
      if (user.avatarUrl!.startsWith('data:image')) {
        final cacheKey = user.id;
        Uint8List? bytes = _avatarCache[cacheKey];
        if (bytes == null) {
          try {
            final base64Data = user.avatarUrl!.split(',').last;
            bytes = base64Decode(base64Data);
            _avatarCache[cacheKey] = bytes;
          } catch (e) {
            avatar = _buildAvatarFallback(user, cs, size: size);
          }
        }
        if (bytes != null) {
          avatar = ClipOval(
            child: Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  _buildAvatarFallback(user, cs, size: size),
            ),
          );
        }
      } else {
        avatar = ClipOval(
          child: Image.network(
            user.avatarUrl!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                _buildAvatarFallback(user, cs, size: size),
          ),
        );
      }
    }
    avatar ??= _buildAvatarFallback(user, cs, size: size);

    return Stack(
      children: [
        avatar,
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                shape: BoxShape.circle,
                border: Border.all(
                  color: cs.surface,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
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

  Widget _buildChatList() {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4),
      itemCount: _filteredChats.length,
      itemBuilder: (context, index) {
        final chat = _filteredChats[index];
        return ChatTile(
          chat: chat,
          onTap: () => openChat(context,
              chatId: chat.id,
              contactId: chat.contactId,
              isGroup: chat.isGroup,
              isProtected: chat.isProtected),
          onLongPress: () => _showChatOptions(chat),
        );
      },
    );
  }

  void _showChatOptions(ChatModel chat) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(
                  chat.isMuted ? Icons.notifications_active : Icons.notifications_off,
                  color: chat.isMuted ? Colors.green : null,
                ),
                title: Text(chat.isMuted ? 'Unmute' : 'Mute'),
                subtitle: Text(chat.isMuted
                    ? 'Turn on notifications'
                    : 'Turn off notifications'),
                onTap: () {
                  Navigator.pop(context);
                  _toggleChatMute(chat);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleChatMute(ChatModel chat) async {
    final prefs = await SharedPreferences.getInstance();
    final mutedChats = prefs.getStringList('muted_chats') ?? [];

    final newMutedState = !chat.isMuted;
    if (newMutedState) {
      mutedChats.add(chat.id);
      ApiService.muteChat(chat.id);
    } else {
      mutedChats.remove(chat.id);
      ApiService.unmuteChat(chat.id);
    }

    await prefs.setStringList('muted_chats', mutedChats);

    setState(() {
      final idx = _chats.indexWhere((c) => c.id == chat.id);
      if (idx != -1) {
        _chats[idx] = _chats[idx].copyWith(isMuted: newMutedState);
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newMutedState ? 'Notifications muted' : 'Notifications unmuted'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isSearching ? Icons.search_off : Icons.chat_bubble_outline,
                size: 56,
                color: cs.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isSearching ? 'No chats found' : 'No chats yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isSearching
                  ? 'Try a different search term'
                  : 'Start a conversation by tapping the button below',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
