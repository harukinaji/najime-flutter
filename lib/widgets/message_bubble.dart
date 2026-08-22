import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/api_service.dart';
import '../models/message.dart';
import '../wallet/services/wallet_access_proxy.dart';
import '../wallet/services/check_escrow_service.dart';
import '../wallet/state/app_state.dart';
import 'sticker_widget.dart';

const _sentColor = Color(0xFF18A7B5);

class MessageBubble extends StatefulWidget {
  final MessageModel message;
  final String? currentUserId;
  final void Function(String emoji)? onReaction;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onCopy;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onPin;
  final VoidCallback? onUnpin;
  final String? searchQuery;
  final bool isCurrentSearchMatch;
  final void Function(String callbackData)? onKeyboardButton;
  final void Function(String text)? onKeyboardSendMessage;
  final void Function(String messageId, String newContent)? onInvoicePaid;

  const MessageBubble({
    super.key,
    required this.message,
    this.currentUserId,
    this.onReaction,
    this.onEdit,
    this.onDelete,
    this.onCopy,
    this.onReply,
    this.onForward,
    this.onPin,
    this.onUnpin,
    this.searchQuery,
    this.isCurrentSearchMatch = false,
    this.onKeyboardButton,
    this.onKeyboardSendMessage,
    this.onInvoicePaid,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  AudioPlayer? _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isLoading = false;
  List<double> _waveform = [];
  bool _invoicePaying = false;
  bool _invoicePaid = false;

  String? get _myWalletAddress {
    final appState = AppState.instance;
    // Built-in wallet — can sign on-chain transactions
    if (appState.wallet != null) return appState.wallet!.address;
    // WalletConnect (Phantom/Solflare) — limited on-chain support
    final wcSession = appState.walletConnectSession;
    if (wcSession != null) return wcSession.primaryAccount;
    return null;
  }

  bool get _hasBuiltInWallet => AppState.instance.wallet != null;

  @override
  void initState() {
    super.initState();
    _initWaveform();
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.voiceWaveform != widget.message.voiceWaveform) {
      _initWaveform();
    }
  }

  void _initWaveform() {
    final stored = widget.message.voiceWaveform;
    if (stored != null && stored.isNotEmpty) {
      _waveform = stored;
    } else {
      _waveform = _generateWaveform(40, widget.message.id);
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  List<double> _generateWaveform(int count, String seed) {
    final hash = seed.hashCode;
    final rng = Random(hash);
    final bars = <double>[];
    for (var i = 0; i < count; i++) {
      bars.add(0.15 + rng.nextDouble() * 0.85);
    }
    return bars;
  }

  Future<void> _togglePlayback() async {
    if (widget.message.type != MessageType.voice) return;

    final url = widget.message.content;
    if (url.isEmpty) return;

    final fullUrl = url.startsWith('/uploads')
        ? '${AppConfig.apiBaseUrl}$url'
        : url;

    if (_player == null) {
      setState(() => _isLoading = true);
      _player = AudioPlayer();
      try {
        await _player!.setUrl(fullUrl);
        _duration = _player!.duration ?? Duration.zero;

        _player!.positionStream.listen((pos) {
          if (mounted) setState(() => _position = pos);
        });

        _player!.playerStateStream.listen((state) {
          if (mounted) {
            setState(() {
              _isPlaying = state.playing;
            });
            if (state.processingState == ProcessingState.completed) {
              setState(() {
                _isPlaying = false;
                _position = Duration.zero;
              });
              _player!.seek(Duration.zero);
            }
          }
        });

        setState(() => _isLoading = false);
      } catch (e) {
        setState(() => _isLoading = false);
        return;
      }
    }

    if (_isPlaying) {
      await _player!.pause();
    } else {
      await _player!.play();
    }
  }

  void _handleReaction(String emoji) {
    widget.onReaction?.call(emoji);
  }

  void _showContextMenu(BuildContext context) {
    final isMe = widget.message.isMe;
    final isText = widget.message.type == MessageType.text;
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Quick reactions row
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['👍', '❤️', '😂', '😮', '😢', '🔥', '👏', '🎉']
                      .map((emoji) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            _handleReaction(emoji);
                          },
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                        );
                      })
                      .toList(),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.reply, color: cs.onSurface),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onReply?.call();
                },
              ),
              if (isText && isMe)
                ListTile(
                  leading: Icon(Icons.edit, color: cs.onSurface),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onEdit?.call();
                  },
                ),
              if (isMe)
                ListTile(
                  leading: Icon(Icons.delete, color: cs.error),
                  title: Text('Delete', style: TextStyle(color: cs.error)),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onDelete?.call();
                  },
                ),
              if (isText)
                ListTile(
                  leading: Icon(Icons.copy, color: cs.onSurface),
                  title: const Text('Copy'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onCopy?.call();
                  },
                ),
              ListTile(
                leading: Icon(Icons.forward, color: cs.onSurface),
                title: const Text('Forward'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onForward?.call();
                },
              ),
              if (widget.message.isPinned)
                ListTile(
                  leading: Icon(Icons.push_pin, color: cs.onSurface),
                  title: const Text('Unpin'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onUnpin?.call();
                  },
                )
              else
                ListTile(
                  leading: Icon(Icons.push_pin_outlined, color: cs.onSurface),
                  title: const Text('Pin'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onPin?.call();
                  },
                ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMe = widget.message.isMe;
    final hasReactions = widget.message.reactions.isNotEmpty;

    // Stickers: no bubble, just the image + time
    if (widget.message.type == MessageType.sticker) {
      return GestureDetector(
        onLongPressStart: (_) {
          HapticFeedback.mediumImpact();
          _showContextMenu(context);
        },
        child: Padding(
          padding: EdgeInsets.only(
            left: isMe ? 48 : 8,
            right: isMe ? 8 : 48,
            top: 2,
            bottom: 2,
          ),
          child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.message.replyToId != null)
                _buildReplyPreview(cs, isMe),
              if (widget.message.forwardedFrom != null)
                _buildForwardedPreview(cs, isMe),
              _buildStickerContent(cs, isMe),
              if (hasReactions) _buildInlineReactions(cs, isMe),
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(widget.message.timestamp),
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      _buildStatusIcon(widget.message.deliveryStatus, isMe, cs),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onLongPressStart: (_) {
        HapticFeedback.mediumImpact();
        _showContextMenu(context);
      },
      child: Padding(
        padding: EdgeInsets.only(
          left: isMe ? 48 : 8,
          right: isMe ? 8 : 48,
          top: 2,
          bottom: 2,
        ),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Row(
              mainAxisAlignment: isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe) const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: isMe ? _sentColor : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isMe ? 20 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 20),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            if (widget.message.forwardedFrom != null)
                              _buildForwardedPreview(cs, isMe),
                            if (widget.message.replyToId != null)
                              _buildReplyPreview(cs, isMe),
                            Padding(
                              padding:
                                  widget.message.type == MessageType.image ||
                                      widget.message.type == MessageType.sticker
                                  ? const EdgeInsets.all(8)
                                  : EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: widget.message.replyToId != null
                                          ? 6
                                          : 10,
                                    ),
                              child: _buildContent(context, cs, isMe),
                            ),
                            if (hasReactions) _buildInlineReactions(cs, isMe),
                            if (widget.message.keyboard != null)
                              _buildInlineKeyboard(cs),
                            Padding(
                              padding: EdgeInsets.only(
                                left: 10,
                                right: 10,
                                bottom: 6,
                                top: hasReactions ? 0 : 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.message.isPinned) ...[
                                    Icon(
                                      Icons.push_pin,
                                      size: 10,
                                      color:
                                          (isMe
                                                  ? Colors.white54
                                                  : cs.onSurfaceVariant)
                                              .withValues(alpha: 0.5),
                                    ),
                                    const SizedBox(width: 2),
                                  ],
                                  if (widget.message.isEdited) ...[
                                    Text(
                                      'edited ',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontStyle: FontStyle.italic,
                                        color:
                                            (isMe
                                                    ? Colors.white70
                                                    : cs.onSurfaceVariant)
                                                .withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                  Text(
                                    _formatTime(widget.message.timestamp),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color:
                                          (isMe
                                                  ? Colors.white70
                                                  : cs.onSurfaceVariant)
                                              .withValues(alpha: 0.6),
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(width: 4),
                                    _buildStatusIcon(
                                      widget.message.deliveryStatus,
                                      isMe,
                                      cs,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineKeyboard(ColorScheme cs) {
    final keyboard = widget.message.keyboard!;
    if (keyboard.rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in keyboard.rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (final btn in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: SizedBox(
                          height: 36,
                          child: OutlinedButton(
                            onPressed: () => _onButtonPressed(btn),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              side: BorderSide(color: cs.outlineVariant),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (btn.url != null) ...[
                                  Icon(
                                    Icons.open_in_new,
                                    size: 14,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Text(
                                    btn.text,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _onButtonPressed(InlineKeyboardButton btn) {
    if (btn.url != null && btn.url!.isNotEmpty) {
      launchUrl(Uri.parse(btn.url!), mode: LaunchMode.externalApplication);
    } else if (btn.sendMessage != null && btn.sendMessage!.isNotEmpty) {
      widget.onKeyboardSendMessage?.call(btn.sendMessage!);
    } else if (btn.callbackData != null) {
      widget.onKeyboardButton?.call(btn.callbackData!);
    }
  }

  Widget _buildInlineReactions(ColorScheme cs, bool isMe) {
    final reactions = widget.message.reactions;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 3,
        children: reactions.map((r) {
          final hasReacted = r.hasUser(widget.currentUserId);
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _handleReaction(r.emoji);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: hasReacted
                    ? (isMe
                          ? Colors.white.withValues(alpha: 0.2)
                          : cs.primary.withValues(alpha: 0.12))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 3),
                  if (r.count <= 2) ...[
                    ...r.users
                        .take(2)
                        .map(
                          (u) => Padding(
                            padding: const EdgeInsets.only(left: 1),
                            child: _buildReactionAvatar(u, isMe, cs),
                          ),
                        ),
                  ] else ...[
                    _buildReactionAvatar(r.users.first, isMe, cs),
                    const SizedBox(width: 2),
                    Text(
                      '${r.count}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isMe ? Colors.white70 : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildReactionAvatar(ReactionUser user, bool isMe, ColorScheme cs) {
    const size = 14.0;
    final hasAvatar = user.avatarUrl.isNotEmpty;

    Widget avatar;

    if (hasAvatar && user.avatarUrl.startsWith('data:image')) {
      try {
        final base64Data = user.avatarUrl.split(',').last;
        final bytes = base64Decode(base64Data);
        avatar = ClipOval(
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {
        avatar = _reactionInitials(user, size, isMe, cs);
      }
    } else if (hasAvatar) {
      avatar = ClipOval(
        child: Image.network(
          user.avatarUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _reactionInitials(user, size, isMe, cs),
        ),
      );
    } else {
      avatar = _reactionInitials(user, size, isMe, cs);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isMe
              ? _sentColor.withValues(alpha: 0.5)
              : cs.surfaceContainerHighest,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatar,
    );
  }

  Widget _reactionInitials(
    ReactionUser user,
    double size,
    bool isMe,
    ColorScheme cs,
  ) {
    final initial = user.displayName.isNotEmpty
        ? user.displayName[0].toUpperCase()
        : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isMe
            ? Colors.white.withValues(alpha: 0.2)
            : cs.primary.withValues(alpha: 0.15),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.5,
            fontWeight: FontWeight.w600,
            color: isMe ? Colors.white70 : cs.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme cs, bool isMe) {
    switch (widget.message.type) {
      case MessageType.text:
        if (widget.searchQuery != null && widget.searchQuery!.isNotEmpty) {
          return _buildHighlightedText(
            widget.message.content,
            widget.searchQuery!,
            TextStyle(
              color: isMe ? Colors.white : cs.onSurface,
              fontSize: 15,
              height: 1.35,
            ),
            widget.isCurrentSearchMatch,
          );
        }
        return Text(
          widget.message.content,
          style: TextStyle(
            color: isMe ? Colors.white : cs.onSurface,
            fontSize: 15,
            height: 1.35,
          ),
        );

      case MessageType.image:
        final url = widget.message.content;
        final fullUrl = url.startsWith('/uploads')
            ? '${AppConfig.apiBaseUrl}$url'
            : url;
        return GestureDetector(
          onTap: () => _openFullScreenImage(context, fullUrl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260, maxHeight: 320),
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMe ? 20 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 20),
              ),
              child: Image.network(
                fullUrl,
                fit: BoxFit.cover,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    width: 180,
                    height: 180,
                    color: Colors.grey[300],
                    child: const Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  width: 180,
                  height: 180,
                  color: Colors.grey[300],
                  child: const Center(
                    child: Icon(
                      Icons.broken_image,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

      case MessageType.file:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white.withValues(alpha: 0.2)
                    : cs.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.attach_file,
                color: isMe ? Colors.white70 : cs.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              widget.message.fileSize ?? '',
              style: TextStyle(
                color: isMe ? Colors.white70 : cs.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        );

      case MessageType.premiumMessage:
        return _buildPremiumContent(cs, isMe);

      case MessageType.voice:
        return _buildVoiceContent(cs, isMe);

      case MessageType.sticker:
        return _buildStickerContent(cs, isMe);
      case MessageType.invoice:
        return _buildInvoiceContent(cs, isMe);
      case MessageType.check:
        return _buildCheckContent(cs, isMe);
    }
  }

  Widget _buildInvoiceContent(ColorScheme cs, bool isMe) {
    final invoice = InvoiceData.tryParse(widget.message.content);
    if (invoice == null) {
      return Text(
        'Invalid invoice',
        style: TextStyle(color: cs.error, fontSize: 14),
      );
    }
    final paid = _invoicePaid || invoice.status == 'paid';
    final payable = invoice.lamports != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withValues(alpha: 0.14)
              : cs.primaryContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isMe
                ? Colors.white.withValues(alpha: 0.2)
                : cs.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.receipt_long,
                  size: 18,
                  color: isMe ? Colors.white : cs.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Invoice',
                  style: TextStyle(
                    color: isMe ? Colors.white70 : cs.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${invoice.amount} ${invoice.currency}',
              style: TextStyle(
                color: isMe ? Colors.white : cs.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '→ ${_shortAddr(invoice.recipient)}',
              style: TextStyle(
                color: isMe ? Colors.white70 : cs.onSurfaceVariant,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (invoice.memo != null && invoice.memo!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                invoice.memo!,
                style: TextStyle(
                  color: isMe ? Colors.white60 : cs.onSurfaceVariant,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            if (paid) ...[
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: isMe ? Colors.white : Colors.green,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Paid',
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.green,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (invoice.txSignature != null &&
                  invoice.txSignature!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Tx: ${invoice.txSignature!.length > 16 ? '${invoice.txSignature!.substring(0, 8)}...${invoice.txSignature!.substring(invoice.txSignature!.length - 6)}' : invoice.txSignature}',
                  style: TextStyle(
                    color: isMe ? Colors.white60 : cs.onSurfaceVariant,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 12,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Devnet — tokens have no real value',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_invoicePaying)
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isMe ? Colors.white : cs.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Sending…',
                    style: TextStyle(
                      color: isMe ? Colors.white70 : cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              )
            else if (payable && !isMe)
              FilledButton.icon(
                onPressed: _payInvoice,
                icon: const Icon(Icons.account_balance_wallet, size: 18),
                label: const Text('Pay'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(38),
                ),
              )
            else if (payable)
              Text(
                'Awaiting payment',
                style: TextStyle(
                  color: isMe ? Colors.white70 : cs.onSurfaceVariant,
                  fontSize: 13,
                ),
              )
            else
              Text(
                'Payment in ${invoice.currency} is not supported yet',
                style: TextStyle(
                  color: isMe ? Colors.white60 : cs.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _shortAddr(String a) =>
      a.length <= 10 ? a : '${a.substring(0, 4)}…${a.substring(a.length - 4)}';

  Future<void> _payInvoice() async {
    final invoice = InvoiceData.tryParse(widget.message.content);
    if (invoice == null || invoice.lamports == null) return;
    // Capture IDs before any async gaps — the widget may unmount during
    // the Phantom deep-link handoff.
    final messageId = widget.message.id;
    final invoiceContent = widget.message.content;
    if (!mounted) return;
    setState(() => _invoicePaying = true);
    try {
      final ctx = context;
      const proxy = WalletAccessProxy();
      var binding = await proxy.getBinding();
      if (!binding.bound) {
        if (!mounted) return;
        await AppState.instance.restoreExternalWalletSession(ctx);
        binding = await proxy.getBinding();
      }
      if (!binding.bound) {
        if (!mounted) return;
        await AppState.instance.connectExternalWallet(ctx);
      }
      if (!mounted) return;
      final res = await proxy.paySolana(
        ctx,
        recipient: invoice.recipient,
        lamports: invoice.lamports!,
        memo: invoice.memo,
      );
      if (kDebugMode) debugPrint('[invoice] paySolana ok');
      // ── Server sync ── runs even if widget unmounted ──
      final txSig = res.signature ?? '';
      bool synced = false;
      try {
        synced = await ApiService.markInvoicePaid(messageId, txSig);
        if (kDebugMode) debugPrint('[invoice] markInvoicePaid');
      } catch (e) {
        debugPrint('[invoice] markInvoicePaid error: $e');
      }
      if (!synced) {
        _syncInvoicePaidWithRetry(messageId, txSig);
      }
      // ── Update local UI (only if still mounted) ──
      if (mounted) {
        setState(() {
          _invoicePaid = true;
          _invoicePaying = false;
        });
      }
      // Push content update to parent (survives rebuilds via _messages)
      final parsed = InvoiceData.tryParse(invoiceContent);
      if (parsed != null) {
        final updated = parsed.copyWith(status: 'paid', txSignature: txSig);
        widget.onInvoicePaid?.call(messageId, updated.encode());
      }
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text('Paid: $txSig')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _invoicePaying = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: const Text(
              'Payment error. If you already paid, press \"Sync\"',
            ),
            action: SnackBarAction(
              label: 'Sync',
              onPressed: () => _syncInvoicePaid(),
            ),
            duration: const Duration(seconds: 10),
          ),
        );
      } else {
        // Widget gone — try server sync in background (user may have paid)
        _syncInvoicePaidWithRetry(messageId, '');
      }
    }
  }

  Future<void> _syncInvoicePaid() async {
    final invoice = InvoiceData.tryParse(widget.message.content);
    if (invoice == null || invoice.lamports == null) return;
    if (!mounted) return;
    setState(() => _invoicePaying = true);
    try {
      final synced = await ApiService.markInvoicePaid(widget.message.id, '');
      if (!mounted) return;
      setState(() {
        _invoicePaid = synced;
        _invoicePaying = false;
      });
      if (synced) {
        final parsed = InvoiceData.tryParse(widget.message.content);
        if (parsed != null) {
          final updated = parsed.copyWith(status: 'paid');
          widget.onInvoicePaid?.call(widget.message.id, updated.encode());
        }
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('Status synced')));
      } else {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Server did not confirm payment. Check the status later.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _invoicePaying = false);
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Sync error: $e')));
    }
  }

  void _syncInvoicePaidWithRetry(String messageId, String txSig) async {
    for (var delay = 2; delay <= 30; delay *= 2) {
      await Future.delayed(Duration(seconds: delay));
      try {
        final synced = await ApiService.markInvoicePaid(messageId, txSig);
        if (synced) return;
      } catch (_) {}
    }
  }

  Widget _buildCheckContent(ColorScheme cs, bool isMe) {
    final check = CheckData.tryParse(widget.message.content);
    if (check == null) {
      return Text(
        'Invalid check',
        style: TextStyle(color: cs.error, fontSize: 14),
      );
    }
    final redeemed = check.status == 'redeemed';
    final isCreator = check.creatorId == widget.currentUserId;
    final sol = check.lamports != null ? check.lamports! / 1e9 : 0.0;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: redeemed
                ? [Colors.grey.shade600, Colors.grey.shade700]
                : [const Color(0xFFF59E0B), const Color(0xFFD97706)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  redeemed ? Icons.receipt_long : Icons.card_giftcard,
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  redeemed ? 'Check redeemed' : 'Check',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${sol.toStringAsFixed(9)} ${check.currency}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (redeemed && check.txSignature != null) ...[
              const SizedBox(height: 4),
              Text(
                'Tx: ${check.txSignature!.length > 16 ? '${check.txSignature!.substring(0, 8)}...${check.txSignature!.substring(check.txSignature!.length - 6)}' : check.txSignature}',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            if (redeemed)
              Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 16,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isCreator ? 'Your check has been redeemed' : 'Redeemed',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            else if (!isCreator) ...[
              // Show wallet info
              if (_myWalletAddress != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _hasBuiltInWallet ? Icons.check_circle : Icons.warning,
                        size: 12,
                        color: _hasBuiltInWallet
                            ? Colors.green.shade200
                            : Colors.orange.shade200,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _hasBuiltInWallet
                              ? 'To: ${_myWalletAddress!.substring(0, 4)}...${_myWalletAddress!.substring(_myWalletAddress!.length - 4)}'
                              : 'Phantom — limitations on-chain. Create built-in wallet.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 10,
                            fontFamily: _hasBuiltInWallet ? 'monospace' : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _hasBuiltInWallet
                      ? () => _redeemCheck(check)
                      : null,
                  icon: const Icon(Icons.redeem, size: 18),
                  label: Text(
                    _hasBuiltInWallet ? 'Redeem' : 'Built-in wallet required',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _hasBuiltInWallet
                        ? const Color(0xFFD97706)
                        : Colors.grey,
                  ),
                ),
              ),
            ] else
              const Text(
                'Awaiting redemption',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 12,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Devnet — tokens have no real value',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _redeemCheck(CheckData check) async {
    if (!mounted) return;

    final appState = AppState.instance;
    final binding = await const WalletAccessProxy().getBinding();
    if (!binding.bound || binding.publicKey == null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Connect a wallet first')));
      return;
    }

    if (!_hasBuiltInWallet) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'On-chain checks require a built-in wallet. Phantom does not support custom programs via deep link.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // Use the built-in wallet address as fee payer since we sign with its
    // keypair.  getBinding() may return a WalletConnect address when Phantom
    // is also connected, which would cause an AccountNotSigner error.
    final walletAddress = appState.wallet!.address;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redeem Check'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount: ${check.amount} ${check.currency}'),
            const SizedBox(height: 8),
            const Text(
              'Recipient:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text(
              walletAddress,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _invoicePaying = true);
    try {
      final pdaAddress = check.checkId ?? widget.message.id;
      if (pdaAddress.isEmpty) throw Exception('No PDA address for this check');

      final creatorAddr = check.creatorAddress;
      if (creatorAddr == null || creatorAddr.isEmpty) {
        throw Exception(
          'Creator wallet address unknown — cannot redeem legacy check',
        );
      }

      final escrowService = CheckEscrowService(appState.solana.client);
      final txSig = await escrowService.redeemCheck(
        wallet: appState.wallet,
        wcClient: appState.walletConnectClient,
        feePayerAddress: walletAddress,
        pdaAddress: pdaAddress,
        creatorAddress: creatorAddr,
      );

      await ApiService.redeemCheck(pdaAddress, txSignature: txSig);

      if (!mounted) return;
      setState(() => _invoicePaying = false);

      final updated = check.copyWith(
        status: 'redeemed',
        redeemerId: widget.currentUserId,
        txSignature: txSig,
      );
      widget.onInvoicePaid?.call(widget.message.id, updated.encode());
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Check redeemed: $txSig')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _invoicePaying = false);
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildVoiceContent(ColorScheme cs, bool isMe) {
    final totalDuration = _duration.inMilliseconds > 0
        ? _duration
        : Duration(milliseconds: widget.message.voiceDurationMs ?? 0);

    final progress = totalDuration.inMilliseconds > 0
        ? (_position.inMilliseconds / totalDuration.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    final displayDuration = _isPlaying || _position.inMilliseconds > 0
        ? _position
        : totalDuration;

    final barCount = _waveform.length;
    final playedIndex = (progress * barCount).floor();

    return Stack(
      children: [
        // Waveform background
        GestureDetector(
          onTapDown: (details) async {
            if (_player == null || _duration.inMilliseconds == 0) return;
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            final localX = details.localPosition.dx;
            final waveformWidth = box.size.width;
            if (waveformWidth <= 0) return;
            final tapProgress = (localX / waveformWidth).clamp(0.0, 1.0);
            final seekMs = (tapProgress * _duration.inMilliseconds).round();
            await _player!.seek(Duration(milliseconds: seekMs));
          },
          child: SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(barCount, (i) {
                final height = _waveform[i] * 44.0 + 4.0;
                final isPlayed = i <= playedIndex;
                final barColor = isPlayed
                    ? (isMe ? Colors.white : cs.primary)
                    : (isMe
                          ? Colors.white.withValues(alpha: 0.3)
                          : cs.onSurfaceVariant.withValues(alpha: 0.3));

                return Expanded(
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: 2.5,
                      height: height,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        // Overlay: play button + duration
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _togglePlayback,
                child: _isLoading
                    ? SizedBox(
                        width: 36,
                        height: 36,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isMe ? Colors.white : cs.primary,
                            ),
                          ),
                        ),
                      )
                    : Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.2)
                              : cs.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: isMe ? Colors.white : cs.primary,
                          size: 22,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDuration(displayDuration),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: (isMe ? Colors.white : cs.onSurface).withValues(
                        alpha: 0.9,
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(totalDuration),
                    style: TextStyle(
                      fontSize: 10,
                      color: (isMe ? Colors.white : cs.onSurfaceVariant)
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWaveform(bool isMe, double progress) {
    final barCount = _waveform.length;
    final playedIndex = (progress * barCount).floor();

    return GestureDetector(
      onTapDown: (details) async {
        if (_player == null || _duration.inMilliseconds == 0) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final localX = details.localPosition.dx;
        final waveformWidth = box.size.width;
        if (waveformWidth <= 0) return;
        final tapProgress = (localX / waveformWidth).clamp(0.0, 1.0);
        final seekMs = (tapProgress * _duration.inMilliseconds).round();
        await _player!.seek(Duration(milliseconds: seekMs));
      },
      child: SizedBox(
        height: 32,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(barCount, (i) {
            final height = _waveform[i] * 28.0 + 4.0;
            final isPlayed = i <= playedIndex;
            final barColor = isPlayed
                ? (isMe ? Colors.white : Theme.of(context).colorScheme.primary)
                : (isMe
                      ? Colors.white.withValues(alpha: 0.3)
                      : Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3));

            return Expanded(
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 2.5,
                  height: height,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  void _openFullScreenImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                },
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(
                    Icons.broken_image,
                    size: 64,
                    color: Colors.white54,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStickerContent(ColorScheme cs, bool isMe) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160, maxHeight: 160),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: StickerWidget(
          url: widget.message.content,
          width: 160,
          height: 160,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildPremiumContent(ColorScheme cs, bool isMe) {
    if (widget.message.premiumInfo != null &&
        widget.message.premiumInfo!.isUnlocked) {
      return Text(
        widget.message.content,
        style: TextStyle(
          color: isMe ? Colors.white : cs.onSurface,
          fontSize: 15,
          height: 1.35,
        ),
      );
    }

    return Column(
      children: [
        Icon(
          Icons.lock_outline,
          color: isMe ? Colors.white70 : cs.onSurfaceVariant,
          size: 28,
        ),
        const SizedBox(height: 8),
        Text(
          'Premium Message',
          style: TextStyle(
            color: isMe ? Colors.white : cs.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap to unlock',
          style: TextStyle(
            color: isMe ? Colors.white70 : cs.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildForwardedPreview(ColorScheme cs, bool isMe) {
    final forwarded = widget.message.forwardedFrom!;
    final barColor = isMe ? Colors.white70 : cs.primary;

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: isMe
          ? const EdgeInsets.only(left: 8, right: 10, top: 3, bottom: 2)
          : const EdgeInsets.only(left: 10, right: 8, top: 3, bottom: 2),
      decoration: BoxDecoration(
        border: isMe
            ? Border(right: BorderSide(color: barColor, width: 3))
            : Border(left: BorderSide(color: barColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forward, size: 14, color: barColor),
              const SizedBox(width: 4),
              Text(
                'Forwarded from',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: barColor,
                  height: 1.2,
                ),
              ),
            ],
          ),
          Text(
            forwarded.originalSenderName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: barColor,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview(ColorScheme cs, bool isMe) {
    final senderName = widget.message.replyToSenderName ?? '';
    final replyContent = widget.message.replyToContent ?? '';
    final displayContent = replyContent.isEmpty ? '📷 Photo' : replyContent;
    final barColor = isMe ? Colors.white70 : cs.primary;

    return GestureDetector(
      onTap: () {
        // TODO: scroll to original message by replyToId
      },
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: isMe
            ? const EdgeInsets.only(left: 8, right: 10, top: 3, bottom: 2)
            : const EdgeInsets.only(left: 10, right: 8, top: 3, bottom: 2),
        decoration: BoxDecoration(
          border: isMe
              ? Border(right: BorderSide(color: barColor, width: 3))
              : Border(left: BorderSide(color: barColor, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              senderName,
              textAlign: isMe ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: barColor,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              displayContent,
              textAlign: isMe ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: (isMe ? Colors.white60 : cs.onSurfaceVariant).withValues(
                  alpha: 0.7,
                ),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildStatusIcon(DeliveryStatus status, bool isMe, ColorScheme cs) {
    final color = (isMe ? Colors.white70 : cs.onSurfaceVariant).withValues(
      alpha: 0.6,
    );
    switch (status) {
      case DeliveryStatus.sending:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
        );
      case DeliveryStatus.sent:
        return Icon(Icons.check, size: 14, color: color);
      case DeliveryStatus.delivered:
        return Icon(Icons.done_all, size: 14, color: color);
      case DeliveryStatus.read:
        return const Icon(Icons.done_all, size: 14, color: Color(0xFF22C55E));
    }
  }

  Widget _buildHighlightedText(
    String text,
    String query,
    TextStyle style,
    bool isCurrent,
  ) {
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start), style: style));
        }
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: style));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: style.copyWith(
            backgroundColor: isCurrent
                ? const Color(0xFFFFEB3B)
                : const Color(0xFFFFEB3B).withValues(alpha: 0.5),
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      start = index + query.length;
    }

    return RichText(text: TextSpan(children: spans));
  }
}
