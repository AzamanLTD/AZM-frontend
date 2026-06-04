// =============================================================================
// TRANSACTION CHAT SCREEN — Azaman Phase 3.3
//
// Premium chat interface for P2P trade execution with:
//   • Draggable floating countdown timer overlay
//   • Ripple extension chips (+15m, +30m) above keyboard
//   • Glassmorphism effects with dark theme
//   • Real-time message updates
//
// Architecture:
//   • Uses Riverpod for state management
//   • Draggable widget for countdown overlay
//   • Live countdown ticker
//   • Premium dark UI with golden accents
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/chat_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'dart:ui';

class TransactionChatScreen extends ConsumerStatefulWidget {
  final String tradeId;
  final String otherUserName;
  final String otherUserId;
  final double tradeAmount;
  final String tradeCurrency;

  const TransactionChatScreen({
    super.key,
    required this.tradeId,
    required this.otherUserName,
    required this.otherUserId,
    required this.tradeAmount,
    required this.tradeCurrency,
  });

  @override
  ConsumerState<TransactionChatScreen> createState() => _TransactionChatScreenState();
}

class _TransactionChatScreenState extends ConsumerState<TransactionChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // Draggable overlay position
  Offset _overlayPosition = const Offset(20, 100);
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _startCountdownTicker();
    _addWelcomeMessage();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startCountdownTicker() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        final chatState = ref.read(transactionChatProvider(widget.tradeId));
        if (chatState.isExpired) {
          _countdownTimer?.cancel();
          ref.read(transactionChatProvider(widget.tradeId).notifier).setExpired();
          _showTimeExpiredDialog();
        }
        setState(() {}); // Force rebuild to update countdown display
      }
    });
  }

  void _addWelcomeMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(transactionChatProvider(widget.tradeId).notifier).addMessage(
            ChatMessage(
              id: 'welcome_${DateTime.now().millisecondsSinceEpoch}',
              senderId: 'system',
              text:
                  'Trade initiated: ${widget.tradeAmount} ${widget.tradeCurrency}\nComplete payment within the time limit.',
              timestamp: DateTime.now(),
              type: MessageType.system,
              isMe: false,
            ),
          );
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.selectionClick();
    ref.read(transactionChatProvider(widget.tradeId).notifier).addMessage(
          ChatMessage(
            id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
            senderId: 'me',
            text: text,
            timestamp: DateTime.now(),
            type: MessageType.text,
            isMe: true,
          ),
        );

    _messageController.clear();
    _scrollToBottom();
  }

  void _requestTimeExtension(int minutes) {
    HapticFeedback.mediumImpact();
    ref.read(transactionChatProvider(widget.tradeId).notifier).requestTimeExtension(minutes);

    // Simulate approval after 2 seconds (in production, this would be a socket event)
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        ref.read(transactionChatProvider(widget.tradeId).notifier).extendTime(minutes);
        HapticFeedback.heavyImpact();
      }
    });

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showTimeExpiredDialog() {
    final colors = ref.read(themeProvider).colors;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.timer_off_rounded, color: colors.danger, size: 28),
            const SizedBox(width: 12),
            Text('Time Expired',
                style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'The transaction timer has expired. Please contact support if payment was completed.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text('Close', style: TextStyle(color: colors.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _formatCountdown(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final chatState = ref.watch(transactionChatProvider(widget.tradeId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherUserName,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Trade: ${widget.tradeAmount} ${widget.tradeCurrency}',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: chatState.isActive ? colors.success.withOpacity(0.15) : colors.danger.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: chatState.isActive ? colors.success : colors.danger,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: chatState.isActive ? colors.success : colors.danger,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  chatState.isActive ? 'ACTIVE' : 'EXPIRED',
                  style: TextStyle(
                    color: chatState.isActive ? colors.success : colors.danger,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main chat interface
          Column(
            children: [
              // Security notice banner
              _buildSecurityBanner(colors),

              // Messages list
              Expanded(
                child: chatState.messages.isEmpty
                    ? _buildEmptyState(colors)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        itemCount: chatState.messages.length,
                        itemBuilder: (context, i) {
                          final msg = chatState.messages[i];
                          return _buildMessageBubble(msg, colors);
                        },
                      ),
              ),

              // Ripple extension chips (above keyboard)
              if (chatState.isActive) _buildRippleExtensions(colors, chatState),

              // Message input field
              _buildInputField(colors, chatState),
            ],
          ),

          // Draggable countdown overlay
          if (chatState.isActive) _buildDraggableCountdown(colors, chatState),
        ],
      ),
    );
  }

  Widget _buildSecurityBanner(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.warning.withOpacity(0.08),
        border: Border(
          bottom: BorderSide(color: colors.warning.withOpacity(0.3), width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: colors.warning, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Keep all communication within Azaman. Never release funds before confirmation.',
              style: TextStyle(
                color: colors.warning,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AzamanColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline_rounded, size: 48, color: colors.textTertiary),
          const SizedBox(height: 12),
          Text(
            'Transaction chat started',
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Send a message to ${widget.otherUserName}',
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, AzamanColors colors) {
    if (msg.type == MessageType.system) {
      return _buildSystemMessage(msg, colors);
    } else if (msg.type == MessageType.timeRequest) {
      return _buildTimeRequestBubble(msg, colors);
    } else if (msg.type == MessageType.timeApproved) {
      return _buildTimeApprovedBubble(msg, colors);
    } else {
      return _buildTextBubble(msg, colors);
    }
  }

  Widget _buildSystemMessage(ChatMessage msg, AzamanColors colors) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.card.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline_rounded, color: colors.accentSecondary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg.text,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRequestBubble(ChatMessage msg, AzamanColors colors) {
    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.warning.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.warning, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.access_time_rounded, color: colors.warning, size: 18),
            const SizedBox(width: 8),
            Text(
              msg.text,
              style: TextStyle(
                color: colors.warning,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeApprovedBubble(ChatMessage msg, AzamanColors colors) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.success.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.success.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline_rounded, color: colors.success, size: 16),
          const SizedBox(width: 8),
          Text(
            msg.text,
            style: TextStyle(
              color: colors.success,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextBubble(ChatMessage msg, AzamanColors colors) {
    final isMe = msg.isMe;
    final bubbleColor = isMe ? colors.glow : colors.card;
    final textColor = isMe ? Colors.black : colors.textPrimary;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: isMe ? colors.glow.withOpacity(0.2) : Colors.black26,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              msg.text,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(msg.timestamp),
              style: TextStyle(
                color: isMe ? Colors.black54 : colors.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRippleExtensions(AzamanColors colors, TransactionChatState chatState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface.withOpacity(0.95),
        border: Border(
          top: BorderSide(color: colors.divider.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, color: colors.accentSecondary, size: 20),
          const SizedBox(width: 10),
          Text(
            'Request more time:',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          _buildRippleChip('+15m', 15, colors),
          const SizedBox(width: 8),
          _buildRippleChip('+30m', 30, colors),
        ],
      ),
    );
  }

  Widget _buildRippleChip(String label, int minutes, AzamanColors colors) {
    return GestureDetector(
      onTap: () => _requestTimeExtension(minutes),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colors.accentSecondary.withOpacity(0.2),
              colors.accentSecondary.withOpacity(0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.accentSecondary.withOpacity(0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: colors.accentSecondary.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: colors.accentSecondary,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildInputField(AzamanColors colors, TransactionChatState chatState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.divider),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.divider),
              ),
              child: TextField(
                controller: _messageController,
                enabled: chatState.isActive,
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: chatState.isActive ? 'Type a message...' : 'Chat expired',
                  hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: chatState.isActive ? _sendMessage : null,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: chatState.isActive
                    ? LinearGradient(
                        colors: [colors.glow, colors.glow.withOpacity(0.8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: chatState.isActive ? null : colors.card,
                shape: BoxShape.circle,
                boxShadow: chatState.isActive
                    ? [
                        BoxShadow(
                          color: colors.glow.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                Icons.send_rounded,
                color: chatState.isActive ? Colors.black : colors.textTertiary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraggableCountdown(AzamanColors colors, TransactionChatState chatState) {
    final remainingTime = chatState.remainingTime;
    final isLowTime = remainingTime.inMinutes < 5;

    return Positioned(
      left: _overlayPosition.dx,
      top: _overlayPosition.dy,
      child: Draggable(
        feedback: _countdownWidget(colors, remainingTime, isLowTime, isDragging: true),
        childWhenDragging: Container(),
        onDragEnd: (details) {
          setState(() {
            _overlayPosition = details.offset;
          });
        },
        child: _countdownWidget(colors, remainingTime, isLowTime),
      ),
    );
  }

  Widget _countdownWidget(AzamanColors colors, Duration remainingTime, bool isLowTime,
      {bool isDragging = false}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isLowTime
                  ? [
                      colors.danger.withOpacity(0.25),
                      colors.danger.withOpacity(0.15),
                    ]
                  : [
                      colors.card.withOpacity(0.7),
                      colors.card.withOpacity(0.5),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isLowTime
                  ? colors.danger.withOpacity(0.6)
                  : colors.glow.withOpacity(0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: isLowTime
                    ? colors.danger.withOpacity(0.3)
                    : colors.glow.withOpacity(0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isLowTime ? Icons.warning_amber_rounded : Icons.timer_outlined,
                    color: isLowTime ? colors.danger : colors.glow,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatCountdown(remainingTime),
                    style: TextStyle(
                      color: isLowTime ? colors.danger : colors.glow,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                isLowTime ? 'TIME RUNNING OUT!' : 'Remaining',
                style: TextStyle(
                  color: isLowTime ? colors.danger : colors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
