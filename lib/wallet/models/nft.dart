/// An attribute from the NFT's off-chain metadata.
class NftAttribute {
  const NftAttribute({required this.traitType, required this.value});

  final String traitType;
  final String value;
}

/// A file entry from the NFT's `properties.files` metadata.
class NftFile {
  const NftFile({required this.uri, required this.type});

  final String uri;
  final String type;

  bool get isAudio => type.toLowerCase().startsWith('audio');
  bool get isVideo => type.toLowerCase().startsWith('video');
}

/// The media category of an NFT: `image`, `audio`, `video` or unknown.
enum NftCategory { image, audio, video, unknown }

/// A non-fungible token owned by the wallet.
class Nft {
  const Nft({
    required this.mint,
    required this.tokenAccount,
    required this.name,
    required this.symbol,
    required this.imageUrl,
    required this.description,
    required this.programId,
    this.attributes = const [],
    this.files = const [],
    this.category = NftCategory.unknown,
  });

  final String mint;
  final String tokenAccount;
  final String name;
  final String symbol;
  final String imageUrl;
  final String description;

  /// Owning token program (standard SPL or Token-2022).
  final String programId;

  final List<NftAttribute> attributes;

  /// Files from `properties.files` (may include audio/video media).
  final List<NftFile> files;

  /// Media category: image / audio / video.
  final NftCategory category;

  bool get isAudio => category == NftCategory.audio;
  bool get isVideo => category == NftCategory.video;
  bool get hasMedia => isAudio || isVideo;

  /// The media file to play (first matching the category), or null.
  NftFile? get mediaFile {
    for (final file in files) {
      if (isAudio && file.isAudio) return file;
      if (isVideo && file.isVideo) return file;
    }
    if (files.isNotEmpty && isAudio == isVideo) return files.first;
    return null;
  }
}
