// =============================================================================
// CHAT MONEY CARD  (2026-07-11)
//
// Premium bank-card–style bubble for money sent/requested in P2P chat.
// Mirrors the _CashBalanceCard aesthetic from the P2P screen:
//   • dark carbon-to-black gradient, gold accent, diagonal sheen animation
//   • SENT → shows amount + recipient + reference, download receipt icon
//   • REQUEST (isMe=false, pending) → shows Accept / Decline action buttons
//     embedded in the card, like Add Money / Withdraw on the P2P card
//
// Usage:
//   ChatMoneyCard(
//     amount: 50.0,
//     currency: 'USDC',
//     isMe: true,
//     contactName: 'Kwame',
//     status: 'completed',   // 'completed' | 'pending' | 'failed'
//     isRequest: false,
//     reference: '#TXN-0001',
//     memo: 'For the logo work',
//     timestamp: msg.createdAt,
//     onAccept: () { ... },
//     onDecline: () { ... },
//     onDownloadReceipt: () { ... },
//   )
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ChatMoneyCard extends StatefulWidget {
  final double amount;
  final String currency;

  /// true = I sent / requested; false = I received / was requested
  final bool isMe;
  final String contactName;

  /// 'completed' | 'pending' | 'failed'
  final String status;

  /// true = this is a payment REQUEST (not a send)
  final bool isRequest;

  final String? reference;
  final String? memo;
  final DateTime timestamp;
  final String? skinId;

  /// Called when the non-sender taps Accept on a pending request.
  final VoidCallback? onAccept;

  /// Called when the non-sender taps Decline on a pending request.
  final VoidCallback? onDecline;

  /// Called to export PDF receipt.
  final VoidCallback? onDownloadReceipt;

  const ChatMoneyCard({
    super.key,
    required this.amount,
    required this.currency,
    required this.isMe,
    required this.contactName,
    required this.status,
    this.isRequest = false,
    this.reference,
    this.memo,
    required this.timestamp,
    this.skinId,
    this.onAccept,
    this.onDecline,
    this.onDownloadReceipt,
  });

  @override
  State<ChatMoneyCard> createState() => _ChatMoneyCardState();
}

class _ChatMoneyCardState extends State<ChatMoneyCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheenCtrl;

  // Fixed brand palette — unaffected by app theme switch, same as P2P card.
  static const Color _cardGold = Color(0xFFD4AF37);
  static const Color _gradTop = Color(0xFF0E1116);
  static const Color _gradBottom = Color(0xFF05070A);


  // ── Skins logic ──────────────────────────────────────────────────────────
  List<Color> get _gradColors {
    switch (widget.skinId) {
      case 'gold': return [const Color(0xFFD4AF37), const Color(0xFFF0B90B)];
      case 'midnight': return [const Color(0xFF0F0F1A), const Color(0xFF23233B)];
      case 'emerald': return [const Color(0xFF00B894), const Color(0xFF00CEC9)];
      case 'sunset': return [const Color(0xFFFF6B6B), const Color(0xFFEE5A24)];
      case 'classic':
      default:
        return [
          Color.alphaBlend(_cardGold.withValues(alpha: 0.16), _gradTop),
          _gradBottom,
        ];
    }
  }

  Color get _textColor {
    return widget.skinId == 'gold' ? const Color(0xFF1A1400) : Colors.white;
  }
  
  Color get _accentColor {
    return widget.skinId == 'gold' ? const Color(0xFF1A1400) : _cardGold;
  }

  Widget _applySkinAnimation(Widget child) {
    switch (widget.skinId) {
      case 'gold':
        return child.animate(onPlay: (c) => c.repeat()).shimmer(duration: 2000.ms, color: _textColor.withOpacity(0.3)).blurXY(begin: 0, end: 0.5, duration: 1000.ms).then().blurXY(begin: 0.5, end: 0);
      case 'midnight':
        return child.animate(onPlay: (c) => c.repeat(reverse: true)).tint(color: Colors.blueAccent.withOpacity(0.2), duration: 4000.ms);
      case 'emerald':
        return child.animate(onPlay: (c) => c.repeat()).shimmer(duration: 2500.ms, color: Colors.greenAccent.withOpacity(0.4), angle: math.pi / 2);
      case 'sunset':
        return child.animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(duration: 3000.ms, color: _textColor.withOpacity(0.2), angle: 0);
      case 'classic':
      default:
        // Already uses the AnimatedBuilder sheen inside the stack
        return child;
    }
  }

  @override
  void initState() {
    super.initState();
    _sheenCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _sheenCtrl.dispose();
    super.dispose();
  }

  // ── Status helpers ─────────────────────────────────────────────────────────
  Color get _statusColor => switch (widget.status) {
        'completed' => const Color(0xFF22C55E),
        'pending' => const Color(0xFFF59E0B),
        _ => const Color(0xFFEF4444),
      };

  String get _statusLabel => switch (widget.status) {
        'completed' => 'Completed',
        'pending' => 'Pending',
        _ => 'Failed',
      };

  // Contextual label
  String get _typeLabel {
    if (widget.isRequest) {
      return widget.isMe ? 'Payment Request Sent' : 'Payment Requested';
    }
    return widget.isMe
        ? (widget.contactName.isNotEmpty && widget.contactName != 'Unknown' ? 'Sent to ${widget.contactName}' : 'You sent')
        : (widget.contactName.isNotEmpty && widget.contactName != 'Unknown' ? 'Received from ${widget.contactName}' : 'You received');
  }

  String _fmtAmount(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}M';
    final fmt = NumberFormat('#,##0.00');
    return fmt.format(v);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width * 0.74;
    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: _applySkinAnimation(Stack(
            children: [
              // ── Background gradient ──────────────────────────────────────
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _gradColors,
                    ),
                    border:
                        Border.all(color: _accentColor.withValues(alpha: 0.25), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: _accentColor.withValues(alpha: 0.12),
                        blurRadius: 24,
                        spreadRadius: -6,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                ),
              ),
              // ── Decorative ring (top-right texture) ──────────────────────
              Positioned(
                right: -36,
                top: -44,
                child: IgnorePointer(
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: _accentColor.withValues(alpha: 0.09), width: 20),
                    ),
                  ),
                ),
              ),
              // ── Diagonal sheen animation ─────────────────────────────────
              Positioned.fill(
                child: IgnorePointer(
                  child: _CardSheen(controller: _sheenCtrl, width: width),
                ),
              ),
              // ── Content ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _topRow(),
                    const SizedBox(height: 14),
                    _amountRow(),
                    const SizedBox(height: 6),
                    Text(
                      _typeLabel,
                      style: TextStyle(
                          color: _textColor.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    ),
                    if (widget.memo != null && widget.memo!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _memoBlock(),
                    ],
                    if (widget.reference != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.reference ?? '—',
                        style: TextStyle(
                            color: _textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4),
                      ),
                    ],
                    const SizedBox(height: 14),
                    // Action buttons OR footer
                    _showActionButtons
                        ? _actionButtons()
                        : _footer(),
                  ],
                ),
              ),
            ],
          )),
        ),
      ),
    );
  }

  bool get _showActionButtons =>
      widget.isRequest &&
      !widget.isMe &&
      widget.status == 'pending' &&
      (widget.onAccept != null || widget.onDecline != null);

  Widget _topRow() => Row(
        children: [
          // Chip glyph
          Container(
            width: 28,
            height: 20,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                colors: [
                  _cardGold.withValues(alpha: 0.85),
                  _cardGold.withValues(alpha: 0.45),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.isRequest ? 'Payment Request' : 'AZM Transfer',
            style: TextStyle(
                color: _textColor.withValues(alpha: 0.85),
                fontSize: 12,
                fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: _statusColor.withValues(alpha: 0.5), width: 0.8),
            ),
            child: Text(
              _statusLabel,
              style: TextStyle(
                  color: _statusColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3),
            ),
          ),
        ],
      );

  Widget _amountRow() => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              widget.currency,
              style: TextStyle(
                  color: _textColor.withValues(alpha: 0.65),
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomLeft,
              child: Text(
                _fmtAmount(widget.amount),
                style: TextStyle(
                    color: _textColor,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.0,
                    height: 1.0),
              ),
            ),
          ),
        ],
      );

  Widget _memoBlock() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _textColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '"${widget.memo}"',
          style: TextStyle(
              color: _textColor.withValues(alpha: 0.75),
              fontSize: 11,
              fontStyle: FontStyle.italic),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );

  // ── Footer (non-request, or already resolved request) ─────────────────────
  Widget _footer() => Row(
        children: [
          Text(
            DateFormat('HH:mm').format(widget.timestamp.toLocal()),
            style: TextStyle(
                color: _textColor.withValues(alpha: 0.4),
                fontSize: 10),
          ),
          const SizedBox(width: 6),
          Icon(Icons.shield_outlined,
              color: const Color(0xFF22C55E).withValues(alpha: 0.7), size: 11),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              'Secured by Azaman',
              style: TextStyle(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w600),
            ),
          ),
          if (widget.onDownloadReceipt != null &&
              widget.status == 'completed')
            GestureDetector(
              onTap: widget.onDownloadReceipt,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.download_outlined,
                    color: _accentColor, size: 14),
              ),
            ),
        ],
      );

  // ── Action buttons (Accept / Decline for pending requests) ────────────────
  Widget _actionButtons() => Row(
        children: [
          if (widget.onDecline != null)
            Expanded(
              child: GestureDetector(
                onTap: widget.onDecline,
                child: Container(
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _textColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _textColor.withValues(alpha: 0.2), width: 1),
                  ),
                  child: Text('Accept',
                      style: TextStyle(
                          color: _textColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              ),
            ),
          if (widget.onDecline != null && widget.onAccept != null)
            const SizedBox(width: 10),
          if (widget.onAccept != null)
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: widget.onAccept,
                child: Container(
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _accentColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Accept & Pay',
                      style: TextStyle(
                          color: Color(0xFF0E1116),
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                ),
              ),
            ),
        ],
      );
}

// ── Diagonal sheen sweep (same as P2P card) ───────────────────────────────────
class _CardSheen extends StatelessWidget {
  final AnimationController controller;
  final double width;
  const _CardSheen({required this.controller, required this.width});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          final t = Curves.easeInOutSine.transform(controller.value);
          final dx = -width * 0.7 + t * width * 1.9;
          return Transform.translate(
            offset: Offset(dx, 0),
            child: Transform.rotate(
              angle: -0.4,
              child: Container(
                width: width * 0.28,
                height: width * 2.2,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.transparent,
                      Color(0x0DFFFFFF),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
