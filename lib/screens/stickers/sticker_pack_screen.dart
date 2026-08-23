import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api_service.dart';
import '../../data/sticker_cache.dart';
import '../../models/sticker.dart';
import '../../widgets/sticker_widget.dart';

class StickerPackScreen extends StatefulWidget {
  const StickerPackScreen({super.key});

  @override
  State<StickerPackScreen> createState() => _StickerPackScreenState();
}

class _StickerPackScreenState extends State<StickerPackScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<StickerPack> _myPacks = [];
  List<StickerPack> _installedPacks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPacks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPacks() async {
    setState(() => _loading = true);
    final myData = await ApiService.getMyStickerPacks();
    final installedData = await ApiService.getInstalledStickerPacks();
    if (!mounted) return;
    setState(() {
      _myPacks = myData.map((p) => StickerPack.fromJson(p)).toList();
      _installedPacks = installedData
          .map((p) => StickerPack.fromJson(p))
          .toList();
      _loading = false;
    });
  }

  void _showImportTelegramDialog() {
    final urlController = TextEditingController();
    bool importing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Import from Telegram'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste a Telegram sticker pack link:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'e.g. https://t.me/addstickers/PackName',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  hintText: 'Pack name or URL',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
                autofocus: true,
              ),
              if (importing) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Importing stickers...',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: importing ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: importing
                  ? null
                  : () async {
                      final url = urlController.text.trim();
                      if (url.isEmpty) return;
                      setDialogState(() => importing = true);

                      final result = await ApiService.importTelegramPack(url);
                      if (!mounted) return;
                      Navigator.pop(ctx);

                      if (result != null) {
                        final imported = result['imported'] as int? ?? 0;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              imported > 0
                                  ? 'Imported $imported stickers!'
                                  : 'Pack imported but no stickers were found',
                            ),
                          ),
                        );
                        _loadPacks();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to import pack'),
                          ),
                        );
                      }
                    },
              child: const Text('Import'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreatePackDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Sticker Pack'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                hintText: 'Pack name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                hintText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final result = await ApiService.createStickerPack(
                name: name,
                description: descController.text.trim().isNotEmpty
                    ? descController.text.trim()
                    : null,
              );
              if (result != null && mounted) {
                _loadPacks();
                _openPackDetail(StickerPack.fromJson(result));
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _openPackDetail(StickerPack pack) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _StickerPackDetailScreen(pack: pack, onUpdated: _loadPacks),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sticker Packs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _showImportTelegramDialog,
            tooltip: 'Import from Telegram',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreatePackDialog,
            tooltip: 'Create pack',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'My Packs'),
            Tab(text: 'Installed'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPackList(_myPacks, isMyPacks: true),
                _buildPackList(_installedPacks, isMyPacks: false),
              ],
            ),
    );
  }

  Widget _buildPackList(List<StickerPack> packs, {required bool isMyPacks}) {
    final cs = Theme.of(context).colorScheme;

    if (packs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isMyPacks ? Icons.create_new_folder : Icons.download_done,
              size: 48,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              isMyPacks
                  ? 'You have no sticker packs yet'
                  : 'No installed sticker packs',
              style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
            ),
            if (isMyPacks) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _showCreatePackDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create Pack'),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPacks,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: packs.length,
        itemBuilder: (context, index) {
          final pack = packs[index];
          return _buildPackTile(pack, isMyPacks: isMyPacks);
        },
      ),
    );
  }

  Widget _buildPackTile(StickerPack pack, {required bool isMyPacks}) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: pack.thumbnailUrl != null
            ? StickerThumb(url: pack.thumbnailUrl!, size: 48, fit: BoxFit.cover)
            : Center(
                child: Text(
                  pack.name[0].toUpperCase(),
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ),
      ),
      title: Text(
        pack.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${pack.stickerCount} stickers',
        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
      ),
      trailing: isMyPacks
          ? IconButton(
              icon: Icon(Icons.delete_outline, color: cs.error),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete pack?'),
                    content: Text(
                      'Are you sure you want to delete "${pack.name}"?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.error,
                        ),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ApiService.deleteStickerPack(pack.id);
                  _loadPacks();
                }
              },
            )
          : IconButton(
              icon: Icon(
                pack.isInstalled
                    ? Icons.check_circle
                    : Icons.add_circle_outline,
                color: pack.isInstalled ? cs.primary : cs.onSurfaceVariant,
              ),
              onPressed: () async {
                if (pack.isInstalled) {
                  await ApiService.uninstallStickerPack(pack.id);
                } else {
                  await ApiService.installStickerPack(pack.id);
                }
                _loadPacks();
              },
            ),
      onTap: () => _openPackDetail(pack),
    );
  }
}

// ── Pack Detail Screen ────────────────────────────────────────

class _StickerPackDetailScreen extends StatefulWidget {
  final StickerPack pack;
  final VoidCallback onUpdated;

  const _StickerPackDetailScreen({required this.pack, required this.onUpdated});

  @override
  State<_StickerPackDetailScreen> createState() =>
      _StickerPackDetailScreenState();
}

class _StickerPackDetailScreenState extends State<_StickerPackDetailScreen> {
  late StickerPack _pack;
  final ImagePicker _picker = ImagePicker();
  bool _loadingStickers = true;
  bool _addingSticker = false;

  @override
  void initState() {
    super.initState();
    _pack = widget.pack;
    _loadPackDetail();
  }

  Future<void> _loadPackDetail() async {
    setState(() => _loadingStickers = true);
    final data = await ApiService.getStickerPack(_pack.id);
    if (data != null && mounted) {
      setState(() {
        _pack = StickerPack.fromJson(data);
        _loadingStickers = false;
      });
      // Preload Lottie stickers in background
      final urls = _pack.stickers.map((s) => s.imageUrl).toList();
      StickerCache.instance.preload(urls);
    } else if (mounted) {
      setState(() => _loadingStickers = false);
    }
  }

  Future<void> _addSticker() async {
    final picker = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
          ],
        ),
      ),
    );

    if (picker == null || !mounted) return;

    final XFile? image;
    if (picker == 'camera') {
      image = await _picker.pickImage(source: ImageSource.camera);
    } else {
      image = await _picker.pickImage(source: ImageSource.gallery);
    }

    if (image == null || !mounted) return;

    // Show emoji input dialog
    final emoji = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Add Emoji (optional)'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'e.g. 😀',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    setState(() => _addingSticker = true);

    // Upload file
    final file = File(image.path);
    final uploadResult = await ApiService.uploadFile(file, scope: 'public');
    if (uploadResult == null || !mounted) {
      setState(() => _addingSticker = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to upload image')));
      }
      return;
    }

    final fileUrl = uploadResult['file_url'] as String?;
    if (fileUrl == null) {
      setState(() => _addingSticker = false);
      return;
    }

    // Add sticker to pack
    final sticker = await ApiService.addSticker(
      packId: _pack.id,
      imageUrl: fileUrl,
      emoji: emoji?.isNotEmpty == true ? emoji : null,
    );

    setState(() => _addingSticker = false);

    if (sticker != null && mounted) {
      // Reload from server to get accurate state
      await _loadPackDetail();
      widget.onUpdated();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sticker added!'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to add sticker')));
    }
  }

  Future<void> _deleteSticker(String stickerId) async {
    final success = await ApiService.deleteSticker(stickerId);
    if (success && mounted) {
      await _loadPackDetail();
      widget.onUpdated();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_pack.name),
        actions: [
          if (_addingSticker)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.add_photo_alternate),
              onPressed: _addSticker,
              tooltip: 'Add sticker',
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_pack.description != null && _pack.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _pack.description!,
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'by ${_pack.creatorName}',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                Text(
                  '${_pack.stickers.length} stickers',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _loadingStickers
                ? const Center(child: CircularProgressIndicator())
                : _pack.stickers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.emoji_emotions_outlined,
                          size: 48,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No stickers yet',
                          style: TextStyle(
                            fontSize: 15,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _addSticker,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add First Sticker'),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadPackDetail,
                    child: GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                          ),
                      itemCount: _pack.stickers.length,
                      itemBuilder: (context, index) {
                        final sticker = _pack.stickers[index];
                        return GestureDetector(
                          onLongPress: () {
                            showModalBottomSheet(
                              context: context,
                              builder: (ctx) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (sticker.emoji != null &&
                                        sticker.emoji!.isNotEmpty)
                                      ListTile(
                                        leading: Text(
                                          sticker.emoji!,
                                          style: const TextStyle(fontSize: 24),
                                        ),
                                        title: Text('Emoji: ${sticker.emoji}'),
                                      ),
                                    ListTile(
                                      leading: Icon(
                                        Icons.delete,
                                        color: cs.error,
                                      ),
                                      title: Text(
                                        'Delete Sticker',
                                        style: TextStyle(color: cs.error),
                                      ),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        _deleteSticker(sticker.id);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withValues(
                                alpha: 0.3,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: StickerThumb(
                                url: sticker.imageUrl,
                                size: 80,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
