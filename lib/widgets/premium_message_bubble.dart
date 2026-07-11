// lib/widgets/premium_message_bubble.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/models/chat_message.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/chat_media_service.dart';
import 'package:azaman/services/friend_service.dart';
import 'package:azaman/widgets/chat_media_bubble.dart';
import 'package:azaman/widgets/chat_money_card.dart';
import 'package:hugeicons_pro/hugeicons.dart';

/// Callback typedef for swipe-to-reply gesture.
typedef OnReplyCallback = void Function(ChatMessage message);
typedef OnReactCallback = void Function(String messageId, String emoji);
typedef OnEditCallback  = void Function(ChatMessage message);
typedef OnDeleteCallback = void Function(String messageId);

/// Single unified bubble — paste into any chat ListView.builder.
class PremiumMessageBubble extends ConsumerStatefulWidget {
  final ChatMessage message;
  final bool showAvatar;   // show sender avatar (groups only)
  final bool showSenderName; // show name above bubble (groups only)
  final int myUserId;
  final OnReplyCallback? onReply;
  final OnReactCallback? onReact;
  final OnEditCallback?  onEdit;
  final OnDeleteCallback? onDelete;
  final VoidCallback? onRetry; // called on failed bubble tap

  const PremiumMessageBubble({
    super.key,
    required this.message,
    required this.myUserId,
    this.showAvatar = false,
    this.showSenderName = false,
    this.onReply,
    this.onReact,
    this.onEdit,
    this.onDelete,
    this.onRetry,
  });

  @override
  ConsumerState<PremiumMessageBubble> createState() => _State();
}

class _State extends ConsumerState<PremiumMessageBubble>
    with SingleTickerProviderStateMixin {
  double _swipeDx = 0;
  bool _swipeTriggered = false;
  late AnimationController _replyCtrl;
  late Animation<double> _replyAnim;

  @override
  void initState() {
    super.initState();
    _replyCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));
    _replyAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _replyCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _replyCtrl.dispose(); super.dispose(); }

  bool get _isMe => widget.message.isMe;
  bool get _isDeleted => widget.message.isDeleted;

  // ── STATUS TICK WIDGET (Telegram 3-state) ──────────────────────────────
  Widget _statusTick(AzamanColors c) {
    switch (widget.message.status) {
      case MessageStatus.sending:
        return Icon(Icons.access_time_rounded, size: 12, color: c.textTertiary.withOpacity(0.5));
      case MessageStatus.sent:
        return Icon(HugeIconsSolid.checkmarkCircle01, size: 12, color: c.textTertiary);
      case MessageStatus.delivered:
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(HugeIconsSolid.checkmarkCircle01, size: 11, color: c.textTertiary),
          const SizedBox(width: -3),
          Icon(HugeIconsSolid.checkmarkCircle01, size: 11, color: c.textTertiary),
        ]);
      case MessageStatus.read:
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(HugeIconsSolid.checkmarkCircle02, size: 11, color: c.accent),
          const SizedBox(width: -3),
          Icon(HugeIconsSolid.checkmarkCircle02, size: 11, color: c.accent),
        ]);
      case MessageStatus.failed:
        return GestureDetector(
          onTap: widget.onRetry,
          child: Icon(Icons.error_outline_rounded, size: 14, color: c.danger),
        );
    }
  }

  // ── REPLY QUOTE HEADER ─────────────────────────────────────────────────
  Widget _replyHeader(AzamanColors c) {
    final msg = widget.message;
    if (msg.replyToId == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: _isMe
          ? Colors.white.withOpacity(0.15)
          : c.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(
          color: _isMe ? Colors.white.withOpacity(0.6) : c.accent,
          width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(msg.replyToSenderName ?? 'Message',
          style: TextStyle(
            color: _isMe ? Colors.white : c.accent,
            fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(msg.replyToText ?? '',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _isMe ? Colors.white.withOpacity(0.75) : c.textSecondary,
            fontSize: 11)),
      ]),
    );
  }

  // ── REACTION SHELF ─────────────────────────────────────────────────────
  Widget _reactionShelf(AzamanColors c) {
    final reactions = widget.message.reactions;
    if (reactions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 4, runSpacing: 4,
        alignment: _isMe ? WrapAlignment.end : WrapAlignment.start,
        children: reactions.entries.map((e) {
          final iMine = e.value.contains(widget.myUserId);
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onReact?.call(widget.message.id, e.key);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: iMine
                  ? c.accent.withOpacity(0.18)
                  : c.softSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: iMine ? c.accent.withOpacity(0.5) : c.divider,
                  width: 0.8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(e.key, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 3),
                Text('${e.value.length}',
                  style: TextStyle(
                    color: iMine ? c.accent : c.textSecondary,
                    fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── TRANSFER REQUEST — accept / decline sheet ──────────────────────────
  // Only shown to the payer (the person who received the request, i.e.
  // !isMe on a TRANSFER_REQUEST message). Calls the same endpoints the
  // rest of the app already uses for this (friend_service.dart).
  void _respondToTransferRequest(BuildContext ctx, AzamanColors c, ChatMessage msg) {
    final meta = msg.metadata ?? const {};
    final transferId = meta['transferId']?.toString();
    if (transferId == null || _isMe) return; // only the payer can respond

    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${msg.senderUsername ?? 'They'} requested ${(msg.amount ?? 0).toStringAsFixed(2)} ${msg.currency ?? 'USDC'}',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: c.accent, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.of(sheetCtx).pop();
                await _fulfillOrDecline(ctx, transferId, fulfill: true);
              },
              child: const Text('Pay', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: c.textSecondary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.of(sheetCtx).pop();
                await _fulfillOrDecline(ctx, transferId, fulfill: false);
              },
              child: const Text('Decline'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fulfillOrDecline(BuildContext ctx, String transferId, {required bool fulfill}) async {
    final token = ref.read(authProvider).user?.token;
    if (token == null) return;
    try {
      if (fulfill) {
        await FriendService().fulfillTransfer(transferId, token);
      } else {
        await FriendService().declineTransfer(transferId, token);
      }
      // The socket layer (friend_transfer_* events, already wired backend-
      // side) pushes the resulting TRANSFER_COMPLETED / TRANSFER_DECLINED
      // message into the chat stream — no local state mutation needed here.
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(fulfill ? 'Could not complete payment' : 'Could not decline request')),
        );
      }
    }
  }

  // ── LONG PRESS CONTEXT MENU ────────────────────────────────────────────
  void _showContextMenu(BuildContext ctx, AzamanColors c) {
    HapticFeedback.mediumImpact();
    final msg = widget.message;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContextMenuSheet(
        message: msg,
        colors: c,
        isMe: _isMe,
        onReact: widget.onReact,
        onReply: widget.onReply,
        onEdit: widget.onEdit,
        onDelete: widget.onDelete,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(themeProvider).colors;
    final msg = widget.message;

    // Deleted placeholder
    if (_isDeleted) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        child: Row(
          mainAxisAlignment:
            _isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: c.softSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.divider, width: 0.8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.not_interested_rounded, size: 13, color: c.textTertiary),
                const SizedBox(width: 6),
                Text('This message was deleted',
                  style: TextStyle(color: c.textTertiary,
                    fontSize: 12, fontStyle: FontStyle.italic)),
              ]),
            ),
          ],
        ),
      );
    }

    // Peer-to-peer money transfer — rendered as an animated card instead of
    // the normal text bubble chrome (2026-07-06).
    if (msg.kind == MessageKind.peerTransfer || msg.kind == MessageKind.transferRequest) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Row(
          mainAxisAlignment: _isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!_isMe && widget.showAvatar) ...[
              _AvatarChip(username: msg.senderUsername ?? '?', avatarUrl: msg.senderAvatar, colors: c),
              const SizedBox(width: 6),
            ],
            ChatMoneyCard(
              amount: msg.amount ?? 0.0,
              currency: msg.currency ?? 'USDC',
              isMe: _isMe,
              contactName: !_isMe ? (msg.senderUsername ?? 'Unknown') : '',
              status: msg.metadata?['status']?.toString().toLowerCase() ?? 'completed',
              isRequest: msg.kind == MessageKind.transferRequest,
              reference: msg.metadata?['reference']?.toString(),
              memo: msg.text.isNotEmpty ? msg.text : null,
              timestamp: msg.timestamp,
              skinId: msg.metadata?['cardSkin']?.toString(),
              onAccept: msg.kind == MessageKind.transferRequest && !_isMe
                  ? () => _respondToTransferRequest(context, c, msg)
                  : null,
              onDecline: msg.kind == MessageKind.transferRequest && !_isMe
                  ? () => _respondToTransferRequest(context, c, msg)
                  : null,
            ),
          ],
        ),
      );
    }

    // Swipe-to-reply wrapper (Telegram-style)
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        final dir = _isMe ? -1.0 : 1.0;
        final delta = d.primaryDelta ?? 0;
        if ((dir > 0 && delta > 0) || (dir < 0 && delta < 0)) {
          setState(() {
            _swipeDx = (_swipeDx + delta * dir).clamp(0.0, 60.0);
          });
        }
      },
      onHorizontalDragEnd: (_) {
        if (_swipeDx > 38 && !_swipeTriggered) {
          _swipeTriggered = true;
          HapticFeedback.mediumImpact();
          widget.onReply?.call(msg);
          _replyCtrl.forward(from: 0).then((_) => _replyCtrl.reverse());
        }
        setState(() { _swipeDx = 0; _swipeTriggered = false; });
      },
      child: Transform.translate(
        offset: Offset(_isMe ? -_swipeDx : _swipeDx, 0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Row(
            mainAxisAlignment:
              _isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Avatar (groups only)
              if (!_isMe && widget.showAvatar) ...[
                _AvatarChip(
                  username: msg.senderUsername ?? '?',
                  avatarUrl: msg.senderAvatar,
                  colors: c,
                ),
                const SizedBox(width: 6),
              ] else if (!_isMe && widget.showAvatar) ...[
                const SizedBox(width: 34),
              ],

              // Reply arrow icon (shows at the left of a right-swipe)
              if (_swipeDx > 12)
                AnimatedOpacity(
                  opacity: (_swipeDx / 60).clamp(0.0, 1.0),
                  duration: const Duration(milliseconds: 80),
                  child: Icon(HugeIconsSolid.arrowTurnBackward,
                    size: 18, color: c.accent),
                ),
              if (_swipeDx > 12) const SizedBox(width: 6),

              // MAIN BUBBLE
              Flexible(
                child: GestureDetector(
                  onLongPress: () => _showContextMenu(context, c),
                  child: Column(
                    crossAxisAlignment: _isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                    children: [
                      // Sender name (groups only)
                      if (!_isMe && widget.showSenderName)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 2),
                          child: Text(msg.senderUsername ?? '',
                            style: TextStyle(color: c.accent,
                              fontSize: 11, fontWeight: FontWeight.w700)),
                        ),

                      // Bubble body
                      Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.72),
                        decoration: BoxDecoration(
                          color: _isMe ? c.accent : c.card,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(_isMe ? 18 : 4),
                            bottomRight: Radius.circular(_isMe ? 4 : 18),
                          ),
                          boxShadow: [BoxShadow(
                            color: Colors.black.withOpacity(
                              c.isDark ? 0.3 : 0.06),
                            blurRadius: 8, offset: const Offset(0,2))],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12,10,12,8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Reply quote
                              _replyHeader(c),
                              // Media bubble
                              if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty)
                                ChatMediaBubble(
                                  payload: ChatMediaPayload(
                                    type: (msg.mediaType ?? 'IMAGE').toUpperCase(),
                                    url: msg.mediaUrl,
                                    mimeType: msg.mediaMimeType,
                                    duration: msg.mediaDuration,
                                    waveformPeaks: msg.waveformPeaks,
                                    linkPreview: msg.linkPreview != null ? LinkPreview.fromJson(msg.linkPreview!) : null,
                                    caption: msg.text.isNotEmpty ? msg.text : null,
                                  ),
                                  isMe: _isMe,
                                ),
                              // Text content
                              if (msg.text.isNotEmpty && msg.mediaUrl == null)
                                Text(msg.text,
                                  style: TextStyle(
                                    color: _isMe ? Colors.white : c.textPrimary,
                                    fontSize: 14.5, height: 1.4,
                                    fontWeight: FontWeight.w400)),
                              const SizedBox(height: 4),
                              // Timestamp + status row
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (msg.isEdited)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Text('edited',
                                        style: TextStyle(
                                          color: _isMe
                                            ? Colors.white.withOpacity(0.6)
                                            : c.textTertiary,
                                          fontSize: 10,
                                          fontStyle: FontStyle.italic)),
                                    ),
                                  Text(_fmtTime(msg.timestamp),
                                    style: TextStyle(
                                      color: _isMe
                                        ? Colors.white.withOpacity(0.65)
                                        : c.textTertiary,
                                      fontSize: 10)),
                                  if (_isMe) ...[
                                    const SizedBox(width: 4),
                                    _statusTick(c),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Reactions shelf (below bubble)
                      _reactionShelf(c),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.hour >= 12 ? "PM" : "AM"}';
  }
}

// ── AVATAR CHIP ─────────────────────────────────────────────────────────────
class _AvatarChip extends StatelessWidget {
  final String username;
  final String? avatarUrl;
  final AzamanColors colors;
  const _AvatarChip({required this.username, this.avatarUrl, required this.colors});
  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 14,
      backgroundColor: colors.accent.withOpacity(0.2),
      backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
        ? NetworkImage(avatarUrl!) : null,
      child: avatarUrl == null || avatarUrl!.isEmpty
        ? Text(username.isNotEmpty ? username[0].toUpperCase() : '?',
            style: TextStyle(color: colors.accent, fontSize: 11,
              fontWeight: FontWeight.w700))
        : null,
    );
  }
}

// ── CONTEXT MENU SHEET ───────────────────────────────────────────────────────
// Long-press sheet: reaction bar + actions (Reply, Edit, Delete, Copy, Forward)
class _ContextMenuSheet extends StatelessWidget {
  final ChatMessage message;
  final AzamanColors colors;
  final bool isMe;
  final OnReactCallback? onReact;
  final OnReplyCallback? onReply;
  final OnEditCallback?  onEdit;
  final OnDeleteCallback? onDelete;

  const _ContextMenuSheet({
    required this.message, required this.colors, required this.isMe,
    this.onReact, this.onReply, this.onEdit, this.onDelete,
  });

  static const _emojis = ['👍','❤️','😂','😮','😢','🙏','🔥','✅'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Drag handle
        Center(child: Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: colors.divider,
            borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        // Emoji reaction bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: _emojis.map((e) => GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onReact?.call(message.id, e);
              Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: message.reactions[e]?.isNotEmpty == true
                  ? colors.accent.withOpacity(0.1) : Colors.transparent,
                shape: BoxShape.circle),
              child: Text(e, style: const TextStyle(fontSize: 24)),
            ),
          )).toList(),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: colors.divider),
        const SizedBox(height: 8),
        // Action list
        _ActionRow(icon: HugeIconsSolid.arrowTurnBackward,
          label: 'Reply', colors: colors,
          onTap: () { Navigator.pop(context); onReply?.call(message); }),
        if (isMe && !message.isDeleted) ...[
          _ActionRow(icon: HugeIconsSolid.pencilEdit01,
            label: 'Edit', colors: colors,
            onTap: () { Navigator.pop(context); onEdit?.call(message); }),
          _ActionRow(icon: HugeIconsSolid.delete01,
            label: 'Delete', colors: colors, isDestructive: true,
            onTap: () { Navigator.pop(context); onDelete?.call(message.id); }),
        ],
        _ActionRow(icon: HugeIconsSolid.copy01,
          label: 'Copy', colors: colors,
          onTap: () {
            Clipboard.setData(ClipboardData(text: message.text));
            Navigator.pop(context);
          }),
      ]),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon; final String label;
  final AzamanColors colors; final VoidCallback onTap;
  final bool isDestructive;
  const _ActionRow({required this.icon, required this.label,
    required this.colors, required this.onTap, this.isDestructive = false});
  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? colors.danger : colors.textPrimary;
    return ListTile(
      onTap: onTap,
      dense: true,
      leading: Icon(icon, size: 20, color: color),
      title: Text(label,
        style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500)),
    );
  }
}

