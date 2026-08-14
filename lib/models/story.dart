enum StoryMediaType { image, video }

class StoryModel {
  final String id;
  final String userId;
  final String userName;
  final String? userAvatar;
  final String mediaPath;
  final StoryMediaType mediaType;
  final DateTime timestamp;
  final String? caption;
  final List<String> viewerIds;

  const StoryModel({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatar,
    required this.mediaPath,
    required this.mediaType,
    required this.timestamp,
    this.caption,
    this.viewerIds = const [],
  });

  bool get isExpired => DateTime.now().difference(timestamp).inHours >= 24;

  StoryModel copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userAvatar,
    String? mediaPath,
    StoryMediaType? mediaType,
    DateTime? timestamp,
    String? caption,
    List<String>? viewerIds,
  }) {
    return StoryModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      mediaPath: mediaPath ?? this.mediaPath,
      mediaType: mediaType ?? this.mediaType,
      timestamp: timestamp ?? this.timestamp,
      caption: caption ?? this.caption,
      viewerIds: viewerIds ?? this.viewerIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'userName': userName,
        'userAvatar': userAvatar,
        'mediaPath': mediaPath,
        'mediaType': mediaType.name,
        'timestamp': timestamp.toIso8601String(),
        'caption': caption,
        'viewerIds': viewerIds,
      };

  factory StoryModel.fromJson(Map<String, dynamic> json) => StoryModel(
        id: json['id'] as String,
        userId: json['userId'] as String,
        userName: json['userName'] as String,
        userAvatar: json['userAvatar'] as String?,
        mediaPath: json['mediaPath'] as String,
        mediaType: StoryMediaType.values.firstWhere(
          (e) => e.name == json['mediaType'],
        ),
        timestamp: DateTime.parse(json['timestamp'] as String),
        caption: json['caption'] as String?,
        viewerIds: (json['viewerIds'] as List?)?.cast<String>() ?? [],
      );
}
