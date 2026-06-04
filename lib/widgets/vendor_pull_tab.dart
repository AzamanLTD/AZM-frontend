// =============================================================================
// VENDOR PULL TAB — Floating side tag (left edge)
//
// Behaviour by role:
//   * Vendor       → tab reads "FOR VENDOR", drag-past-50% opens VendorDashboard
//   * Non-vendor   → 3-pull confirmation flow:
//       Pull 1: Snap back + info popup ("You're not a vendor")
//       Pull 2: Snap back + confirmation prompt ("Pull again to start")
//       Pull 3: Opens VendorApplyScreen (within timeout window)
//       Timeout: If >5s between pulls, resets to pull 1
//
// Visual:
//   - Rotated 90° vertically
//   - Subtle floating/bobbing animation (3-4px oscillation, idle state only)
//   - User can drag horizontally to the right
//   - Non-vendors: hard limit 15%, snap back, progressive prompts
//
// Phase V-2 (2026-05): 3-pull confirmation gate. Users must demonstrate
// intentional interest before we open the registration flow.
// =============================================================================

import 'dart:async';
import 'dart:math' as _math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/screens/vendor_apply.dart';
import 'package:azaman/screens/vendor_dashboard.dart';

class VendorPullTab extends ConsumerStatefulWidget {
  const VendorPullTab({super.key});

  @override
  ConsumerState<VendorPullTab> createState() => _VendorPullTabState();
}

class _VendorPullTabState extends ConsumerState<VendorPullTab>
    with TickerProviderStateMixin {
  late AnimationController _floatController;
  late Animation<double> _floatAnimation;
  late AnimationController _snapController;
  late Animation<double> _snapAnimation;
  // Phase H6 BUGFIX (2026-05-27): the snap-back animation listener is
  // installed ONCE in initState and reads `_snapAnimation.value` directly
  // (the field is reassigned per drag-end with the new tween range).
  // Previous version called `_snapController.addListener(...)` inside
  // `_onDragEnd`, leaking a fresh listener every time the user dragged
  // the tab. After N drags, the (N+1)th drag's animation fired N
  // setState() calls per tick — quadratic rebuild storm + memory leak.
  late final VoidCallback _snapListener;

  double _dragX = 0;
  bool _isDragging = false;
  bool _hasPassedThreshold = false;
  bool _hasHitLimit = false;

  // 3-pull state for non-vendors
  int _pullCount = 0; // 0 = fresh, 1 = info shown, 2 = confirm shown
  Timer? _pullResetTimer;
  static const _pullTimeoutDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();

    _floatController = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(begin: -3.0, end: 3.0).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    _snapController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _snapAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.elasticOut),
    );
    // Install the snap-back animation listener exactly once. The
    // `_snapAnimation` reference is reassigned per drag-end (new
    // begin/end tween range), but the controller is the same — driving
    // the listener via `_snapAnimation.value` Just Works without
    // re-attaching.
    _snapListener = () {
      if (mounted) setState(() => _dragX = _snapAnimation.value);
    };
    _snapController.addListener(_snapListener);
  }

  @override
  void dispose() {
    _floatController.dispose();
    _snapController.removeListener(_snapListener);
    _snapController.dispose();
    _pullResetTimer?.cancel();
    super.dispose();
  }

  void _resetPullState() {
    _pullResetTimer?.cancel();
    setState(() => _pullCount = 0);
  }

  void _startPullTimeout() {
    _pullResetTimer?.cancel();
    _pullResetTimer = Timer(_pullTimeoutDuration, () {
      if (mounted) _resetPullState();
    });
  }

  void _onDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _hasPassedThreshold = false;
      _hasHitLimit = false;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isVendor = ref.read(tradeProvider).currentRole == AppRole.vendor;

    setState(() {
      if (isVendor) {
        _dragX = (_dragX + details.delta.dx).clamp(0.0, double.infinity);
        if (_dragX > screenWidth * 0.5 && !_hasPassedThreshold) {
          _hasPassedThreshold = true;
          HapticFeedback.heavyImpact();
        }
      } else {
        final maxDrag = screenWidth * 0.15;
        _dragX = (_dragX + details.delta.dx).clamp(0.0, maxDrag);
        if (_dragX >= maxDrag - 1 && !_hasHitLimit) {
          _hasHitLimit = true;
          HapticFeedback.mediumImpact();
        }
      }
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isVendor = ref.read(tradeProvider).currentRole == AppRole.vendor;

    if (isVendor && _dragX > screenWidth * 0.5) {
      HapticFeedback.heavyImpact();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const VendorDashboard()),
      );
      setState(() {
        _dragX = 0;
        _isDragging = false;
      });
    } else {
      // Snap back
      HapticFeedback.lightImpact();
      _snapAnimation = Tween<double>(begin: _dragX, end: 0).animate(
        CurvedAnimation(parent: _snapController, curve: Curves.elasticOut),
      );
      _snapController.forward(from: 0).then((_) {
        if (mounted) setState(() => _dragX = 0);
      });
      // BUGFIX: listener installed once in initState — see field
      // declaration. No per-drag-end addListener.

      // Non-vendor: 3-pull progression
      if (!isVendor && _dragX > screenWidth * 0.05) {
        _handleNonVendorPull();
      }

      setState(() => _isDragging = false);
    }
  }

  void _handleNonVendorPull() {
    _pullCount++;
    _startPullTimeout();

    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;

      switch (_pullCount) {
        case 1:
          // First pull: show info popup
          _showVendorInfoPopup();
          break;
        case 2:
          // Second pull: show confirmation prompt
          _showConfirmationPrompt();
          break;
        case >= 3:
          // Third pull: open registration
          HapticFeedback.heavyImpact();
          _pullResetTimer?.cancel();
          _resetPullState();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VendorApplyScreen()),
          );
          break;
      }
    });
  }

  void _showVendorInfoPopup() {
    final colors = ref.read(themeProvider).colors;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VendorRequirementSheet(
        colors: colors,
        onOpenWebsite: () async {
          final uri = Uri.parse('https://azaman.me/vendors');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
      ),
    );
  }

  void _showConfirmationPrompt() {
    final colors = ref.read(themeProvider).colors;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.storefront_rounded, color: colors.accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ready to become a vendor?',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Pull the tab one more time to start your application',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.accent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '5s',
                style: TextStyle(
                  color: colors.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: colors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.accent.withOpacity(0.3)),
        ),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        duration: _pullTimeoutDuration,
        elevation: 8,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final role = ref.watch(tradeProvider.select((t) => t.currentRole));
    final isVendor = role == AppRole.vendor;

    // Dynamic label based on pull state — shortened to fit the new
    // 78px ribbon without truncation.
    String label;
    if (isVendor) {
      label = 'VENDOR';
    } else if (_pullCount >= 2) {
      label = 'PULL!';
    } else {
      label = 'BE VENDOR';
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final maxForProgress = isVendor ? screenWidth * 0.5 : screenWidth * 0.15;
    final progress = (_dragX / maxForProgress).clamp(0.0, 1.0);

    // Color shifts based on pull progress
    final tabBgColor = _hasPassedThreshold
        ? colors.accent
        : (_pullCount >= 2 && !isVendor)
            ? colors.accent.withOpacity(0.2)
            : (_hasHitLimit && !isVendor)
                ? colors.danger.withOpacity(0.15)
                : colors.surface.withOpacity(0.95);

    final tabBorderColor = _hasPassedThreshold
        ? colors.accent
        : (_pullCount >= 2 && !isVendor)
            ? colors.accent.withOpacity(0.7)
            : (_hasHitLimit && !isVendor)
                ? colors.danger.withOpacity(0.6)
                : colors.accent.withOpacity(0.4);

    final tabTextColor = _hasPassedThreshold
        ? (colors.isDark ? Colors.black : Colors.white)
        : (_pullCount >= 2 && !isVendor)
            ? colors.accent
            : (_hasHitLimit && !isVendor)
                ? colors.danger
                : colors.accent;

    return AnimatedBuilder(
      animation: _floatAnimation,
      builder: (context, child) {
        return Positioned(
          // Master Sprint v2: horizontal ribbon now hangs flush from the
          // left edge of the screen so the cloth body extends rightward.
          // The previous rotated layout used a -28 shim to hide the
          // rotated rectangle's edge; with the painter's natural
          // orientation that's no longer needed.
          left: 0 + _dragX,
          top: MediaQuery.of(context).size.height * 0.45 +
              (_isDragging ? 0 : _floatAnimation.value),
          child: GestureDetector(
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              child: Stack(
                children: [
                  // Drag trail
                  if (_isDragging && _dragX > 20)
                    Positioned(
                      left: 0,
                      child: Container(
                        width: _dragX,
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              colors.accent.withOpacity(0.0),
                              (_hasHitLimit && !isVendor)
                                  ? (_pullCount >= 2
                                      ? colors.accent.withOpacity(progress * 0.7)
                                      : colors.danger.withOpacity(progress * 0.5))
                                  : colors.accent.withOpacity(progress * 0.5),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // The tab — Master Sprint v2 (2026-05-27): horizontal
                  // waving ribbon. Reads "VENDOR" along the cloth body
                  // with sinusoidal long edges, a chevron tail, and a
                  // subtle wave that amplifies during drag. The ribbon
                  // is anchored at the LEFT edge (because that's where
                  // the user grabs it) and the cloth flutters to the
                  // RIGHT toward the tail.
                  AnimatedBuilder(
                    animation: _floatController,
                    builder: (context, _) => CustomPaint(
                      // Master Sprint v2 (2026-05-27): shorter ribbon —
                      // 78px wide so it doesn't dominate the side gutter.
                      // Height kept at 28 to keep the tap target.
                      size: const Size(78, 28),
                      painter: _RibbonPainter(
                        label: label,
                        background: tabBgColor,
                        border: tabBorderColor,
                        text: tabTextColor,
                        phase: _floatController.value * 6.2831853,
                        amplitude: _isDragging ? 4.0 : 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// RIBBON PAINTER — Master Sprint v2 (2026-05-27)
//
// Renders the vendor-pull tab as a waving cloth ribbon. The ribbon body
// is a path with two sinusoidal long edges plus a chevron tail on one end,
// mimicking how a flag or banner ripples in the wind. The wave phase comes
// from the parent's float controller; amplitude bumps during drag.
// =============================================================================
class _RibbonPainter extends CustomPainter {
  final String label;
  final Color background;
  final Color border;
  final Color text;
  final double phase;
  final double amplitude;

  _RibbonPainter({
    required this.label,
    required this.background,
    required this.border,
    required this.text,
    required this.phase,
    required this.amplitude,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final amp = amplitude;
    // Tail notch (chevron) takes ~14px on the right end of the ribbon.
    const tail = 14.0;
    const samples = 24;

    // Top edge — sine wave from x=0 to x=w-tail
    final path = Path();
    path.moveTo(0, _waveY(0, w - tail, amp, phase));
    for (int i = 1; i <= samples; i++) {
      final t = i / samples;
      final x = (w - tail) * t;
      path.lineTo(x, _waveY(x, w - tail, amp, phase));
    }
    // Top-right corner of cloth
    path.lineTo(w - tail, _waveY(w - tail, w - tail, amp, phase));
    // Forked tail — V-cut chevron
    path.lineTo(w, h * 0.5 - 1);
    path.lineTo(w - tail, h - 0 + _waveY(w - tail, w - tail, amp, phase) - h);
    path.lineTo(w - tail, h + _waveY(w - tail, w - tail, amp, phase * 1.05));
    // Bottom edge — sine wave (slightly out-of-phase with top so the cloth
    // appears to bend, not just translate)
    for (int i = samples; i >= 0; i--) {
      final t = i / samples;
      final x = (w - tail) * t;
      path.lineTo(x, h + _waveY(x, w - tail, amp, phase * 1.05));
    }
    path.close();

    // Fill
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          background,
          Color.alphaBlend(
            background.withOpacity(0.6),
            border.withOpacity(0.18),
          ),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(path, fillPaint);

    // Stitch / border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = border;
    canvas.drawPath(path, borderPaint);

    // Soft drop shadow under the ribbon — single offset blur
    final shadowPaint = Paint()
      ..color = border.withOpacity(0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.save();
    canvas.translate(0, 1.5);
    canvas.drawPath(path, shadowPaint);
    canvas.restore();

    // Label — centred horizontally on the cloth body
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: text,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.6,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: w - tail - 6);
    final tx = ((w - tail) - tp.width) / 2;
    final ty = (h - tp.height) / 2;
    tp.paint(canvas, Offset(tx, ty));
  }

  /// Vertical offset for a point at x along [0, len], using a sine wave.
  double _waveY(double x, double len, double amp, double phase) {
    // Anchor the ribbon ends so the wave doesn't pull away from the
    // attachment edge — multiply by a fade that goes 0→1 over the first
    // ~25% of the length.
    final t = (x / len).clamp(0.0, 1.0);
    final fade = (t < 0.25) ? (t / 0.25) : 1.0;
    final wave = amp * fade *
        (0.6 * _sin(phase + t * 6.2831853) + 0.4 * _sin(phase * 1.5 + t * 9.42));
    return wave;
  }

  double _sin(double r) {
    // Inline tiny Taylor approx not needed — math.sin is fine, but we
    // want zero allocation per frame so use the cached function.
    return _math.sin(r);
  }

  @override
  bool shouldRepaint(_RibbonPainter old) =>
      old.phase != phase ||
      old.amplitude != amplitude ||
      old.background != background ||
      old.border != border ||
      old.text != text ||
      old.label != label;
}





// =============================================================================
// VENDOR REQUIREMENT POPUP (Bottom Sheet) — shown on 1st pull
// =============================================================================

class _VendorRequirementSheet extends StatelessWidget {
  final AzamanColors colors;
  final VoidCallback onOpenWebsite;

  const _VendorRequirementSheet({
    required this.colors,
    required this.onOpenWebsite,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Header
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.accent.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.storefront_rounded,
                        color: colors.accent, size: 40),
                  ),
                ),
                const SizedBox(height: 20),

                Center(
                  child: Text(
                    'You\'re Not a Vendor Yet',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Earn from every trade. Set your own rates. Build your reputation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                _buildSectionTitle('What You\'ll Need'),
                const SizedBox(height: 12),
                _buildRequirement(Icons.badge_rounded,
                    'Valid Government ID',
                    'Passport, National ID, or Driver\'s License with a selfie'),
                _buildRequirement(Icons.home_rounded,
                    'Proof of Address',
                    'Utility bill or bank statement (within 3 months)'),
                _buildRequirement(Icons.account_balance_wallet_rounded,
                    'Minimum \$500 USDT Collateral',
                    'Locked during your active vendor period'),
                _buildRequirement(Icons.payment_rounded,
                    'At Least 2 Payment Methods',
                    'Mobile Money, bank transfer, or supported e-wallets'),
                _buildRequirement(Icons.verified_user_rounded,
                    'Financial Background Check',
                    'Source of funds and trading experience'),

                const SizedBox(height: 24),

                _buildSectionTitle('Why Become a Vendor?'),
                const SizedBox(height: 12),
                _buildBenefit('Set your own exchange rates and margins'),
                _buildBenefit('Earn on every trade with zero platform listing fees'),
                _buildBenefit('Priority support and dispute resolution'),
                _buildBenefit('Vendor XP system with level-up rewards'),
                _buildBenefit('Access to analytics dashboard and ad boosting'),

                const SizedBox(height: 28),

                // Website link
                GestureDetector(
                  onTap: onOpenWebsite,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.accent.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.accent.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.open_in_new_rounded,
                            color: colors.accent, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Learn More on Our Website',
                                  style: TextStyle(
                                      color: colors.accent,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(
                                  'azaman.me/vendors — Full details, FAQ, and success stories',
                                  style: TextStyle(
                                      color: colors.textTertiary,
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded,
                            color: colors.accent.withOpacity(0.5), size: 14),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Phase UI-1 (2026-05-26): "Start Application" CTA removed
                // ────────────────────────────────────────────────────────────
                // The application path is intentionally gated by the 3-pull
                // confirmation flow on the side tab. A primary button here
                // bypassed that gate and produced two parallel onboarding
                // entrances. Replaced with a clean text block prompting the
                // user to either browse the website (link above) or pull the
                // tab two more times to begin the in-app application.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surface.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: colors.accent, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Want to apply?',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'For full vendor program details, FAQ, and success '
                        'stories visit our official website above. To begin '
                        'your application in-app, dismiss this and pull the '
                        'side tab two more times within 5 seconds.',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: TextStyle(
            color: colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800));
  }

  Widget _buildRequirement(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: colors.accent, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style:
                        TextStyle(color: colors.textTertiary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefit(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: colors.success, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
