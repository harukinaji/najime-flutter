enum CallType { voice, video }

enum CallStatus { incoming, outgoing, missed, answered }

class CallModel {
  final String id;
  final String contactId;
  final String contactName;
  final String? contactAvatar;
  final CallType type;
  final CallStatus status;
  final DateTime timestamp;
  final Duration? duration;

  const CallModel({
    required this.id,
    required this.contactId,
    required this.contactName,
    this.contactAvatar,
    required this.type,
    required this.status,
    required this.timestamp,
    this.duration,
  });
}
