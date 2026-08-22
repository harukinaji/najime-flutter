import 'package:flutter/material.dart';

import '../../data/api_service.dart';

class FoldersScreen extends StatefulWidget {
  const FoldersScreen({super.key});

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  List<Map<String, dynamic>> _folders = [];
  List<Map<String, dynamic>> _allChats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final results = await Future.wait([
      ApiService.getFolders(),
      ApiService.getChats(),
    ]);
    if (!mounted) return;
    _folders = results[0];
    _allChats = results[1];
    _loading = false;
    setState(() {});
  }

  void _showFolderEditor({Map<String, dynamic>? folder}) {
    final nameController = TextEditingController(
      text: folder?['name'] as String? ?? '',
    );
    final selectedChatIds = Set<String>.from(
      (folder?['chat_ids'] as List?)?.cast<String>() ?? [],
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final cs = Theme.of(ctx).colorScheme;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    folder == null ? 'New Folder' : 'Edit Folder',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Folder name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select chats to include:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 300,
                    child: ListView(
                      children: _allChats.map((chat) {
                        final chatId = chat['id'] as String;
                        final isSelected = selectedChatIds.contains(chatId);
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (v) {
                            setSheetState(() {
                              if (v == true) {
                                selectedChatIds.add(chatId);
                              } else {
                                selectedChatIds.remove(chatId);
                              }
                            });
                          },
                          title: Text(chat['name'] as String? ?? ''),
                          subtitle: Text(
                            (chat['is_group'] as bool?) == true
                                ? 'Channel'
                                : 'Personal',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          controlAffinity: ListTileControlAffinity.trailing,
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        if (nameController.text.trim().isEmpty) return;
                        final name = nameController.text.trim();
                        final chatIds = selectedChatIds.toList();
                        if (folder != null) {
                          await ApiService.updateFolder(
                            folder['id'] as String,
                            name,
                            chatIds,
                          );
                        } else {
                          await ApiService.createFolder(name, chatIds);
                        }
                        Navigator.of(ctx).pop();
                        _loadData();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF18A7B5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        folder == null ? 'Create Folder' : 'Save',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _deleteFolder(Map<String, dynamic> folder) {
    if (folder['is_default'] == true) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text('Delete "${folder['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await ApiService.deleteFolder(folder['id'] as String);
              Navigator.of(ctx).pop();
              _loadData();
            },
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Folders')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _folders.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_open,
                    size: 64,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No folders yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a folder to organize your chats',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _folders.length,
              itemBuilder: (context, index) {
                final folder = _folders[index];
                final chatCount = (folder['chat_ids'] as List?)?.length ?? 0;
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.folder, color: cs.primary, size: 24),
                    ),
                    title: Text(
                      folder['name'] as String? ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      '$chatCount chat${chatCount == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (folder['is_default'] != true)
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              color: cs.error,
                              size: 20,
                            ),
                            onPressed: () => _deleteFolder(folder),
                          ),
                        Icon(
                          Icons.chevron_right,
                          color: cs.onSurfaceVariant,
                          size: 22,
                        ),
                      ],
                    ),
                    onTap: () => _showFolderEditor(folder: folder),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF18A7B5),
        foregroundColor: Colors.white,
        onPressed: () => _showFolderEditor(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
