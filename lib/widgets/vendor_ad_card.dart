import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/marketplace_provider.dart';
import 'package:azaman/widgets/risk_tag.dart';

/// Vendor Ad Card — redesigned as a proper card with purple/magenta tint,
/// diagonal hatch texture, avatar, risk pill, SELL/BUY tag, and info chips.
/// Matches the reference screenshot provided by the founder.
class VendorAdCard extends ConsumerWidget {
  final AdListing ad;
  final VoidCallback? onTap;
  final bool showDivider; // kept for call-site compatibility; unused now
  const VendorAdCard({super.key, required this.ad, this.onTap, this.showDivider = true});

  static const _purple = Color(0xFF8B5CF6);
  static const _magenta = Color(0xFFD946A8);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final isSell = ad.adType.toUpperCase() == 'SELL';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap == null ? null : () { HapticFeedback.lightImpact(); onTap!(); },
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(colors.surface, _purple, 0.12)!,
                  Color.lerp(colors.surface, _magenta, 0.08)!,
                ],
              ),
              border: Border.all(color: _purple.withValues(alpha: 0.25), width: 1),
              boxShadow: [
                BoxShadow(color: _purple.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8)),
              ],
            ),
            child: Stack(
              children: [
                // Diagonal hatch texture — very low opacity, matches reference image
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CustomPaint(painter: _DiagonalHatchPainter(color: _purple.withValues(alpha: 0.05))),
                  ),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Top row: avatar, vendor name, online dot, risk pill
                  Row(children: [
                    _VendorAvatar(username: ad.vendorUsername, isOnline: ad.isOnline, purple: _purple),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(children: [
                        Flexible(
                          child: Text(ad.vendorUsername,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.textPrimary, fontSize: 16,
                              fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                        ),
                        const SizedBox(width: 6),
                        Container(width: 5, height: 5,
                          decoration: BoxDecoration(color: colors.textTertiary.withValues(alpha: 0.5), shape: BoxShape.circle)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    RiskTag(method: ad.paymentMethod),
                  ]),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 42),
                    child: Row(children: [
                      Icon(HugeIconsSolid.star, size: 12, color: const Color(0xFFF4B93D)),
                      const SizedBox(width: 4),
                      Text(_ratingLabel(ad), style: TextStyle(color: colors.textTertiary, fontSize: 12.5, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  // SELL/BUY tag + big payment method name, Available amount right
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (isSell ? colors.success : colors.accent).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(isSell ? 'SELL' : 'BUY',
                            style: TextStyle(color: isSell ? colors.success : colors.accent,
                              fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_formatPaymentMethod(ad.paymentMethod),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.textPrimary, fontSize: 20,
                              fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        ),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('Available', style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text('${_fmt(ad.availableUsdc)} USDC',
                        style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                    ]),
                  ]),
                  const SizedBox(height: 12),
                  // Bottom pill chips: limit range + payment method icon
                  Row(children: [
                    _InfoChip(icon: HugeIconsSolid.arrowDataTransferVertical,
                      label: '\$${_fmtInt(ad.minLimit)} – \$${_fmtInt(ad.maxLimit)}', colors: colors),
                    const SizedBox(width: 8),
                    _InfoChip(icon: HugeIconsSolid.bank, label: _formatPaymentMethod(ad.paymentMethod), colors: colors),
                  ]),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _ratingLabel(AdListing ad) {
    if (ad.completedTrades == 0) return '0 trades · 0% completion';
    final rate = (ad.completionRate * 100).toStringAsFixed(0);
    return '${ad.completedTrades} trades · $rate% completion';
  }

  String _formatPaymentMethod(String method) {
    final t = method.trim(); if (t.isEmpty) return method;
    final l = t.toLowerCase(); return l[0].toUpperCase() + l.substring(1);
  }

  String _fmt(double v) {
    if (v < 1000) return v.toStringAsFixed(2);
    final s = v.toStringAsFixed(0); final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(','); buf.write(s[i]); }
    return buf.toString();
  }

  String _fmtInt(double v) {
    if (v < 1000) return v.toStringAsFixed(0);
    final s = v.toStringAsFixed(0); final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(','); buf.write(s[i]); }
    return buf.toString();
  }
}

class _VendorAvatar extends StatelessWidget {
  final String username;
  final bool isOnline;
  final Color purple;
  const _VendorAvatar({required this.username, required this.isOnline, required this.purple});

  @override
  Widget build(BuildContext context) {
    final initials = username.length >= 2 ? username.substring(0, 2).toUpperCase() : username.toUpperCase();
    return Stack(children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [purple, purple.withValues(alpha: 0.6)]),
          border: Border.all(color: purple.withValues(alpha: 0.4), width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
      ),
      if (isOnline)
        Positioned(right: 0, bottom: 0,
          child: Container(width: 10, height: 10,
            decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle))),
    ]);
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final AzamanColors colors;
  const _InfoChip({required this.icon, required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.softSurface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: colors.divider.withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: colors.textSecondary),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _DiagonalHatchPainter extends CustomPainter {
  final Color color;
  _DiagonalHatchPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1;
    const spacing = 14.0;
    for (double x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DiagonalHatchPainter oldDelegate) => oldDelegate.color != color;
}
