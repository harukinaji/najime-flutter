class Sticker {
  final String id;
  final String packId;
  final String imageUrl;
  final String? emoji;
  final int sortOrder;

  const Sticker({
    required this.id,
    required this.packId,
    required this.imageUrl,
    this.emoji,
    this.sortOrder = 0,
  });

  factory Sticker.fromJson(Map<String, dynamic> json) {
    return Sticker(
      id: json['id'] as String,
      packId: json['pack_id'] as String,
      imageUrl: json['image_url'] as String,
      emoji: json['emoji'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'pack_id': packId,
    'image_url': imageUrl,
    if (emoji != null) 'emoji': emoji,
    'sort_order': sortOrder,
  };
}

class StickerPack {
  final String id;
  final String name;
  final String? description;
  final String? thumbnailUrl;
  final String creatorId;
  final String creatorName;
  final bool isInstalled;
  final int stickerCount;
  final List<Sticker> stickers;
  final DateTime createdAt;

  const StickerPack({
    required this.id,
    required this.name,
    this.description,
    this.thumbnailUrl,
    required this.creatorId,
    required this.creatorName,
    this.isInstalled = false,
    this.stickerCount = 0,
    this.stickers = const [],
    required this.createdAt,
  });

  factory StickerPack.fromJson(Map<String, dynamic> json) {
    return StickerPack(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      creatorId: json['creator_id'] as String,
      creatorName: json['creator_name'] as String? ?? '',
      isInstalled: json['is_installed'] as bool? ?? false,
      stickerCount: json['sticker_count'] as int? ?? 0,
      stickers:
          (json['stickers'] as List?)
              ?.map((s) => Sticker.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
    'creator_id': creatorId,
    'creator_name': creatorName,
    'is_installed': isInstalled,
    'sticker_count': stickerCount,
    'stickers': stickers.map((s) => s.toJson()).toList(),
    'created_at': createdAt.toIso8601String(),
  };

  StickerPack copyWith({
    String? name,
    String? description,
    String? thumbnailUrl,
    bool? isInstalled,
    List<Sticker>? stickers,
  }) {
    return StickerPack(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      creatorId: creatorId,
      creatorName: creatorName,
      isInstalled: isInstalled ?? this.isInstalled,
      stickerCount: stickers?.length ?? stickerCount,
      stickers: stickers ?? this.stickers,
      createdAt: createdAt,
    );
  }
}
