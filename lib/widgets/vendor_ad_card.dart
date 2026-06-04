// =============================================================================
// VENDOR AD CARD — Phase 3.2 | Azaman V2
//
// Glassmorphism card consumed inside the Apple Wallet SliverList.
// Self-contained: accepts an AdListing, reads ThemeProvider for colors.
//
// Visual anatomy (Phase UI-1, 2026-05-26 — "Trade Now" CTA removed):
//   ┌──────────────────────────────────────────────────────┐
//   │  [Avatar]  VendorName ● online dot   [Risk Tag]      │
//   │             ★ 312 trades · 98% completion            │
//   ├──────────────────────────────────────────────────────┤
//   │  [SELL/BUY]  Bank Transfer        Available: 2,340   │
//   │  Limit: $50 – $5,000              Method: Bank ...   │
//   └──────────────────────────────────────────────────────┘
//
// Why no button: tapping the card body now flips it open via
// `ad_detail_flip_card.dart` and the trade form lives on the back face.
// A standalone "Trade Now" button was a redundant exit point and bulked
// out every row. Queue depth (when present) is communicated via the
// "X ahead" chip on the limits row.
//
// AI Filter badge renders when aiScore ≥ 0.80 and filter is active.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/marketplace_provider.dart';
import 'package:azaman/widgets/vendor_badge_row.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public widget
// ─────────────────────────────────────────────────────────────────────────────
class VendorAdCard extends ConsumerWidget {
  final AdListing ad;

  /// Called when the card itself is tapped (anywhere on the surface).
  /// Opens the [AdDetailFlipCard] overlay where the trade form lives.
  final VoidCallback? onTap;

  const VendorAdCard({
    super.key,
    required this.ad,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final aiFilterOn = ref.watch(aiFilterProvider);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onTap!();
            },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: _liquidGlassDecoration(colors, ad.riskLevel),
              child: Stack(
                children: [
                  // Subtle diagonal grain overlay
                  Positioned.fill(child: _GrainOverlay(color: colors.glow)),

                  Padding(
                    // Slender mandate: 14 vertical down from 18.
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Row 1: vendor identity + risk tag ──────────────────
                        _IdentityRow(ad: ad, colors: colors),
                        const SizedBox(height: 12),

                        // ── Row 2: ad type + payment method + available ───────
                        _RateRow(ad: ad, colors: colors),
                        const SizedBox(height: 8),

                        // ── Row 3: limits + payment method + meta chips ──────
                        _LimitsRow(
                          ad: ad,
                          colors: colors,
                          aiFilterOn: aiFilterOn,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 320.ms, curve: Curves.easeOut)
        .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
  }

  // ── Liquid Glass decoration — premium glassmorphism with BackdropFilter ──
  BoxDecoration _liquidGlassDecoration(AzamanColors colors, RiskLevel risk) {
    final Color borderColor;
    switch (risk) {
      case RiskLevel.low:
        borderColor = colors.success.withOpacity(0.15);
        break;
      case RiskLevel.medium:
        borderColor = colors.warning.withOpacity(0.15);
        break;
      case RiskLevel.high:
        borderColor = colors.danger.withOpacity(0.15);
        break;
    }

    return BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      // Dark translucent background for liquid glass effect
      color: colors.surface.withOpacity(0.25),
      border: Border.all(
        color: Colors.white.withOpacity(0.15),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.4),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: borderColor.withOpacity(0.15),
          blurRadius: 24,
          spreadRadius: 0,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grain overlay — purely decorative, painted once
// ─────────────────────────────────────────────────────────────────────────────
class _GrainOverlay extends StatelessWidget {
  final Color color;
  const _GrainOverlay({required this.color});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DiagPainter(color: color.withOpacity(0.03)));
}

class _DiagPainter extends CustomPainter {
  final Color color;
  const _DiagPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 0.6;
    const step = 22.0;
    for (double d = -size.height; d < size.width; d += step) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), p);
    }
  }
  @override
  bool shouldRepaint(_DiagPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Row 1: Vendor identity
// ─────────────────────────────────────────────────────────────────────────────
class _IdentityRow extends StatelessWidget {
  final AdListing ad;
  final AzamanColors colors;
  const _IdentityRow({required this.ad, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar
        _VendorAvatar(username: ad.vendorUsername, colors: colors),
        const SizedBox(width: 10),

        // Name + stats
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    ad.vendorUsername,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Online indicator
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ad.isOnline
                          ? colors.success
                          : colors.textTertiary.withOpacity(0.4),
                      boxShadow: ad.isOnline
                          ? [
                              BoxShadow(
                                color: colors.success.withOpacity(0.55),
                                blurRadius: 5,
                              )
                            ]
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Icon(Icons.star_rounded, color: colors.warning, size: 12),
                  const SizedBox(width: 3),
                  Text(
                    '${ad.completedTrades} trades',
                    style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w400),
                  ),
                  Text(
                    '  ·  ',
                    style: TextStyle(color: colors.textTertiary, fontSize: 11),
                  ),
                  Text(
                    '${(ad.completionRate * 100).toStringAsFixed(0)}% completion',
                    style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w400),
                  ),
                ],
              ),
              // Phase Q13: Vendor verification badges
              if (ad.vendorId.isNotEmpty)
                VendorBadgeRow(
                  vendorId: int.tryParse(ad.vendorId) ?? 0,
                  colors: colors,
                ),
            ],
          ),
        ),

        // Risk tag
        _RiskTag(riskLevel: ad.riskLevel, colors: colors),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vendor avatar circle — initials + gradient tinted by vendor hash
// ─────────────────────────────────────────────────────────────────────────────
class _VendorAvatar extends StatelessWidget {
  final String username;
  final AzamanColors colors;
  const _VendorAvatar({required this.username, required this.colors});

  Color _hashColor() {
    final hue = (username.codeUnits.fold(0, (a, b) => a + b) % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.60, 0.55).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final c = _hashColor();
    final initials = username.length >= 2
        ? username.substring(0, 2).toUpperCase()
        : username.toUpperCase();

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [
          c.withOpacity(0.40),
          c.withOpacity(0.10),
        ]),
        border: Border.all(color: c.withOpacity(0.40), width: 1.0),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: c,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Risk tag glass pill
// ─────────────────────────────────────────────────────────────────────────────
class _RiskTag extends StatelessWidget {
  final RiskLevel riskLevel;
  final AzamanColors colors;
  const _RiskTag({required this.riskLevel, required this.colors});

  @override
  Widget build(BuildContext context) {
    final Color tagColor;
    final String label;
    final IconData icon;

    switch (riskLevel) {
      case RiskLevel.low:
        tagColor = colors.success;
        label = 'Low Risk';
        icon = Icons.shield_rounded;
        break;
      case RiskLevel.medium:
        tagColor = colors.warning;
        label = 'Mid Risk';
        icon = Icons.warning_amber_rounded;
        break;
      case RiskLevel.high:
        tagColor = colors.danger;
        label = 'High Risk';
        icon = Icons.dangerous_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: tagColor.withOpacity(0.10),
        border: Border.all(color: tagColor.withOpacity(0.30), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: tagColor, size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: tagColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Row 2: Rate + available USDC
// ─────────────────────────────────────────────────────────────────────────────
class _RateRow extends StatelessWidget {
  final AdListing ad;
  final AzamanColors colors;
  const _RateRow({required this.ad, required this.colors});

  @override
  Widget build(BuildContext context) {
    final isSell = ad.isSellAd;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Ad type badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: isSell
                ? colors.success.withOpacity(0.12)
                : colors.danger.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            isSell ? 'SELL' : 'BUY',
            style: TextStyle(
              color: isSell ? colors.success : colors.danger,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Payment method as primary display
        Text(
          ad.paymentMethod,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            height: 1.0,
          ),
        ),
        const Spacer(),
        // Available
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Available',
              style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 10,
                  letterSpacing: 0.4),
            ),
            const SizedBox(height: 2),
            Text(
              '${_fmt(ad.availableUsdc)} USDC',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _fmt(double v) {
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      final buffer = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
        buffer.write(s[i]);
      }
      return buffer.toString();
    }
    return v.toStringAsFixed(2);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Row 3: Limits + payment method + queue depth + AI badge (Phase UI-1)
//
// After the "Trade Now" CTA was removed (2026-05-26), the AI score badge and
// queue-depth indicator that lived on the old CTA row migrate down here so
// the user still sees both pieces of information at a glance. The card-tap
// (handled at the parent) opens the flip overlay where the user actually
// initiates the trade.
// ─────────────────────────────────────────────────────────────────────────────
class _LimitsRow extends StatelessWidget {
  final AdListing ad;
  final AzamanColors colors;
  final bool aiFilterOn;
  const _LimitsRow({
    required this.ad,
    required this.colors,
    required this.aiFilterOn,
  });

  @override
  Widget build(BuildContext context) {
    final showAi = aiFilterOn && ad.aiScore >= 0.75;
    final showQueue = ad.queueFull && ad.queueDepth > 0;
    return Row(
      children: [
        _InfoChip(
          icon: Icons.swap_vert_rounded,
          label: '\$${_fmtInt(ad.minLimit)} – \$${_fmtInt(ad.maxLimit)}',
          colors: colors,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: _InfoChip(
            icon: Icons.account_balance_rounded,
            label: ad.paymentMethod,
            colors: colors,
          ),
        ),
        const Spacer(),
        if (showQueue) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: colors.warning.withOpacity(0.10),
              border: Border.all(
                  color: colors.warning.withOpacity(0.30), width: 0.7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hourglass_top_rounded,
                    color: colors.warning, size: 11),
                const SizedBox(width: 4),
                Text(
                  '${ad.queueDepth} ahead',
                  style: TextStyle(
                    color: colors.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (showAi) const SizedBox(width: 6),
        ],
        if (showAi) _AiBadge(score: ad.aiScore, colors: colors),
      ],
    );
  }

  String _fmtInt(double v) {
    if (v >= 1000) {
      final s = v.toStringAsFixed(0);
      final buf = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
        buf.write(s[i]);
      }
      return buf.toString();
    }
    return v.toStringAsFixed(0);
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final AzamanColors colors;
  const _InfoChip(
      {required this.icon, required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: colors.glow.withOpacity(0.06),
        border:
            Border.all(color: colors.glow.withOpacity(0.12), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.textTertiary, size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CtaRow REMOVED in Phase UI-1 (2026-05-26).
//
// Was a row containing the "Trade Now" / "Wait in Queue" button + AI badge +
// "X ahead" queue depth label. After the de-cluttering sweep:
//   • Queue depth + AI badge migrated into _LimitsRow (Row 3).
//   • Trade initiation moved to the back face of the flip overlay
//     (`ad_detail_flip_card.dart`), reachable by tapping the card body.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// AI Score Badge
// ─────────────────────────────────────────────────────────────────────────────
class _AiBadge extends StatelessWidget {
  final double score;
  final AzamanColors colors;
  const _AiBadge({required this.score, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6C63FF).withOpacity(0.22),
            const Color(0xFF00E5FF).withOpacity(0.14),
          ],
        ),
        border: Border.all(
            color: const Color(0xFF6C63FF).withOpacity(0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_rounded,
              color: Color(0xFF9D8FFF), size: 11),
          const SizedBox(width: 4),
          Text(
            'AI ${(score * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Color(0xFF9D8FFF),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
