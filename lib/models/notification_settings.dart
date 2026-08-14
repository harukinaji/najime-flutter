class NotificationSettingsModel {
  final bool messagesEnabled;
  final bool callsEnabled;
  final bool groupMessagesEnabled;
  final bool soundEnabled;
  final bool vibrationEnabled;

  const NotificationSettingsModel({
    this.messagesEnabled = true,
    this.callsEnabled = true,
    this.groupMessagesEnabled = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
  });

  NotificationSettingsModel copyWith({
    bool? messagesEnabled,
    bool? callsEnabled,
    bool? groupMessagesEnabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
  }) {
    return NotificationSettingsModel(
      messagesEnabled: messagesEnabled ?? this.messagesEnabled,
      callsEnabled: callsEnabled ?? this.callsEnabled,
      groupMessagesEnabled: groupMessagesEnabled ?? this.groupMessagesEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    );
  }
}
