import 'package:flutter/material.dart';

import '../data/api_service.dart';
import '../models/sticker.dart';
import 'sticker_widget.dart';

class StickerStrip extends StatefulWidget {
  final Function(String stickerUrl) onStickerSelected;
  final VoidCallback? onExpand;

  const StickerStrip({
    super.key,
    required this.onStickerSelected,
    this.onExpand,
  });

  @override
  State<StickerStrip> createState() => _StickerStripState();
}

class _StickerStripState extends State<StickerStrip> {
  List<StickerPack> _packs = [];
  List<Sticker> _stickers = [];
  bool _loading = true;
  int _selectedPackIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  Future<void> _loadPacks() async {
    final data = await ApiService.getInstalledStickerPacks();
    if (!mounted) return;
    setState(() {
      _packs = data.map((p) => StickerPack.fromJson(p)).toList();
      _loading = false;
    });
    _loadStickersForSelectedPack();
  }

  Future<void> _loadStickersForSelectedPack() async {
    if (_selectedPackIndex < 0 || _selectedPackIndex >= _packs.length) {
      setState(() => _stickers = []);
      return;
    }
    final pack = _packs[_selectedPackIndex];
    setState(() => _stickers = []);
    final detail = await ApiService.getStickerPack(pack.id);
    if (!mounted) return;
    if (detail != null) {
      final stickers =
          (detail['stickers'] as List?)
              ?.map((s) => Sticker.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [];
      setState(() => _stickers = stickers);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: _loading ? 48 : 56,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _packs.isEmpty
          ? Center(
              child: TextButton.icon(
                onPressed: widget.onExpand,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Install sticker packs'),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pack tabs row
                SizedBox(
                  height: 28,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (int i = 0; i < _packs.length; i++)
                        GestureDetector(
                          onTap: () {
                            setState(() => _selectedPackIndex = i);
                            _loadStickersForSelectedPack();
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: _selectedPackIndex == i
                                  ? cs.primary.withValues(alpha: 0.15)
                                  : cs.surfaceContainerHighest.withValues(
                                      alpha: 0.5,
                                    ),
                              borderRadius: BorderRadius.circular(6),
                              border: _selectedPackIndex == i
                                  ? Border.all(color: cs.primary, width: 1)
                                  : null,
                            ),
                            child: _packs[i].thumbnailUrl != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(5),
                                    child: StickerThumb(
                                      url: _packs[i].thumbnailUrl!,
                                      size: 28,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Center(
                                    child: Text(
                                      _packs[i].name.isNotEmpty
                                          ? _packs[i].name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      // Expand button
                      GestureDetector(
                        onTap: widget.onExpand,
                        child: Container(
                          width: 28,
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.open_in_full,
                            size: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Sticker thumbnails strip
                Expanded(
                  child: _stickers.isEmpty
                      ? Center(
                          child: Text(
                            'No stickers',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: _stickers.length,
                          itemBuilder: (context, index) {
                            final sticker = _stickers[index];
                            return GestureDetector(
                              onTap: () =>
                                  widget.onStickerSelected(sticker.imageUrl),
                              child: Container(
                                width: 40,
                                height: 40,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: StickerThumb(
                                    url: sticker.imageUrl,
                                    size: 40,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
