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
import 'package:azaman/services/socket_service.dart';

import 'package:azaman/config.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/chat_trust_metrics_provider.dart';
import 'package:azaman/screens/chat_profile_screen.dart';
import 'package:azaman/screens/tickets/ticket_dashboard_screen.dart';
import 'package:azaman/screens/tickets/ticket_workspace_screen.dart';
import 'package:azaman/screens/tickets/ticket_create_sheet.dart';
import 'package:azaman/services/chat_media_service.dart';
import 'package:azaman/services/chat_profile_service.dart';
import 'package:azaman/services/friend_service.dart';
import 'package:azaman/screens/friends/transfer_modal.dart';
import 'package:azaman/widgets/audio_recorder_button.dart';
import 'package:azaman/widgets/chat_media_bubble.dart';
import 'package:azaman/widgets/trust_breakdown_sheet.dart';
import 'package:azaman/providers/premium_chat_provider.dart';
import 'package:azaman/models/chat_message.dart';
import 'package:azaman/widgets/premium_message_bubble.dart';
import 'package:azaman/widgets/premium_chat_input.dart';
import 'package:azaman/widgets/typing_indicator_bubble.dart';
import 'package:azaman/widgets/chat_avatar.dart';
import 'package:azaman/widgets/chat_date_header.dart';


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
  ChatMessage? _replyTo;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FriendService _service = FriendService();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _friendTyping = false;
  String? _friendProfilePic;
  bool _isFriendOnline = false;
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

  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _setupSocketListeners();
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
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        ref.read(premiumChatProvider(ChatContextParams(context: ChatContext.friend, contextId: widget.friendshipId)).notifier).loadMessages(loadMore: true);
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _presenceTimeout?.cancel();
    final socket = SocketService.instance.rawSocket;
    socket?.off('friend_typing');
    socket?.off('ticket_presence_update');
    socket?.off('ticket_status_changed');
    super.dispose();
  }

  // ===========================================================================
  // SOCKET SETUP
  // ===========================================================================

  void _setupSocketListeners() {
    final socket = SocketService.instance.rawSocket;
    if (socket == null) return;

    // Listen for typing indicator
    socket.on('friend_typing', (data) {
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
    socket.on('ticket_presence_update', (data) {
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
    socket.on('ticket_status_changed', (data) {
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
      final friendData = result['friend'] as Map<String, dynamic>?;
      if (friendData != null && mounted) {
        setState(() {
          _friendProfilePic = friendData['profilePictureUrl']?.toString();
          _isFriendOnline = friendData['isOnline'] == true;
        });
      }

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
    SocketService.instance.rawSocket?.emit('typing_friend', {'friendshipId': widget.friendshipId});
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
    final c = ref.watch(themeProvider).colors;
    final params = ChatContextParams(context: ChatContext.friend, contextId: widget.friendshipId);
    final chatState = ref.watch(premiumChatProvider(params));
    final myUserId = int.tryParse(ref.read(authProvider).user?.id?.toString() ?? '0') ?? 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: c.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: _openChatProfile,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              ChatAvatar(
                imageUrl: _friendProfilePic,
                name: widget.friendUsername,
                size: 38,
                showOnlineDot: true,
                isOnline: _isFriendOnline,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ChatHeaderTitle(
                  friendshipId: widget.friendshipId,
                  username: widget.friendUsername,
                  isFriendTyping: _friendTyping || chatState.typingUserIds.isNotEmpty,
                  onTrustTapped: _showTrustBreakdown,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert, color: c.textPrimary),
            onPressed: _openChatProfile,
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner for ticket presence
          if (_ticketPresenceTicketId != null)
            Container(
              color: c.accent.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.visibility, color: c.accent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.friendUsername} is viewing a ticket workspace',
                      style: TextStyle(color: c.accent, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TicketWorkspaceScreen(ticketId: _ticketPresenceTicketId!, friendUsername: widget.friendUsername))),
                    style: TextButton.styleFrom(minimumSize: Size.zero, padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: Text('Join', style: TextStyle(color: c.accent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          
          Expanded(
            child: chatState.isLoading && chatState.messages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: chatState.messages.length + (chatState.hasMore ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i == chatState.messages.length) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    }
                    final msg = chatState.messages[i];
                    final msgDate = msg.createdAt;
                    final prevMsg = i < chatState.messages.length - 1 ? chatState.messages[i + 1] : null;
                    final showDateHeader = prevMsg == null ||
                        msgDate.day != prevMsg.createdAt.day ||
                        msgDate.month != prevMsg.createdAt.month;

                    return Column(children: [
                      if (showDateHeader) ChatDateHeader(date: msgDate),
                      PremiumMessageBubble(
                        key: ValueKey(msg.localId),
                        message: msg,
                        myUserId: myUserId,
                        showAvatar: false,
                        showSenderName: false,
                        onReply: (m) => setState(() => _replyTo = m),
                        onReact: (id, emoji) => ref.read(premiumChatProvider(params).notifier).reactToMessage(id, emoji),
                        onEdit: (m) => _showEditDialog(context, c, m, params),
                        onDelete: (id) => ref.read(premiumChatProvider(params).notifier).deleteMessage(id),
                        onRetry: () => ref.read(premiumChatProvider(params).notifier).retryMessage(msg.localId),
                      )
                    ]);
                  },
                ),
          ),
          
          if (chatState.typingUserIds.isNotEmpty)
            TypingBubble(colors: c),
            
          PremiumChatInput(
            replyTo: _replyTo,
            onClearReply: () => setState(() => _replyTo = null),
            onTransfer: _openTransferModal,
            onTickets: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => TicketCreateSheet(
                  friendshipId: widget.friendshipId,
                ),
              );
            },
            onSendText: (text) {
              ref.read(premiumChatProvider(params).notifier).sendTextMessage(
                text,
                replyToId: _replyTo?.id,
                replyToText: _replyTo?.text,
                replyToSenderName: _replyTo?.senderUsername,
              );
              setState(() => _replyTo = null);
            },
            onSendMedia: ({required mediaUrl, required mediaType, required messageType, mimeType, size, duration, waveformPeaks, linkPreview, caption}) {
              ref.read(premiumChatProvider(params).notifier).sendMediaMessage(
                mediaUrl: mediaUrl, mediaType: mediaType, messageType: messageType, mimeType: mimeType,
                size: size, duration: duration, waveformPeaks: waveformPeaks, linkPreview: linkPreview, caption: caption,
              );
            },
            onTypingChanged: (isTyping) => ref.read(premiumChatProvider(params).notifier).sendTyping(isTyping),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext ctx, AzamanColors c, ChatMessage msg, ChatContextParams params) {
    final editCtrl = TextEditingController(text: msg.text);
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: c.card,
        title: Text('Edit Message', style: TextStyle(color: c.textPrimary, fontSize: 16)),
        content: TextField(
          controller: editCtrl,
          maxLines: null,
          style: TextStyle(color: c.textPrimary),
          decoration: InputDecoration(hintText: 'Edit your message', hintStyle: TextStyle(color: c.textTertiary)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: c.textTertiary))),
          TextButton(
            onPressed: () {
              final newText = editCtrl.text.trim();
              if (newText.isNotEmpty) {
                ref.read(premiumChatProvider(params).notifier).editMessage(msg.id, newText);
              }
              Navigator.pop(ctx);
            },
            child: Text('Save', style: TextStyle(color: c.accent)),
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
