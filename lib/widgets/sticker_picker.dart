import 'dart:convert';

import 'package:flutter/material.dart';

import '../config.dart';
import '../data/api_service.dart';
import '../data/sticker_cache.dart';
import '../models/sticker.dart';
import '../screens/stickers/sticker_pack_screen.dart';
import 'sticker_widget.dart';

class StickerPicker extends StatefulWidget {
  final Function(String stickerUrl) onStickerSelected;
  final VoidCallback? onManagePacks;

  const StickerPicker({
    super.key,
    required this.onStickerSelected,
    this.onManagePacks,
  });

  @override
  State<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker> {
  List<StickerPack> _packs = [];
  bool _loading = true;
  int _selectedPackIndex = 0;
  List<Sticker> _stickers = [];
  bool _loadingStickers = false;

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  Future<void> _loadPacks() async {
    setState(() => _loading = true);
    final data = await ApiService.getInstalledStickerPacks();
    if (!mounted) return;
    setState(() {
      _packs = data.map((p) => StickerPack.fromJson(p)).toList();
      _loading = false;
      if (_selectedPackIndex >= _packs.length) {
        _selectedPackIndex = _packs.isNotEmpty ? 0 : -1;
      }
    });
    _loadStickersForSelectedPack();
  }

  Future<void> _loadStickersForSelectedPack() async {
    if (_selectedPackIndex < 0 || _selectedPackIndex >= _packs.length) {
      setState(() => _stickers = []);
      return;
    }
    final pack = _packs[_selectedPackIndex];
    setState(() => _loadingStickers = true);
    final detail = await ApiService.getStickerPack(pack.id);
    if (!mounted) return;
    if (detail != null) {
      final stickers = (detail['stickers'] as List?)
              ?.map((s) => Sticker.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [];
      setState(() {
        _stickers = stickers;
        _loadingStickers = false;
      });
      // Preload Lottie stickers in background
      final urls = stickers.map((s) => s.imageUrl).toList();
      StickerCache.instance.preload(urls);
    } else {
      setState(() {
        _stickers = [];
        _loadingStickers = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildPackTabs(cs),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _packs.isEmpty
                    ? _buildEmptyState(cs)
                    : _selectedPackIndex >= 0 &&
                            _selectedPackIndex < _packs.length
                        ? _loadingStickers
                            ? const Center(child: CircularProgressIndicator())
                            : _buildStickerGrid(_stickers, cs)
                        : _buildEmptyState(cs),
          ),
        ],
      ),
    );
  }

  Widget _buildPackTabs(ColorScheme cs) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: [
          // Manage packs button
          GestureDetector(
            onTap: () {
              widget.onManagePacks?.call();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StickerPackScreen(),
                ),
              ).then((_) => _loadPacks());
            },
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.add, color: cs.primary, size: 20),
            ),
          ),
          // Pack thumbnails
          for (int i = 0; i < _packs.length; i++)
            GestureDetector(
              onTap: () {
                setState(() => _selectedPackIndex = i);
                _loadStickersForSelectedPack();
              },
              child: Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: _selectedPackIndex == i
                      ? cs.primary.withValues(alpha: 0.15)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: _selectedPackIndex == i
                      ? Border.all(color: cs.primary, width: 1.5)
                      : null,
                ),
                child: _packs[i].thumbnailUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: _buildImage(_packs[i].thumbnailUrl!),
                      )
                    : Center(
                        child: Text(
                          _packs[i].name.isNotEmpty
                              ? _packs[i].name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.emoji_emotions_outlined,
            size: 40,
            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            'No sticker packs installed',
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StickerPackScreen(),
                ),
              ).then((_) => _loadPacks());
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Browse Sticker Packs'),
          ),
        ],
      ),
    );
  }

  Widget _buildStickerGrid(List<Sticker> stickers, ColorScheme cs) {
    if (stickers.isEmpty) {
      return Center(
        child: Text(
          'No stickers in this pack',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, index) {
        final sticker = stickers[index];
        return GestureDetector(
          onTap: () => widget.onStickerSelected(sticker.imageUrl),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: StickerThumb(
                url: sticker.imageUrl,
                size: 80,
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImage(String url) {
    final fullUrl = url.startsWith('/uploads')
        ? '${AppConfig.apiBaseUrl}$url'
        : url;
    if (fullUrl.startsWith('data:image')) {
      try {
        final base64Data = fullUrl.split(',').last;
        final bytes = base64Decode(base64Data);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 24),
        );
      } catch (_) {
        return const Icon(Icons.broken_image, size: 24);
      }
    }

    return Image.network(
      fullUrl,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 24),
    );
  }
}
