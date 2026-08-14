class ContactModel {
  final String id;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final bool isOnline;
  final bool isRegistered;
  final String? phoneNumber;
  final bool isBot;
  final String? description;

  const ContactModel({
    required this.id,
    required this.displayName,
    required this.username,
    this.avatarUrl,
    this.isOnline = false,
    this.isRegistered = true,
    this.phoneNumber,
    this.isBot = false,
    this.description,
  });
}
