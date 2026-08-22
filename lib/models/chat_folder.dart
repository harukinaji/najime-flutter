class ChatFolder {
  final String id;
  final String name;
  final List<String> chatIds;
  final bool isDefault;

  const ChatFolder({
    required this.id,
    required this.name,
    this.chatIds = const [],
    this.isDefault = false,
  });

  ChatFolder copyWith({String? name, List<String>? chatIds}) {
    return ChatFolder(
      id: id,
      name: name ?? this.name,
      chatIds: chatIds ?? this.chatIds,
      isDefault: isDefault,
    );
  }
}
