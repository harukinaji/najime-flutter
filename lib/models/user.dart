class UserModel {
  final String id;
  final String displayName;
  final String username;
  final String bio;
  final String? avatarUrl;
  final String? phoneNumber;
  final String? walletAddress;
  final bool isPremium;
  final bool isOnline;

  const UserModel({
    required this.id,
    required this.displayName,
    required this.username,
    required this.bio,
    this.avatarUrl,
    this.phoneNumber,
    this.walletAddress,
    this.isPremium = false,
    this.isOnline = false,
  });

  UserModel copyWith({
    String? displayName,
    String? username,
    String? bio,
    String? avatarUrl,
    String? phoneNumber,
    String? walletAddress,
    bool? isPremium,
    bool? isOnline,
  }) {
    return UserModel(
      id: id,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      walletAddress: walletAddress ?? this.walletAddress,
      isPremium: isPremium ?? this.isPremium,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}
