// =============================================================================
// AD DETAIL FLIP CARD — Premium in-place 3D vertical flip
//
// Behaviour (P2P UI Sprint, 2026-05-26):
//   1. The card sits inline in the marketplace feed in its compact "front"
//      form. When the user taps it the marketplace inserts an OverlayEntry
//      that:
//        a) Captures the tapped card's screen rect.
//        b) Renders a frosted BackdropFilter behind the card so the rest
//           of the screen blurs out and the flip card becomes the focal
//           point.
//        c) Animates the card from its origin rect upward toward the
//           middle of the screen and flips it on the X-axis (vertical
//           flip = rotation around the horizontal axis) from front to
//           back face.
//   2. Back face contains the trade form (amount + buyer payment details
//      for SELL ads + Confirm Trade button). The user initiates the trade
//      from the back face directly — no extra modal sheet.
//   3. Swiping DOWN dismisses: the card flips back, animates to its
//      origin rect, and the OverlayEntry is removed.
//
// Why X-axis (vertical flip)?
//   The brief reads "vertical flip" — i.e. the card hinges along its
//   horizontal middle and the top edge rotates toward / away from the
//   viewer. Mathematically this is `Matrix4.rotateX(angle)`.
//
// Underline bug fix:
//   Flutter renders default-style underlines when a Text widget lacks a
//   Material / DefaultTextStyle ancestor. Inside an overlay there is no
//   such ancestor by default, so we wrap the card root in
//   `Material(color: Colors.transparent, child: ...)`.
// =============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/marketplace_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/vendor_badge_row.dart';

/// Public entry point: open the in-place flip overlay.
///
/// `originRect` is the screen-space rect of the source card row (used
/// so the overlay knows where to flip in/out). `onConfirmTrade` is the
/// callback fired when the user submits the trade form on the back
/// face — the marketplace screen handles the actual trade-initiation
/// HTTP call so all the existing trade-flow logic (queueing, errors,
/// etc.) stays in one place.
Future<void> showInPlaceFlipCard({
  required BuildContext context,
  required AdListing ad,
  required Rect originRect,
  required Future<void> Function({
    required double amountFiat,
    required Map<String, String> buyerDetails,
  }) onConfirmTrade,
}) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  final completer = Completer<void>();

  entry = OverlayEntry(
    builder: (_) => _InPlaceFlipOverlay(
      ad: ad,
      originRect: originRect,
      onConfirmTrade: onConfirmTrade,
      onDismissed: () {
        if (entry.mounted) entry.remove();
        if (!completer.isCompleted) completer.complete();
      },
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

// ─────────────────────────────────────────────────────────────────────────────
// The overlay body — owns the open/flip/close animation, the blurred
// backdrop, and the dismiss gesture.
// ─────────────────────────────────────────────────────────────────────────────
class _InPlaceFlipOverlay extends ConsumerStatefulWidget {
  final AdListing ad;
  final Rect originRect;
  final VoidCallback onDismissed;
  final Future<void> Function({
    required double amountFiat,
    required Map<String, String> buyerDetails,
  }) onConfirmTrade;

  const _InPlaceFlipOverlay({
    required this.ad,
    required this.originRect,
    required this.onConfirmTrade,
    required this.onDismissed,
  });

  @override
  ConsumerState<_InPlaceFlipOverlay> createState() =>
      _InPlaceFlipOverlayState();
}

class _InPlaceFlipOverlayState extends ConsumerState<_InPlaceFlipOverlay>
    with TickerProviderStateMixin {
  // One controller drives BOTH the position/scale grow-into-place AND the
  // flip rotation. Splitting them is unnecessary because the user only
  // ever wants the card to be either fully closed or fully open (the
  // intermediate state is the animation itself).
  late final AnimationController _ctrl;
  late final Animation<double> _t; // 0 → 1 over the open animation
  bool _hasLoggedView = false;
  bool _isDismissing = false;
  bool _isSubmitting = false;

  // Dismiss-gesture state
  double _dragDy = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 540),
      reverseDuration: const Duration(milliseconds: 420),
    );
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
    _logInteraction('VIEWED');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _close({bool tradeInitiated = false}) async {
    if (_isDismissing) return;
    _isDismissing = true;
    _logInteraction(tradeInitiated ? 'TRADE_INITIATED' : 'CLOSED');
    HapticFeedback.lightImpact();
    setState(() => _dragDy = 0);
    await _ctrl.reverse();
    if (mounted) widget.onDismissed();
  }

  Future<void> _logInteraction(String type) async {
    try {
      await apiClient.post(
        '/ads/${widget.ad.id}/interaction',
        {'type': type},
      );
    } catch (_) {/* analytics is best-effort */}
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    // Only meaningful once the open animation has completed; while the
    // card is still flying in we ignore drag to avoid weird states.
    if (_ctrl.status != AnimationStatus.completed) return;
    setState(() => _dragDy = (_dragDy + d.delta.dy).clamp(-40.0, 320.0));
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    if (_ctrl.status != AnimationStatus.completed) return;
    final velocity = d.primaryVelocity ?? 0;
    if (_dragDy > 80 || velocity > 600) {
      _close();
    } else {
      setState(() => _dragDy = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final colors = ref.watch(themeProvider).colors;

    // Target rect for the open state — centred horizontally, with a soft
    // top inset so the card sits above the keyboard when the back-face
    // form is active. Width is ~92% of screen, height is generous so
    // the trade form fits without scrolling on most iPhones.
    final targetWidth = size.width * 0.92;
    final targetHeight =
        math.min(size.height * 0.78, 640.0).toDouble();
    final targetTop = math.max(
      MediaQuery.of(context).padding.top + 24,
      (size.height - targetHeight) / 2 - 60,
    );
    final targetLeft = (size.width - targetWidth) / 2;
    final targetRect = Rect.fromLTWH(
      targetLeft,
      targetTop,
      targetWidth,
      targetHeight,
    );

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _t.value;

        // Lerp the rect from origin to target
        final left = ui.lerpDouble(widget.originRect.left, targetRect.left, t)!;
        final top = ui.lerpDouble(widget.originRect.top, targetRect.top, t)!;
        final width =
            ui.lerpDouble(widget.originRect.width, targetRect.width, t)!;
        final height =
            ui.lerpDouble(widget.originRect.height, targetRect.height, t)!;

        // Drag offset on the open card (positive = downward)
        final dragOffset = (_ctrl.status == AnimationStatus.completed
                ? _dragDy
                : 0.0)
            .clamp(0.0, 320.0);
        final dragProgress = (dragOffset / 200).clamp(0.0, 1.0);
        final blurAmount = (24.0 * t * (1 - dragProgress * 0.35)).clamp(0.0, 24.0);
        final scrimAlpha =
            (0.55 * t * (1 - dragProgress * 0.4)).clamp(0.0, 0.55);

        // Flip angle: pi (180°) at full open, 0 closed.
        final flipAngle = math.pi * t;
        final showBack = t > 0.5;

        return Stack(
          fit: StackFit.expand,
          children: [
            // ── 1. Tap-out scrim + blur ────────────────────────────────
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                      sigmaX: blurAmount, sigmaY: blurAmount),
                  child: Container(
                    color: Colors.black.withOpacity(scrimAlpha),
                  ),
                ),
              ),
            ),

            // ── 2. The flipping card ──────────────────────────────────
            Positioned(
              left: left,
              top: top + dragOffset,
              width: width,
              height: height,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateX(flipAngle),
                child: GestureDetector(
                  onVerticalDragUpdate: _onVerticalDragUpdate,
                  onVerticalDragEnd: _onVerticalDragEnd,
                  // Material ancestor wraps both faces — kills the default
                  // text underline that overlay text would otherwise pick
                  // up (the well-known "no Material ancestor" gotcha).
                  child: Material(
                    color: Colors.transparent,
                    child: showBack
                        ? Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()..rotateX(math.pi),
                            child: _BackFace(
                              ad: widget.ad,
                              colors: colors,
                              isSubmitting: _isSubmitting,
                              onConfirm: _onConfirm,
                              onDismiss: _close,
                            ),
                          )
                        : _FrontFace(ad: widget.ad, colors: colors),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Trade submit ────────────────────────────────────────────────────
  Future<void> _onConfirm({
    required double amountFiat,
    required Map<String, String> buyerDetails,
  }) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.onConfirmTrade(
        amountFiat: amountFiat,
        buyerDetails: buyerDetails,
      );
      // Trade-initiated flow handles its own navigation (queue / active
      // trade screen); we just dismiss the overlay.
      await _close(tradeInitiated: true);
    } catch (_) {
      // The marketplace screen surfaces the error in a snackbar; we just
      // unblock the form.
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FRONT FACE — same compact summary as the source row card. The user only
// sees this for ~270ms before the flip rotates them onto the back face.
// ─────────────────────────────────────────────────────────────────────────────
class _FrontFace extends StatelessWidget {
  final AdListing ad;
  final AzamanColors colors;
  const _FrontFace({required this.ad, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.divider),
        boxShadow: [
          BoxShadow(
            color: colors.glow.withOpacity(0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(initial: ad.vendorUsername, colors: colors),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ad.vendorUsername,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${ad.completedTrades} trades · ${(ad.completionRate * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                          color: colors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${ad.paymentMethod}  ·  ${ad.isSellAd ? "SELL" : "BUY"}',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Limit: \$${ad.minLimit.toStringAsFixed(0)} – \$${ad.maxLimit.toStringAsFixed(0)}',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BACK FACE — full ad details + trade form. Submitting fires the
// onConfirmTrade callback the marketplace screen passed in.
// ─────────────────────────────────────────────────────────────────────────────
class _BackFace extends ConsumerStatefulWidget {
  final AdListing ad;
  final AzamanColors colors;
  final bool isSubmitting;
  final Future<void> Function({
    required double amountFiat,
    required Map<String, String> buyerDetails,
  }) onConfirm;
  final VoidCallback onDismiss;

  const _BackFace({
    required this.ad,
    required this.colors,
    required this.isSubmitting,
    required this.onConfirm,
    required this.onDismiss,
  });

  @override
  ConsumerState<_BackFace> createState() => _BackFaceState();
}

class _BackFaceState extends ConsumerState<_BackFace> {
  final _amountCtrl = TextEditingController();
  final Map<String, TextEditingController> _detailCtrls = {};

  // For SELL ads only — buyer must enter their payment endpoint so the
  // vendor can cross-check the inbound transfer.
  bool get _needsBuyerDetails => widget.ad.isSellAd;

  @override
  void dispose() {
    _amountCtrl.dispose();
    for (final c in _detailCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Per-method buyer-detail field schema. Mirrors the validation in
  /// services/tradeAccountValidation on the backend so the FE collects
  /// the exact set the BE will accept. Only the fields the buyer needs
  /// to expose to the vendor (a payment endpoint) — never the full
  /// account schema (e.g. routing number).
  List<_FieldSpec> _buyerFields() {
    switch (widget.ad.paymentMethod.toUpperCase()) {
      case 'CASHAPP':
        return [const _FieldSpec('cashtag', 'Your \$Cashtag', '\$YourTag')];
      case 'ZELLE':
        return [
          const _FieldSpec('email', 'Your Zelle email or phone',
              'name@example.com or +1…'),
        ];
      case 'VENMO':
        return [
          const _FieldSpec('username', 'Your @Venmo username', '@yourname'),
        ];
      case 'PAYPAL':
        return [
          const _FieldSpec(
              'email', 'Your PayPal email', 'name@example.com'),
        ];
      case 'APPLE_PAY':
      case 'APPLE PAY':
        return [
          const _FieldSpec('phone', 'Your Apple Pay number',
              '+1 555 555 5555'),
        ];
      case 'BANK_TRANSFER':
      case 'BANK TRANSFER':
        return [
          const _FieldSpec('bankName', 'Bank name', 'e.g. Chase'),
          const _FieldSpec('accountNumber', 'Account number', '1234567890'),
        ];
      default:
        return [
          const _FieldSpec(
              'identifier', 'Your payment handle', 'username / email / phone'),
        ];
    }
  }

  void _submit() {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      _err('Enter a valid amount');
      return;
    }
    if (amount < widget.ad.minLimit || amount > widget.ad.maxLimit) {
      _err('Amount must be between \$${widget.ad.minLimit.toStringAsFixed(0)} '
          'and \$${widget.ad.maxLimit.toStringAsFixed(0)}');
      return;
    }
    // Buyer details are collected in the active trade screen, not here
    final details = <String, String>{};
    HapticFeedback.heavyImpact();
    widget.onConfirm(amountFiat: amount, buyerDetails: details);
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: widget.colors.danger,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final ad = widget.ad;

    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    // 1 USDC = 1 USD on the global-fiat P2P bridge. The vendor's margin
    // is encoded in the ad's pricePerUSD field and applied server-side
    // at completion; the buyer just sees a 1:1 receipt preview.
    final receiveUsdc = amount;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surface, colors.card],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.accent.withOpacity(0.30)),
        boxShadow: [
          BoxShadow(
            color: colors.accent.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top handle for the swipe-to-dismiss affordance
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Avatar(initial: ad.vendorUsername, colors: colors),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ad.isSellAd ? 'Buy USDC' : 'Sell USDC',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ad.vendorUsername,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${ad.paymentMethod} · ${_getMethodFeeLabel(ad.paymentMethod)} fee',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (ad.vendorId.isNotEmpty)
                  VendorBadgeRow(
                    vendorId: int.tryParse(ad.vendorId) ?? 0,
                    colors: colors,
                  ),
              ],
            ),

            // Vendor stats + risk badge
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.divider),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statChip('${ad.completedTrades}', 'Trades', colors),
                  Container(width: 1, height: 24, color: colors.divider),
                  _statChip('${(ad.completionRate * 100).toStringAsFixed(0)}%', 'Rate', colors),
                  Container(width: 1, height: 24, color: colors.divider),
                  _riskBadge(ad.paymentMethod, colors, context),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Amount input
            Text(
              'Amount (USD)',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.divider),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  prefixText: '\$ ',
                  prefixStyle: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  hintText: '0.00',
                  hintStyle: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Limit \$${ad.minLimit.toStringAsFixed(0)} – \$${ad.maxLimit.toStringAsFixed(0)}',
                  style: TextStyle(color: colors.textTertiary, fontSize: 11),
                ),
                Text(
                  '1 USDC = 1 USD',
                  style: TextStyle(color: colors.textTertiary, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Receipt preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.accent.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Text(
                    'You receive',
                    style: TextStyle(
                        color: colors.textTertiary, fontSize: 11),
                  ),
                  const Spacer(),
                  Text(
                    '${receiveUsdc.toStringAsFixed(2)} USDC',
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),

            // Buyer payment details removed — user provides these in the
            // active trade screen AFTER initiating, not at this stage.

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor:
                      colors.isDark ? Colors.black : Colors.white,
                  disabledBackgroundColor: colors.accent.withOpacity(0.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: widget.isSubmitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.bolt_rounded, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Confirm Trade',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
              ),
            )
                .animate(target: widget.isSubmitting ? 0 : 1)
                .shimmer(
                  delay: 700.ms,
                  duration: 1400.ms,
                  color: Colors.white.withOpacity(0.30),
                ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Swipe down to close',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getMethodFeeLabel(String method) {
    const fees = {
      'ZELLE': '2%', 'CASHAPP': '2%', 'APPLE_PAY': '2.5%', 'APPLE PAY': '2.5%',
      'GOOGLE_PAY': '2.5%', 'GOOGLE PAY': '2.5%', 'VENMO': '2.5%',
      'PAYPAL': '4%', 'WISE': '2%', 'REVOLUT': '2.5%',
      'WESTERN_UNION': '1.5%', 'WESTERN UNION': '1.5%',
      'WIRE_TRANSFER': '1.5%', 'WIRE TRANSFER': '1.5%',
    };
    return fees[method.toUpperCase()] ?? '2%';
  }

  Widget _statChip(String value, String label, AzamanColors colors) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: colors.textTertiary, fontSize: 9, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _riskBadge(String method, AzamanColors colors, BuildContext context) {
    final risk = _getRiskLevel(method);
    final riskColor = risk == 'LOW' ? colors.success : risk == 'HIGH' ? colors.danger : colors.warning;
    final riskLabel = risk == 'LOW' ? 'Low Risk' : risk == 'HIGH' ? 'High Risk' : 'Med Risk';

    return GestureDetector(
      onTap: () => _showRiskExplanation(context, risk, method, colors),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: riskColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: riskColor.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: 10, color: riskColor),
            const SizedBox(width: 4),
            Text(riskLabel, style: TextStyle(color: riskColor, fontSize: 9, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  String _getRiskLevel(String method) {
    const riskMap = {
      'ZELLE': 'LOW', 'CASHAPP': 'LOW', 'WISE': 'LOW',
      'WESTERN_UNION': 'LOW', 'WESTERN UNION': 'LOW',
      'WIRE_TRANSFER': 'LOW', 'WIRE TRANSFER': 'LOW',
      'APPLE_PAY': 'MEDIUM', 'APPLE PAY': 'MEDIUM',
      'GOOGLE_PAY': 'MEDIUM', 'GOOGLE PAY': 'MEDIUM',
      'VENMO': 'MEDIUM', 'REVOLUT': 'MEDIUM',
      'PAYPAL': 'HIGH',
    };
    return riskMap[method.toUpperCase()] ?? 'MEDIUM';
  }

  void _showRiskExplanation(BuildContext context, String risk, String method, AzamanColors colors) {
    final explanations = {
      'LOW': 'This payment method has very low chargeback risk. Transactions are typically irreversible once sent.',
      'MEDIUM': 'This payment method has moderate risk. Disputes are possible but uncommon with verified accounts.',
      'HIGH': 'This payment method has higher chargeback risk. The platform charges a higher fee to offset potential reversals.',
    };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$method Risk Level', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(explanations[risk] ?? '', style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Got it', style: TextStyle(color: colors.accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _FieldSpec {
  final String key;
  final String label;
  final String hint;
  const _FieldSpec(this.key, this.label, this.hint);
}

class _Avatar extends StatelessWidget {
  final String initial;
  final AzamanColors colors;
  const _Avatar({required this.initial, required this.colors});

  @override
  Widget build(BuildContext context) {
    final letter =
        initial.isEmpty ? 'V' : initial.substring(0, 1).toUpperCase();
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.accent.withOpacity(0.15),
        border: Border.all(color: colors.accent.withOpacity(0.30)),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: colors.accent,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
