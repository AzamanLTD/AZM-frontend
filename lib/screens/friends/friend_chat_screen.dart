// =============================================================================
// AZAMAN V3 — FRIEND CHAT SCREEN
//
// Real-time messaging with a friend. Supports text messages and special
// transfer message types (sent, request, completed, declined).
// Socket integration for live messaging and typing indicators.
// =============================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'package:azaman/config.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/chat_trust_metrics_provider.dart';
import 'package:azaman/screens/chat_profile_screen.dart';
import 'package:azaman/screens/tickets/ticket_dashboard_screen.dart';
import 'package:azaman/screens/tickets/ticket_workspace_screen.dart';
import 'package:azaman/services/chat_media_service.dart';
import 'package:azaman/services/chat_profile_service.dart';
import 'package:azaman/services/friend_service.dart';
import 'package:azaman/screens/friends/transfer_modal.dart';
import 'package:azaman/widgets/audio_recorder_button.dart';
import 'package:azaman/widgets/chat_media_bubble.dart';
import 'package:azaman/widgets/trust_breakdown_sheet.dart';


class FriendChatScreen extends ConsumerStatefulWidget {
  final String friendshipId;
  final String friendUsername;
  final int friendId;

  const FriendChatScreen({
    super.key,
    required this.friendshipId,
    required this.friendUsername,
    required this.friendId,
  });

  @override
  ConsumerState<FriendChatScreen> createState() => _FriendChatScreenState();
}

class _FriendChatScreenState extends ConsumerState<FriendChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FriendService _service = FriendService();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _friendTyping = false;
  // Phase UI-POLISH (2026-05-26): tracks whether the text field is empty
  // so we can swap between the audio recorder mic and the text-send arrow.
  bool _hasInputText = false;
  // Phase UI-POLISH: while a voice note is uploading we lock the input so
  // a second hold can't kick off a parallel upload.
  bool _isUploadingAudio = false;
  int _currentPage = 1;
  bool _hasMore = true;

  // Phase UI-4 (2026-05-26): Tickets Engine — counterparty presence banner.
  // When the friend opens any ticket workspace under this friendship, the
  // server emits `ticket_presence_update` with `viewing: true`. We render
  // a soft banner above the input bar; cleared on `viewing: false` or
  // after a 60-second idle timeout.
  String? _ticketPresenceTicketId;
  Timer? _presenceTimeout;

  IO.Socket? _socket;
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _setupSocket();
    _markAsRead();

    // Phase UI-6 (2026-05-27): prime the persistent trust-metric line
    // under the friend's name in the AppBar. Cheap call (two parallel
    // COUNTs server-side); we trigger it post-frame so it doesn't
    // contend with the initial message-list paint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(chatTrustMetricsProvider(widget.friendshipId).notifier)
          .primeIfNeeded();
    });

    // Listen for scroll to load more
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _presenceTimeout?.cancel();
    _socket?.emit('leave_friend_chat', {'friendshipId': widget.friendshipId});
    _socket?.off('friend_message');
    _socket?.off('friend_typing');
    _socket?.off('ticket_presence_update');
    _socket?.off('ticket_status_changed');
    super.dispose();
  }

  // ===========================================================================
  // SOCKET SETUP
  // ===========================================================================

  void _setupSocket() {
    final token = ref.read(authProvider).user?.token;
    if (token == null) return;

    _socket = IO.io(
      AppConfig.socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );

    _socket!.connect();

    // Join the friend chat room
    _socket!.emit('join_friend_chat', {'friendshipId': widget.friendshipId});

    // Listen for incoming messages
    _socket!.on('friend_message', (data) {
      if (data is Map<String, dynamic> &&
          data['friendshipId']?.toString() == widget.friendshipId) {
        // Phase 4.1 (Susu Sprint, 2026-05-31): only auto-scroll to bottom
        // when the user is already within 50 logical pixels of it. If
        // they're scrolled up reading older history, we preserve their
        // position so the incoming message doesn't yank them away
        // (Req 1.3 / 1.4). The ListView is reverse:true so "bottom" is
        // pixels == 0 from the controller's perspective.
        final wasNearBottom = _isNearBottom();

        // De-dupe: if this echo matches an optimistic placeholder we
        // inserted in _sendMessage, swap the placeholder for the real
        // server row rather than rendering the same content twice.
        final clientNonce =
            (data['clientNonce'] ?? data['metadata']?['clientNonce'])?.toString();
        bool replaced = false;
        if (clientNonce != null) {
          final idx = _messages.indexWhere(
              (m) => m['clientNonce']?.toString() == clientNonce);
          if (idx != -1) {
            _messages[idx] = data;
            replaced = true;
          }
        }

        setState(() {
          if (!replaced) _messages.insert(0, data);
          _friendTyping = false;
        });

        if (wasNearBottom) _scrollToBottom();
        _markAsRead();

        // Phase UI-6: a TRANSFER_COMPLETED message means a PeerTransfer
        // was just fulfilled — bump the trust counter without waiting
        // for the next chat open. Cheap call (the BE endpoint is two
        // counts and one row), so we don't worry about debouncing.
        final type = (data['type'] ?? data['messageType'] ?? '')
            .toString()
            .toUpperCase();
        if (type == 'TRANSFER_COMPLETED') {
          ref
              .read(chatTrustMetricsProvider(widget.friendshipId).notifier)
              .refresh();
        }
      }
    });

    // Listen for typing indicator
    _socket!.on('friend_typing', (data) {
      if (data is Map<String, dynamic> &&
          data['friendshipId']?.toString() == widget.friendshipId) {
        setState(() => _friendTyping = true);
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _friendTyping = false);
        });
      }
    });

    // Phase UI-4: Tickets Engine presence updates. Fired when the
    // counterparty opens or closes any ticket workspace under this
    // friendship. We only react if the event is scoped to OUR friendship
    // and the user reported is NOT us (we shouldn't see our own banner).
    final myUserId = ref.read(authProvider).user?.id;
    _socket!.on('ticket_presence_update', (data) {
      if (!mounted) return;
      if (data is! Map<String, dynamic>) return;
      if (data['friendshipId']?.toString() != widget.friendshipId) return;
      final eventUserId = data['userId'];
      final viewing = data['viewing'] == true;
      if (myUserId != null && eventUserId == myUserId) return; // self-event
      setState(() {
        _ticketPresenceTicketId = viewing
            ? (data['ticketId']?.toString() ?? 'unknown')
            : null;
      });
      _presenceTimeout?.cancel();
      if (viewing) {
        // Auto-clear after 60s in case we miss the matching `viewing: false`
        // (background flips, dropped connection, etc.)
        _presenceTimeout = Timer(const Duration(seconds: 60), () {
          if (mounted) setState(() => _ticketPresenceTicketId = null);
        });
      }
    });

    // Phase UI-6: refresh trust metrics whenever a ticket lifecycle
    // transition lands. CLOSED is the only one that bumps the count, but
    // a CANCELLED → REOPENED → CLOSED cycle is legal and we don't want
    // to maintain that bookkeeping client-side. One refresh per status
    // change is cheap and always correct.
    _socket!.on('ticket_status_changed', (data) {
      if (!mounted) return;
      if (data is! Map<String, dynamic>) return;
      if (data['friendshipId']?.toString() != widget.friendshipId) return;
      ref
          .read(chatTrustMetricsProvider(widget.friendshipId).notifier)
          .refresh();
    });
  }

  // ===========================================================================
  // DATA LOADING
  // ===========================================================================

  Future<void> _loadMessages({bool loadMore = false}) async {
    final token = ref.read(authProvider).user?.token;
    if (token == null) return;

    if (loadMore) {
      _currentPage++;
    } else {
      _currentPage = 1;
    }

    try {
      final result = await _service.getMessages(
        widget.friendshipId,
        token,
        page: _currentPage,
      );

      final msgs = List<Map<String, dynamic>>.from(result['messages'] ?? []);

      setState(() {
        if (loadMore) {
          _messages.addAll(msgs);
        } else {
          _messages = msgs;
        }
        _hasMore = result['hasMore'] ?? false;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('FriendChat._loadMessages error: $e');
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 100 &&
        _hasMore &&
        !_isLoading) {
      _loadMessages(loadMore: true);
    }
  }

  // Phase 4.1 (Susu Sprint, 2026-05-31) — Req 1.3 / 1.4: in a reverse:true
  // ListView, the BOTTOM of the visible area is `pixels == 0` from the
  // controller's perspective. We're "near the bottom" iff the user's
  // current scroll offset is within 50 logical pixels of that.
  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels <= 50.0;
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    // jumpTo (not animateTo) so the local-send bubble lands within the
    // 100 ms SLA (Req 1.5). For inbound socket messages the same call
    // is fine — we're already at offset 0 in 99% of cases.
    _scrollController.jumpTo(0);
  }

  Future<void> _markAsRead() async {
    final token = ref.read(authProvider).user?.token;
    if (token == null) return;
    await _service.markAsRead(widget.friendshipId, token);
    // Refresh unread count in provider
    ref.read(friendProvider).fetchUnreadCount();
  }

  // ===========================================================================
  // SENDING MESSAGES
  // ===========================================================================

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    final token = ref.read(authProvider).user?.token;
    if (token == null) return;

    _messageController.clear();

    // Phase 4.1 (Susu Sprint, 2026-05-31) — Req 1.5: the sent bubble
    // must appear at the bottom of the visible area within 100 ms of
    // the send action. We insert an optimistic placeholder immediately
    // (synchronous setState), pin the viewport to the bottom, and let
    // the network call complete in the background. When the server's
    // `friend_message` echo arrives, the echo's `clientNonce` matches
    // the placeholder and the inbound handler swaps the row in place
    // rather than duplicating it.
    final myUserId = ref.read(authProvider).user?.id;
    final clientNonce =
        '${DateTime.now().microsecondsSinceEpoch}-${text.hashCode}';
    final optimistic = <String, dynamic>{
      'clientNonce': clientNonce,
      'content': text,
      'senderId': myUserId,
      'createdAt': DateTime.now().toIso8601String(),
      'type': 'TEXT',
      'friendshipId': widget.friendshipId,
      '_pending': true,
    };

    setState(() {
      _messages.insert(0, optimistic);
      _hasInputText = false;
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final result = await _service.sendMessage(
        widget.friendshipId,
        text,
        token,
      );

      // Swap optimistic row for the server-canonical record, preserving
      // chat order. If the echo already arrived via socket and replaced
      // the placeholder, the indexWhere returns -1 and we no-op.
      final serverMsg = result['message'];
      if (serverMsg is Map<String, dynamic>) {
        final idx = _messages
            .indexWhere((m) => m['clientNonce']?.toString() == clientNonce);
        if (idx != -1 && mounted) {
          // Carry the nonce through so a subsequent socket echo can
          // de-dupe against this row (the BE doesn't always echo back
          // to the sender, but if it does, this prevents a duplicate).
          setState(() => _messages[idx] = {
                ...serverMsg,
                'clientNonce': clientNonce,
              });
        }
      }
    } catch (e) {
      debugPrint('FriendChat._sendMessage error: $e');
      // Mark the optimistic row as failed instead of removing it — the
      // user keeps the visual breadcrumb, the bubble's _pending flag
      // tracks the failure, and a retry path can re-attempt later.
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere(
              (m) => m['clientNonce']?.toString() == clientNonce);
          if (idx != -1) {
            _messages[idx] = {
              ..._messages[idx],
              '_failed': true,
              '_pending': false,
            };
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _emitTyping() {
    _socket?.emit('typing_friend', {'friendshipId': widget.friendshipId});
  }

  // ===========================================================================
  // TRANSFER ACTIONS
  // ===========================================================================

  void _openTransferModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TransferModal(
        friendshipId: widget.friendshipId,
        friendUsername: widget.friendUsername,
      ),
    ).then((result) {
      if (result == true) {
        // Refresh messages to show the transfer
        _loadMessages();
        ref.read(friendProvider).fetchFriends();
      }
    });
  }

  // ===========================================================================
  // TICKETS (Phase UI-4)
  // ===========================================================================

  void _openTicketDashboard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TicketDashboardScreen(
          friendshipId: widget.friendshipId,
          friendUsername: widget.friendUsername,
        ),
      ),
    ).then((_) {
      // Refresh messages so any new TICKET_LINK event cards appear in
      // the parent chat feed.
      _loadMessages();
    });
  }

  void _openTicket(String ticketId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TicketWorkspaceScreen(
          ticketId: ticketId,
          friendUsername: widget.friendUsername,
        ),
      ),
    );
  }

  // ===========================================================================
  // CHAT PROFILE + VAULT (Phase UI-5)
  // ===========================================================================

  void _openChatProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatProfileScreen(
          friendshipId: widget.friendshipId,
          fallbackUsername: widget.friendUsername,
        ),
      ),
    );
  }

  // ===========================================================================
  // TRUST BREAKDOWN POPUP (Phase UI-7)
  // ===========================================================================

  void _showTrustBreakdown() {
    final state = ref.read(chatTrustMetricsProvider(widget.friendshipId));
    final metrics = state.metrics;
    if (metrics == null) {
      // Metrics haven't landed yet — fall through to the full profile
      // screen rather than show an empty sheet. Cheap fallback that
      // preserves the user's intent ("show me reputation detail").
      _openChatProfile();
      return;
    }
    showTrustBreakdownSheet(
      context,
      username: widget.friendUsername,
      breakdown: metrics.breakdown,
      rating: metrics.rating,
      positiveReviews: metrics.positiveReviews,
      negativeReviews: metrics.negativeReviews,
      isVerifiedVendor: metrics.isVerifiedVendor,
    );
  }

  Future<void> _fulfillTransfer(String transferId) async {
    final token = ref.read(authProvider).user?.token;
    if (token == null) return;

    try {
      await _service.fulfillTransfer(transferId, token);
      _loadMessages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transfer fulfilled successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fulfill transfer: $e')),
        );
      }
    }
  }

  Future<void> _declineTransfer(String transferId) async {
    final token = ref.read(authProvider).user?.token;
    if (token == null) return;

    try {
      await _service.declineTransfer(transferId, token);
      _loadMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to decline transfer: $e')),
        );
      }
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final myUserId = ref.read(authProvider).user?.id;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          // Phase UI-5 (2026-05-26): tapping the title row (avatar +
          // name) routes to the upgraded ChatProfileScreen with the
          // identity tier + tabbed Media / Docs & Links / Tickets /
          // Receipts vault.
          onTap: _openChatProfile,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: colors.accent.withOpacity(0.2),
                child: Text(
                  widget.friendUsername.isNotEmpty
                      ? widget.friendUsername[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: colors.accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Phase UI-6: stack the username, a persistent trust line
              // (⭐ rating · N Completed Transactions), and the verified
              // vendor checkmark when applicable. Typing indicator
              // briefly replaces the trust line while the friend is
              // typing — a transient overlay rather than the only
              // subtitle the row ever shows.
              //
              // Phase UI-7: tap the trust line to open the breakdown
              // sheet (P2P / Transfers / Tickets). Tapping the username
              // (or anywhere outside the trust line) still routes to
              // the full Chat Profile screen via the GestureDetector
              // above this Row.
              Expanded(
                child: _ChatHeaderTitle(
                  friendshipId: widget.friendshipId,
                  username: widget.friendUsername,
                  isFriendTyping: _friendTyping,
                  onTrustTapped: _showTrustBreakdown,
                ),
              ),
            ],
          ),
        ),
        actions: [
          // Phase UI-4 (2026-05-26): the legacy `swap_horiz_rounded`
          // "Transfer" icon was REPLACED by the Ticket button. Send-money
          // is still reachable in-chat via the input bar's `+` Send funds
          // button (`_buildInputBar` below).
          IconButton(
            icon: Icon(Icons.confirmation_number_outlined, color: colors.accent),
            tooltip: 'Tickets',
            onPressed: _openTicketDashboard,
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: colors.accent))
                : _messages.isEmpty
                    ? _buildEmptyState(colors)
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe =
                              msg['senderId']?.toString() == myUserId?.toString();
                          final type = (msg['type'] ?? msg['messageType'] ?? 'TEXT').toString().toUpperCase();

                          if (type == 'TICKET_LINK') {
                            return _buildTicketLinkBubble(msg, isMe, colors);
                          }
                          if (type.contains('TRANSFER')) {
                            return _buildTransferBubble(msg, type, isMe, colors);
                          }
                          // Phase UI-3 + UI-POLISH: route IMAGE / VIDEO /
                          // DOCUMENT / AUDIO / LINK messages through the
                          // shared `ChatMediaBubble` so they render with
                          // inline players, OG cards, doc icons, etc.
                          if (const {
                            'IMAGE', 'VIDEO', 'AUDIO', 'DOCUMENT', 'LINK'
                          }.contains(type)) {
                            final payload =
                                ChatMediaPayload.fromMessageJson(msg);
                            return Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4),
                                child: ChatMediaBubble(
                                    payload: payload, isMe: isMe),
                              ),
                            );
                          }
                          return _buildMessageBubble(msg, isMe, colors);
                        },
                      ),
          ),

          // Phase UI-4: Tickets Engine presence banner. Renders when the
          // counterparty is currently viewing any ticket workspace under
          // this friendship.
          if (_ticketPresenceTicketId != null)
            _buildTicketPresenceBanner(colors),

          // Input bar
          _buildInputBar(colors),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AzamanColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 48, color: colors.textTertiary),
          const SizedBox(height: 12),
          Text(
            'Start a conversation',
            style: TextStyle(color: colors.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Say hello to ${widget.friendUsername}!',
            style: TextStyle(color: colors.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // MESSAGE BUBBLES
  // ===========================================================================

  Widget _buildMessageBubble(
      Map<String, dynamic> msg, bool isMe, AzamanColors colors) {
    final content = msg['content'] ?? msg['message'] ?? '';
    final time = _formatTime(msg['createdAt']);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? colors.accent.withOpacity(0.15) : colors.card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: isMe
              ? Border.all(color: colors.accent.withOpacity(0.3))
              : null,
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              content,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(color: colors.textTertiary, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferBubble(
      Map<String, dynamic> msg, String type, bool isMe, AzamanColors colors) {
    Color cardColor;
    IconData icon;
    String title;
    String subtitle;
    bool showActions = false;

    final amount = msg['amount'] ?? msg['metadata']?['amount'] ?? 0;
    final reference = msg['reference'] ?? msg['metadata']?['reference'] ?? '';
    final transferId = msg['transferId']?.toString() ??
        msg['metadata']?['transferId']?.toString() ??
        '';

    switch (type) {
      case 'TRANSFER_SENT':
        cardColor = colors.success;
        icon = Icons.arrow_upward;
        title = isMe ? 'You sent AZM $amount' : 'Received AZM $amount';
        subtitle = reference.isNotEmpty ? reference : 'Direct transfer';
        break;
      case 'TRANSFER_REQUEST':
        cardColor = colors.warning;
        icon = Icons.note_outlined;
        title = isMe
            ? 'You requested AZM $amount'
            : 'Requesting AZM $amount';
        subtitle = reference.isNotEmpty ? reference : 'Fund request';
        showActions = !isMe; // Show fulfill/decline for the recipient
        break;
      case 'TRANSFER_COMPLETED':
        cardColor = colors.success;
        icon = Icons.check_circle_outline;
        title = 'Transfer completed — AZM $amount';
        subtitle = 'Successfully fulfilled';
        break;
      case 'TRANSFER_DECLINED':
        cardColor = colors.textTertiary;
        icon = Icons.cancel_outlined;
        title = 'Transfer declined — AZM $amount';
        subtitle = 'Request was declined';
        break;
      default:
        cardColor = colors.accent;
        icon = Icons.swap_horiz;
        title = 'Transfer — AZM $amount';
        subtitle = reference;
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardColor.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: cardColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ],
            if (showActions && transferId.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _fulfillTransfer(transferId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Pay', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _declineTransfer(transferId),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.danger,
                        side: BorderSide(color: colors.danger.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child:
                          const Text('Decline', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                _formatTime(msg['createdAt']),
                style: TextStyle(color: colors.textTertiary, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TICKET LINK + PRESENCE BANNER (Phase UI-4)
  // ===========================================================================

  Widget _buildTicketLinkBubble(
      Map<String, dynamic> msg, bool isMe, AzamanColors colors) {
    final metadata = msg['metadata'] is Map<String, dynamic>
        ? msg['metadata'] as Map<String, dynamic>
        : <String, dynamic>{};
    final ticketId = metadata['ticketId']?.toString();
    final ticketName = metadata['ticketName']?.toString() ?? 'Ticket';
    final ticketType = metadata['ticketType']?.toString() ?? 'BUY';
    final ticketStatus =
        (metadata['ticketStatus'] ?? 'OPEN').toString().toUpperCase();
    final eventType =
        (metadata['eventType'] ?? 'CREATED').toString().toUpperCase();
    final amount = metadata['targetAmount']?.toString();
    final currency = metadata['targetCurrency']?.toString() ?? '';

    Color borderColor;
    String headline;
    switch (eventType) {
      case 'CLOSED':
        borderColor = colors.success;
        headline = 'Ticket closed';
        break;
      case 'CANCELLED':
        borderColor = colors.danger;
        headline = 'Ticket cancelled';
        break;
      case 'REOPENED':
        borderColor = colors.warning;
        headline = 'Ticket reopened';
        break;
      default:
        borderColor = colors.accent;
        headline = 'New ticket';
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: ticketId == null ? null : () => _openTicket(ticketId),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: borderColor.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor.withOpacity(0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.confirmation_number_outlined,
                      color: borderColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    headline.toUpperCase(),
                    style: TextStyle(
                      color: borderColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                ticketName,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$ticketType · ${amount ?? ''} $currency · $ticketStatus',
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Open ticket',
                    style: TextStyle(
                      color: borderColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward,
                      color: borderColor, size: 12),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTicketPresenceBanner(AzamanColors colors) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.accent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.confirmation_number_outlined,
              color: colors.accent, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${widget.friendUsername} is currently viewing the ticket window.',
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

  // ===========================================================================
  // VOICE NOTES (Phase UI-POLISH)
  // ===========================================================================

  /// Called by `AudioRecorderButton` when the user releases a successful
  /// recording. Uploads the file via `ChatMediaService.uploadAudio()`
  /// then sends an AUDIO-typed message via the existing friend-chat
  /// REST endpoint. Errors surface as a snackbar; local optimistic
  /// state is cleared regardless.
  Future<void> _onAudioRecorded(
    File file,
    int durationSeconds,
    List<int> waveformPeaks,
  ) async {
    final colors = ref.read(themeProvider).colors;
    final token = ref.read(authProvider).user?.token;
    if (token == null) return;
    setState(() => _isUploadingAudio = true);
    try {
      final uploaded = await ChatMediaService.instance.uploadAudio(
        file,
        durationSeconds: durationSeconds,
        waveformPeaks: waveformPeaks,
      );
      // Reuse the existing friend-chat send endpoint with media fields.
      // The BE persists every media column for AUDIO type and broadcasts
      // through the same `friend_message` socket channel.
      await _service.sendMessage(
        widget.friendshipId,
        '',
        token,
        messageType: 'AUDIO',
        mediaUrl: uploaded.url,
        mediaType: 'audio',
        mediaMimeType: uploaded.mimeType,
        mediaSize: uploaded.size,
        mediaDuration: uploaded.duration ?? durationSeconds,
        mediaWaveformPeaks: uploaded.waveformPeaks ?? waveformPeaks,
      );
      _loadMessages(); // pick up the new bubble + the server-emitted echo
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Voice note failed: $e'),
          backgroundColor: colors.danger,
        ));
      }
    } finally {
      // Local recording file is in temp dir — leave it for the OS to
      // garbage-collect; deleting now risks racing the upload's
      // streamed read on slower phones.
      if (mounted) setState(() => _isUploadingAudio = false);
    }
  }

  // ===========================================================================
  // INPUT BAR
  // ===========================================================================

  Widget _buildInputBar(AzamanColors colors) {
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
          // Transfer button
          IconButton(
            icon: Icon(Icons.attach_money, color: colors.accent),
            onPressed: _openTransferModal,
            tooltip: 'Send/Request funds',
          ),

          // Text field
          Expanded(
            child: TextField(
              controller: _messageController,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              maxLines: 4,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (text) {
                _emitTyping();
                final isEmpty = text.trim().isEmpty;
                if (_hasInputText == !isEmpty) return;
                setState(() => _hasInputText = !isEmpty);
              },
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(color: colors.textTertiary),
                filled: true,
                fillColor: colors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Phase UI-POLISH (2026-05-26): when the text field is empty we
          // surface the hold-to-record audio button INSTEAD of the send
          // arrow (WhatsApp / iMessage parity). When the user starts
          // typing, the send arrow re-appears.
          if (!_hasInputText && !_isSending)
            AudioRecorderButton(
              disabled: _isUploadingAudio,
              size: 38,
              onRecorded: _onAudioRecorded,
            )
          else
            // Send button
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accent,
              ),
              child: IconButton(
                icon: _isSending
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.isDark ? Colors.black : Colors.white,
                        ),
                      )
                    : Icon(
                        Icons.send_outlined,
                        color: colors.isDark ? Colors.black : Colors.white,
                        size: 20,
                      ),
                onPressed: _isSending ? null : _sendMessage,
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp.toString()).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) return 'now';
      if (diff.inHours < 1) return '${diff.inMinutes}m';
      if (diff.inDays < 1) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      if (diff.inDays < 7) return '${diff.inDays}d';
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }
}

// =============================================================================
// CHAT HEADER TITLE — Phase UI-6 (2026-05-27)
//
// AppBar title block: avatar (in caller) + username + persistent trust-metric
// subtitle. Renders as:
//
//   <username>                                    (verified ✓ — vendors only)
//   ⭐ 4.9 · 120 Completed Transactions
//
// Behaviour:
//   • The trust line is the DEFAULT subtitle. It persists for as long as the
//     screen is mounted.
//   • When the friend is currently typing, the subtitle is replaced by an
//     animated "typing..." line. The trust line returns the moment the
//     typing indicator clears.
//   • If the friend has zero reviews, the rating + star are suppressed and
//     only the count line is rendered ("120 Completed Transactions"). A
//     brand-new account showing a 0.0-star rating would be misleading.
//   • The verified ✓ trailing icon is shown only for users with role=VENDOR
//     and kycStatus=VERIFIED.
//
// While the metric is loading on first paint, we render a neutral placeholder
// ("…") rather than collapsing the row — keeping the header height stable
// avoids a jarring shift when the data arrives.
// =============================================================================
class _ChatHeaderTitle extends ConsumerWidget {
  final String friendshipId;
  final String username;
  final bool isFriendTyping;
  final VoidCallback? onTrustTapped;

  const _ChatHeaderTitle({
    required this.friendshipId,
    required this.username,
    required this.isFriendTyping,
    this.onTrustTapped,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(chatTrustMetricsProvider(friendshipId));
    final metrics = state.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (metrics?.isVerifiedVendor == true) ...[
              const SizedBox(width: 5),
              Tooltip(
                message: 'Verified vendor',
                child: Icon(
                  Icons.check_circle_outline,
                  color: colors.accent,
                  size: 14,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 1),
        // Phase UI-7: trust line is tappable when onTrustTapped is set.
        // We consume the tap with HitTestBehavior.opaque so it doesn't
        // bubble up to the AppBar title's parent GestureDetector (which
        // routes to the full Chat Profile vault screen).
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTrustTapped,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: isFriendTyping
                ? Text(
                    'typing…',
                    key: const ValueKey('typing'),
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                : _buildTrustLine(state, metrics, colors),
          ),
        ),
      ],
    );
  }

  Widget _buildTrustLine(
    ChatTrustMetricsState state,
    ChatTrustMetrics? metrics,
    AzamanColors colors,
  ) {
    // First-load placeholder — keeps the row height stable so the AppBar
    // doesn't bounce vertically when the data lands.
    if (metrics == null) {
      return Text(
        state.error != null ? '—' : 'Loading reputation…',
        key: ValueKey('placeholder-${state.error != null}'),
        style: TextStyle(
          color: colors.textTertiary,
          fontSize: 11,
        ),
      );
    }

    final children = <Widget>[];

    if (metrics.rating != null) {
      children.addAll([
        Icon(Icons.star_outline, color: colors.warning, size: 12),
        const SizedBox(width: 2),
        Text(
          metrics.rating!.toStringAsFixed(1),
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 2,
          height: 2,
          decoration: BoxDecoration(
            color: colors.textTertiary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
      ]);
    }

    final count = metrics.completedTransactions;
    final countLabel = count == 1
        ? '1 Completed Transaction'
        : '$count Completed Transactions';

    children.add(
      Flexible(
        child: Text(
          countLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );

    return Row(
      key: const ValueKey('trust-line'),
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
