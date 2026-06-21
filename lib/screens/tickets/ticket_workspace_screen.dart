// =============================================================================
// TICKET WORKSPACE SCREEN — Phase UI-4 (2026-05-26)
//
// Isolated chat interface for a single ticket. Renders:
//   • Ticket header card (name, type, target amount + currency, status badge)
//   • Memo banner (if set)
//   • Message list (oldest at top, newest at bottom)
//   • Text input with send button
//   • Action menu in AppBar to close / cancel / reopen the ticket
//
// On mount: fires presence ping (`viewing: true`) and joins the
// `ticket_${id}` socket room. On dispose: presence ping `viewing: false`
// and leaves the room.
//
// Media bubble rendering reuses `ChatMediaBubble` (Phase UI-3).
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/escrow_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/ticket_provider.dart';
import 'package:azaman/services/chat_media_service.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/services/ticket_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/audio_recorder_button.dart';
import 'package:azaman/widgets/chat_media_bubble.dart';
import 'package:azaman/widgets/escrow_status_panel.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class TicketWorkspaceScreen extends ConsumerStatefulWidget {
  final String ticketId;
  final String friendUsername;
  const TicketWorkspaceScreen({
    super.key,
    required this.ticketId,
    required this.friendUsername,
  });

  @override
  ConsumerState<TicketWorkspaceScreen> createState() =>
      _TicketWorkspaceScreenState();
}

class _TicketWorkspaceScreenState extends ConsumerState<TicketWorkspaceScreen>
    with WidgetsBindingObserver {
  final TextEditingController _messageCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  // Phase UI-POLISH: locks the audio mic while a voice note upload is
  // in flight so a fast second hold can't kick off a parallel upload.
  bool _isUploadingAudio = false;

  // V3 Marketplace Sprint (2026-06-21): per-ticket escrow socket subscriptions.
  // We keep the handler refs so dispose() can `off(event, handler)` precisely —
  // a bare `off(event)` would also nuke SocketService's own dispatcher for that
  // event name.
  static const _escrowEvents = [
    'escrow_funded',
    'escrow_settled',
    'escrow_pending_settlement',
    'escrow_disputed',
    'escrow_resolved',
    'escrow_terms_updated',
  ];
  final List<MapEntry<String, void Function(dynamic)>> _escrowSubs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref
          .read(ticketWorkspaceProvider(widget.ticketId).notifier)
          .load();
      _joinRoom();
      _scrollToBottom();
      // Once the ticket is loaded we know whether it's an escrow; if so, load
      // the escrow state and start listening for realtime escrow_* events.
      if (!mounted) return;
      final loaded =
          ref.read(ticketWorkspaceProvider(widget.ticketId)).ticket;
      if (loaded?.type == TicketType.escrow) {
        ref.read(escrowProvider(widget.ticketId).notifier).load();
        _wireEscrowSocket();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _leaveRoom();
    _unwireEscrowSocket();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _wireEscrowSocket() {
    final socket = SocketService.instance.rawSocket;
    if (socket == null) return;
    for (final evt in _escrowEvents) {
      void handler(dynamic data) {
        try {
          final raw = data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map);
          if (raw['ticketId']?.toString() == widget.ticketId) {
            ref
                .read(escrowProvider(widget.ticketId).notifier)
                .onRealtimeUpdate(raw, evt);
            if (evt == 'escrow_settled') AzamanHaptics.confirm();
            if (evt == 'escrow_disputed') AzamanHaptics.warn();
          }
        } catch (_) {}
      }

      _escrowSubs.add(MapEntry(evt, handler));
      socket.on(evt, handler);
    }
  }

  void _unwireEscrowSocket() {
    final socket = SocketService.instance.rawSocket;
    for (final sub in _escrowSubs) {
      socket?.off(sub.key, sub.value);
    }
    _escrowSubs.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // While the workspace is mounted but the app is backgrounded, treat
    // that as "not viewing" so the counterparty's presence banner clears.
    if (state == AppLifecycleState.resumed) {
      _joinRoom();
    } else if (state == AppLifecycleState.paused) {
      _leaveRoom();
    }
  }

  void _joinRoom() {
    final socket = SocketService.instance.rawSocket;
    socket?.emit('join_ticket', {'ticketId': widget.ticketId});
    ref
        .read(ticketWorkspaceProvider(widget.ticketId).notifier)
        .pingViewing(true);
  }

  void _leaveRoom() {
    final socket = SocketService.instance.rawSocket;
    socket?.emit('leave_ticket', {'ticketId': widget.ticketId});
    ref
        .read(ticketWorkspaceProvider(widget.ticketId).notifier)
        .pingViewing(false);
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _messageCtrl.text;
    if (text.trim().isEmpty) return;
    _messageCtrl.clear();
    await ref
        .read(ticketWorkspaceProvider(widget.ticketId).notifier)
        .sendText(text);
    _scrollToBottom();
  }

  /// Phase UI-POLISH (2026-05-26): voice-note path. Uploads the audio
  /// file via `ChatMediaService.uploadAudio()` then calls the ticket
  /// REST `sendMessage` endpoint with `type: 'AUDIO'` and the full
  /// media envelope. Server-side validation in `ticketController` and
  /// the socket fanout (`ticket_message`) take it from there.
  Future<void> _onAudioRecorded(
    File file,
    int durationSeconds,
    List<int> waveformPeaks,
  ) async {
    if (!mounted) return;
    final colors = ref.read(themeProvider).colors;
    setState(() => _isUploadingAudio = true);
    try {
      final uploaded = await ChatMediaService.instance.uploadAudio(
        file,
        durationSeconds: durationSeconds,
        waveformPeaks: waveformPeaks,
      );
      final msg = await TicketService.instance.sendMessage(
        ticketId: widget.ticketId,
        type: 'AUDIO',
        mediaUrl: uploaded.url,
        mediaType: 'audio',
        mediaMimeType: uploaded.mimeType,
        mediaSize: uploaded.size,
        mediaDuration: uploaded.duration ?? durationSeconds,
        mediaWaveformPeaks: uploaded.waveformPeaks ?? waveformPeaks,
      );
      // Push into local state via the provider's realtime hook so the
      // bubble appears immediately without re-fetching the workspace.
      ref
          .read(ticketWorkspaceProvider(widget.ticketId).notifier)
          .onRealtimeMessage(msg);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Voice note failed: $e'),
          backgroundColor: colors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _isUploadingAudio = false);
    }
  }

  Future<void> _confirmAndChange(TicketStatus target) async {
    final colors = ref.read(themeProvider).colors;
    final notifier =
        ref.read(ticketWorkspaceProvider(widget.ticketId).notifier);
    final verb = target == TicketStatus.closed
        ? 'close'
        : target == TicketStatus.cancelled
            ? 'cancel'
            : 'reopen';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('${verb[0].toUpperCase()}${verb.substring(1)} ticket?',
            style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'You are about to $verb this ticket. ${target == TicketStatus.open ? 'Both parties will be able to post again.' : 'Posting will be locked thereafter; the ticket history is preserved.'}',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Back', style: TextStyle(color: colors.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(verb.toUpperCase(),
                style: TextStyle(
                  color: target == TicketStatus.cancelled
                      ? colors.danger
                      : colors.accent,
                  fontWeight: FontWeight.w800,
                )),
          ),
        ],
      ),
    );
    if (ok != true) return;
    AzamanHaptics.confirm();
    if (target == TicketStatus.open) {
      await notifier.reopen();
    } else if (target == TicketStatus.closed) {
      await notifier.close();
    } else {
      await notifier.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(ticketWorkspaceProvider(widget.ticketId));
    final myId = ref.watch(authProvider).user?.id;

    // V3 Marketplace Sprint: escrow status panel (only for ESCROW tickets).
    final isEscrow = state.ticket?.type == TicketType.escrow;
    final escrowState =
        isEscrow ? ref.watch(escrowProvider(widget.ticketId)) : null;
    final currentUser = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: state.ticket == null
            ? Text('Ticket',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.ticket!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'with ${widget.friendUsername} · ${state.ticket!.status.label}',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
        actions: [
          if (state.ticket != null)
            PopupMenuButton<TicketStatus>(
              icon: Icon(HugeIconsSolid.moreVertical, color: colors.textPrimary),
              color: colors.surface,
              onSelected: _confirmAndChange,
              itemBuilder: (_) {
                final cur = state.ticket!.status;
                final items = <PopupMenuEntry<TicketStatus>>[];
                if (cur == TicketStatus.open) {
                  items.add(PopupMenuItem(
                    value: TicketStatus.closed,
                    child: _menuRow(HugeIconsSolid.checkmarkCircle01,
                        'Close ticket', colors),
                  ));
                  items.add(PopupMenuItem(
                    value: TicketStatus.cancelled,
                    child: _menuRow(HugeIconsSolid.cancel01,
                        'Cancel ticket', colors,
                        danger: true),
                  ));
                } else {
                  items.add(PopupMenuItem(
                    value: TicketStatus.open,
                    child: _menuRow(HugeIconsSolid.refresh01,
                        'Reopen ticket', colors),
                  ));
                }
                return items;
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (escrowState != null && currentUser != null)
            EscrowStatusPanel(
              escrow: escrowState.escrow,
              currentUserId: int.tryParse(currentUser.id) ?? 0,
              isLoading: escrowState.isLoading,
              onFund: () =>
                  ref.read(escrowProvider(widget.ticketId).notifier).fund(),
              onSatisfy: () => ref
                  .read(escrowProvider(widget.ticketId).notifier)
                  .markSatisfied(),
              onDispute: (r, u) => ref
                  .read(escrowProvider(widget.ticketId).notifier)
                  .raiseDispute(r, u),
              onUpdateTerms: (t) => ref
                  .read(escrowProvider(widget.ticketId).notifier)
                  .updateTerms(t),
              onCancel: () =>
                  ref.read(escrowProvider(widget.ticketId).notifier).cancel(),
            ),
          if (state.ticket != null) _Header(ticket: state.ticket!, colors: colors),
          if (state.counterpartyViewingUserId != null)
            _PresenceBanner(colors: colors, friendName: widget.friendUsername),
          Expanded(
            child: state.isLoading && state.messages.isEmpty
                ? Center(child: CircularProgressIndicator(color: colors.accent))
                : state.messages.isEmpty
                    ? _EmptyState(colors: colors)
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: state.messages.length,
                        itemBuilder: (_, i) {
                          final msg = state.messages[i];
                          final isMe = msg.senderId.toString() == myId;
                          return _Bubble(
                              msg: msg, isMe: isMe, colors: colors);
                        },
                      ),
          ),
          if (state.ticket?.status == TicketStatus.open)
            _InputBar(
              controller: _messageCtrl,
              onSend: _send,
              onAudioRecorded: _onAudioRecorded,
              isSending: state.isSending,
              isUploadingAudio: _isUploadingAudio,
              colors: colors,
            )
          else
            _LockedFooter(status: state.ticket?.status, colors: colors),
        ],
      ),
    );
  }

  Widget _menuRow(IconData icon, String label, AzamanColors colors,
      {bool danger = false}) {
    return Row(
      children: [
        Icon(icon,
            color: danger ? colors.danger : colors.textPrimary, size: 18),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
                color: danger ? colors.danger : colors.textPrimary,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header (ticket meta card)
// ─────────────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final Ticket ticket;
  final AzamanColors colors;
  const _Header({required this.ticket, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  ticket.type.label.toUpperCase(),
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${ticket.targetAmount.toStringAsFixed(2)} ${ticket.targetCurrency}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (ticket.memo != null && ticket.memo!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              ticket.memo!,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Presence banner
// ─────────────────────────────────────────────────────────────────────────────
class _PresenceBanner extends StatelessWidget {
  final AzamanColors colors;
  final String friendName;
  const _PresenceBanner({required this.colors, required this.friendName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.accent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: colors.accent, blurRadius: 4),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$friendName is currently viewing this ticket.',
              style: TextStyle(
                color: colors.accent,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bubble
// ─────────────────────────────────────────────────────────────────────────────
class _Bubble extends StatelessWidget {
  final TicketMessageRow msg;
  final bool isMe;
  final AzamanColors colors;
  const _Bubble({required this.msg, required this.isMe, required this.colors});

  @override
  Widget build(BuildContext context) {
    final isMedia = const {
      'IMAGE',
      'VIDEO',
      'AUDIO',
      'DOCUMENT',
      'LINK',
    }.contains(msg.type);

    if (isMedia) {
      final payload = ChatMediaPayload.fromMessageJson({
        'messageType': msg.type,
        'mediaUrl': msg.mediaUrl,
        'mediaMimeType': msg.mediaMimeType,
        'mediaSize': msg.mediaSize,
        'mediaDuration': msg.mediaDuration,
        'mediaWaveformPeaks': msg.mediaWaveformPeaks,
        'linkPreview': msg.linkPreview,
        'content': msg.content,
      });
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ChatMediaBubble(payload: payload, isMe: isMe),
        ),
      );
    }

    // SYSTEM messages render as a centered ghost line.
    if (msg.type == 'SYSTEM') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            msg.content ?? '',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? colors.accent.withOpacity(0.16) : colors.card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(
            color: isMe
                ? colors.accent.withOpacity(0.25)
                : colors.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              msg.content ?? '',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(msg.createdAt),
              style: TextStyle(color: colors.textTertiary, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final AzamanColors colors;
  const _EmptyState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HugeIconsSolid.bubbleChat,
                color: colors.textTertiary, size: 36),
            const SizedBox(height: 8),
            Text('No messages yet.',
                style:
                    TextStyle(color: colors.textSecondary, fontSize: 13)),
            Text('Start the conversation about this deal.',
                style:
                    TextStyle(color: colors.textTertiary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Input bar
// ─────────────────────────────────────────────────────────────────────────────
class _InputBar extends StatefulWidget {
  final TextEditingController controller;
  final Future<void> Function() onSend;
  final Future<void> Function(File file, int durationSec, List<int> peaks)
      onAudioRecorded;
  final bool isSending;
  final bool isUploadingAudio;
  final AzamanColors colors;
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.onAudioRecorded,
    required this.isSending,
    required this.isUploadingAudio,
    required this.colors,
  });

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  bool _hasInputText = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              maxLines: 4,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              onChanged: (text) {
                final isEmpty = text.trim().isEmpty;
                if (_hasInputText == !isEmpty) return;
                setState(() => _hasInputText = !isEmpty);
              },
              decoration: InputDecoration(
                hintText: 'Type a message…',
                hintStyle: TextStyle(color: colors.textTertiary),
                filled: true,
                fillColor: colors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Phase UI-POLISH: hold-to-record audio mic when input is empty,
          // standard send arrow otherwise.
          if (!_hasInputText && !widget.isSending)
            AudioRecorderButton(
              disabled: widget.isUploadingAudio,
              size: 38,
              onRecorded: (f, d, p) => widget.onAudioRecorded(f, d, p),
            )
          else
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accent,
              ),
              child: IconButton(
                icon: widget.isSending
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.isDark
                              ? Colors.black
                              : Colors.white,
                        ),
                      )
                    : Icon(HugeIconsSolid.sent,
                        color: colors.isDark
                            ? Colors.black
                            : Colors.white,
                        size: 20),
                onPressed: widget.isSending
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        widget.onSend();
                        setState(() => _hasInputText = false);
                      },
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Locked footer (closed / cancelled tickets)
// ─────────────────────────────────────────────────────────────────────────────
class _LockedFooter extends StatelessWidget {
  final TicketStatus? status;
  final AzamanColors colors;
  const _LockedFooter({required this.status, required this.colors});

  @override
  Widget build(BuildContext context) {
    final label = status == TicketStatus.cancelled
        ? 'This ticket was cancelled. Reopen to post again.'
        : 'This ticket is closed. Reopen to post again.';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      color: colors.surface,
      child: Row(
        children: [
          Icon(HugeIconsSolid.lock,
              color: colors.textTertiary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
