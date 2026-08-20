import 'dart:convert';

enum MessageType {
  text,
  image,
  file,
  premiumMessage,
  voice,
  sticker,
  invoice,
  check,
}

enum DeliveryStatus { sending, sent, delivered, read }

class PremiumUnlockInfo {
  final String assetSymbol;
  final double amount;
  final bool isUnlocked;

  const PremiumUnlockInfo({
    required this.assetSymbol,
    required this.amount,
    this.isUnlocked = false,
  });

  PremiumUnlockInfo copyWith({bool? isUnlocked}) {
    return PremiumUnlockInfo(
      assetSymbol: assetSymbol,
      amount: amount,
      isUnlocked: isUnlocked ?? this.isUnlocked,
    );
  }
}

class ReactionUser {
  final String userId;
  final String displayName;
  final String avatarUrl;

  const ReactionUser({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
  });
}

class Reaction {
  final String emoji;
  final List<ReactionUser> users;

  const Reaction({required this.emoji, required this.users});

  int get count => users.length;

  bool hasUser(String? userId) =>
      userId != null && users.any((u) => u.userId == userId);
}

class ForwardedFromInfo {
  final String originalSenderId;
  final String originalSenderName;
  final String? originalChatName;

  const ForwardedFromInfo({
    required this.originalSenderId,
    required this.originalSenderName,
    this.originalChatName,
  });
}

class InlineKeyboardButton {
  final String text;
  final String? callbackData;
  final String? url;
  final String? sendMessage;

  const InlineKeyboardButton({required this.text, this.callbackData, this.url, this.sendMessage});

  factory InlineKeyboardButton.fromJson(Map<String, dynamic> json) {
    return InlineKeyboardButton(
      text: json['text'] as String? ?? '',
      callbackData: json['callback_data'] as String?,
      url: json['url'] as String?,
      sendMessage: json['send_message'] as String?,
    );
  }
}

class InlineKeyboard {
  final List<List<InlineKeyboardButton>> rows;

  const InlineKeyboard({required this.rows});

  factory InlineKeyboard.fromJson(dynamic json) {
    if (json is! List) return const InlineKeyboard(rows: []);
    final rows = <List<InlineKeyboardButton>>[];
    for (final row in json) {
      if (row is List) {
        rows.add(row
            .map((b) => InlineKeyboardButton.fromJson(b as Map<String, dynamic>))
            .toList());
      }
    }
    return InlineKeyboard(rows: rows);
  }
}

class MessageModel {
  final String id;
  final String senderId;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final bool isMe;
  final String? fileName;
  final String? fileSize;
  final PremiumUnlockInfo? premiumInfo;
  final int? voiceDurationMs;
  final List<double>? voiceWaveform;
  final List<Reaction> reactions;
  final bool isEdited;
  final String? replyToId;
  final String? replyToContent;
  final String? replyToSenderName;
  final DeliveryStatus deliveryStatus;
  final ForwardedFromInfo? forwardedFrom;
  final bool isPinned;
  final InlineKeyboard? keyboard;

  const MessageModel({
    required this.id,
    required this.senderId,
    required this.content,
    required this.type,
    required this.timestamp,
    required this.isMe,
    this.fileName,
    this.fileSize,
    this.premiumInfo,
    this.voiceDurationMs,
    this.voiceWaveform,
    this.reactions = const [],
    this.isEdited = false,
    this.replyToId,
    this.replyToContent,
    this.replyToSenderName,
    this.deliveryStatus = DeliveryStatus.sent,
    this.forwardedFrom,
    this.isPinned = false,
    this.keyboard,
  });

  MessageModel copyWith({
    String? content,
    PremiumUnlockInfo? premiumInfo,
    List<Reaction>? reactions,
    bool? isEdited,
    DeliveryStatus? deliveryStatus,
    ForwardedFromInfo? forwardedFrom,
    bool? isPinned,
    InlineKeyboard? keyboard,
  }) {
    return MessageModel(
      id: id,
      senderId: senderId,
      content: content ?? this.content,
      type: type,
      timestamp: timestamp,
      isMe: isMe,
      fileName: fileName,
      fileSize: fileSize,
      premiumInfo: premiumInfo ?? this.premiumInfo,
      voiceDurationMs: voiceDurationMs,
      voiceWaveform: voiceWaveform,
      reactions: reactions ?? this.reactions,
      isEdited: isEdited ?? this.isEdited,
      replyToId: replyToId,
      replyToContent: replyToContent,
      replyToSenderName: replyToSenderName,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      forwardedFrom: forwardedFrom ?? this.forwardedFrom,
      isPinned: isPinned ?? this.isPinned,
      keyboard: keyboard ?? this.keyboard,
    );
  }
}

/// Payload of an `MessageType.invoice` message, stored as JSON in
/// `MessageModel.content`. Represents a payment request the recipient can pay
/// by tapping the rendered card.
class InvoiceData {
  const InvoiceData({
    required this.amount,
    required this.currency,
    required this.recipient,
    this.memo,
    this.status = 'pending',
    this.txSignature,
  });

  /// Human-readable amount (e.g. `0.005`).
  final double amount;

  /// Symbol of the requested currency (e.g. `SOL`, `USDC`).
  final String currency;

  /// Base58 destination wallet address.
  final String recipient;

  /// Optional memo shown on the invoice card / on-chain.
  final String? memo;

  /// `pending` | `paid` | `expired`.
  final String status;

  /// On-chain transaction signature once paid.
  final String? txSignature;

  int? get lamports =>
      currency.toUpperCase() == 'SOL' ? (amount * 1e9).round() : null;

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'currency': currency,
        'recipient': recipient,
        if (memo != null) 'memo': memo,
        'status': status,
        if (txSignature != null) 'tx_signature': txSignature,
      };

  static InvoiceData? tryParse(String content) {
    try {
      final json = jsonDecode(content);
      if (json is! Map<String, dynamic>) return null;
      final amount = (json['amount'] as num?)?.toDouble();
      final currency = json['currency'] as String?;
      final recipient = json['recipient'] as String?;
      if (amount == null || currency == null || recipient == null) return null;
      return InvoiceData(
        amount: amount,
        currency: currency,
        recipient: recipient,
        memo: json['memo'] as String?,
        status: (json['status'] as String?) ?? 'pending',
        txSignature: json['tx_signature'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode(toJson());

  InvoiceData copyWith({
    double? amount,
    String? currency,
    String? recipient,
    String? memo,
    String? status,
    String? txSignature,
  }) {
    return InvoiceData(
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      recipient: recipient ?? this.recipient,
      memo: memo ?? this.memo,
      status: status ?? this.status,
      txSignature: txSignature ?? this.txSignature,
    );
  }
}

class CheckData {
  const CheckData({
    required this.amount,
    required this.currency,
    required this.creatorId,
    this.status = 'active',
    this.redeemerId,
    this.checkId,
    this.txSignature,
    this.creatorAddress,
  });

  final double amount;
  final String currency;
  final String creatorId;
  final String status;
  final String? redeemerId;
  final String? checkId;
  final String? txSignature;
  final String? creatorAddress;

  int? get lamports =>
      currency.toUpperCase() == 'SOL' ? (amount * 1e9).round() : null;

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'currency': currency,
        'creator_id': creatorId,
        'status': status,
        if (redeemerId != null) 'redeemer_id': redeemerId,
        if (checkId != null) 'check_id': checkId,
        if (txSignature != null) 'tx_signature': txSignature,
        if (creatorAddress != null) 'creator_address': creatorAddress,
      };

  static CheckData? tryParse(String content) {
    try {
      final json = jsonDecode(content);
      if (json is! Map<String, dynamic>) return null;
      final amount = (json['amount'] as num?)?.toDouble();
      final currency = json['currency'] as String?;
      final creatorId = json['creator_id'] as String?;
      if (amount == null || currency == null || creatorId == null) return null;
      return CheckData(
        amount: amount,
        currency: currency,
        creatorId: creatorId,
        status: (json['status'] as String?) ?? 'active',
        redeemerId: json['redeemer_id'] as String?,
        checkId: json['check_id'] as String?,
        txSignature: json['tx_signature'] as String?,
        creatorAddress: json['creator_address'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode(toJson());

  CheckData copyWith({
    double? amount,
    String? currency,
    String? creatorId,
    String? status,
    String? redeemerId,
    String? checkId,
    String? txSignature,
    String? creatorAddress,
  }) {
    return CheckData(
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      creatorId: creatorId ?? this.creatorId,
      status: status ?? this.status,
      redeemerId: redeemerId ?? this.redeemerId,
      checkId: checkId ?? this.checkId,
      txSignature: txSignature ?? this.txSignature,
      creatorAddress: creatorAddress ?? this.creatorAddress,
    );
  }
}
