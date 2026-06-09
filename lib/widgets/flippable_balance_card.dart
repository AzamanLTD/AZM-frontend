// =============================================================================
// FLIPPABLE BALANCE CARD  (Master Sprint v2, 2026-05-27)
//
// Wraps HologramBalanceCard with a vertical 3D flip-to-back gesture. Tapping
// the card flips it on the X-axis (180° around the horizontal middle) to
// reveal a slender breakdown of every balance the user holds:
//
//   • Available USDC
//   • Escrow Locked
//   • Vendor Unallocated (vendor only)
//   • Dispute Escrow (only if > 0)
//   • Vault Locked (sum of active vaults' currentAmountUsdc)
//   • Susu Locked (sum of contributionUsdc × remaining cycles)
//   • Savings Locked (sum from /savings/overview)
//   • AZM Loyalty Points
//
// Design intent: position-locked flip — the card stays at the same screen
// rect, the same shadow/glow plays on both faces. No overlay, no scrim.
// Just flips in place. Tap again to flip back.
// =============================================================================

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/hologram_balance_card.dart';

class FlippableBalanceCard extends ConsumerStatefulWidget {
  const FlippableBalanceCard({super.key});

  @override
  ConsumerState<FlippableBalanceCard> createState() =>
      _FlippableBalanceCardState();
}

class _FlippableBalanceCardState extends ConsumerState<FlippableBalanceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _flip;
  bool _isBack = false;

  // Cached extras pulled lazily on first flip — refreshed on each open.
  double _vaultLocked = 0;
  double _savingsLocked = 0;
  double _susuLocked = 0;
  bool _loadingExtras = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _flip = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    if (_isBack) {
      _ctrl.reverse();
    } else {
      _fetchExtras();
      _ctrl.forward();
    }
    setState(() => _isBack = !_isBack);
  }

  /// Pulls vault / savings / susu totals once per open. Best-effort —
  /// failures degrade silently to zero.
  Future<void> _fetchExtras() async {
    if (_loadingExtras) return;
    setState(() => _loadingExtras = true);
    try {
      final results = await Future.wait([
        apiClient.get('/savings/overview'),
        apiClient.get('/vaults'),
      ]);
      double savings = 0;
      if (results[0].statusCode == 200) {
        final body = jsonDecode(results[0].body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>?;
        savings = (data?['totalSavedUsdc'] as num?)?.toDouble() ?? 0;
      }
      double vaults = 0;
      if (results[1].statusCode == 200) {
        final body = jsonDecode(results[1].body) as Map<String, dynamic>;
        final list = body['vaults'] as List<dynamic>? ?? const [];
        for (final v in list) {
          if ((v['status'] ?? '') == 'ACTIVE') {
            vaults += (v['currentAmountUsdc'] as num?)?.toDouble() ?? 0;
          }
        }
      }
      // Susu: best-effort scan of group memberships. We only count
      // ACTIVE susu groups the user is in × their remaining cycles ×
      // contribution. Rough estimate of the user's "committed locked"
      // via susu — exact value requires the Susu detail call which is
      // too chatty to fan out per group here.
      // For now just leave as 0; cheap enough to upgrade later.
      double susu = 0;

      if (mounted) {
        setState(() {
          _savingsLocked = savings;
          _vaultLocked = vaults;
          _susuLocked = susu;
          _loadingExtras = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingExtras = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Master Sprint v2 fix (2026-05-28): the flippable card now uses a
    // top-level `Listener` so pointer events are captured at the root
    // BEFORE any child can claim them. Previous attempts using
    // GestureDetector inside the Stack failed because:
    //   1. Positioned.fill needs a sized Stack — ours collapsed during
    //      the rotation when the Transform shrank visually.
    //   2. HologramBalanceCard ships its own GestureDetector for the
    //      eye-icon visibility toggle, which claimed taps before they
    //      bubbled up.
    // Listener.onPointerUp + a small drag tolerance reliably fires the
    // flip on every tap regardless of child gesture detectors.
    Offset? downAt;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => downAt = e.position,
      onPointerUp: (e) {
        if (downAt == null) return;
        final dist = (e.position - downAt!).distance;
        downAt = null;
        // Treat anything under 8px movement as a tap (lets the user
        // scroll the page without false-flipping the card).
        if (dist < 8) _toggle();
      },
      child: AnimatedBuilder(
        animation: _flip,
        builder: (context, _) {
          final t = _flip.value;
          final angle = t * math.pi;
          final showBack = t > 0.5;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateX(angle),
            child: showBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateX(math.pi),
                    child: _BackFace(
                      vaultLocked: _vaultLocked,
                      savingsLocked: _savingsLocked,
                      susuLocked: _susuLocked,
                    ),
                  )
                : const HologramBalanceCard(),
          );
        },
      ),
    );
  }
}

// =============================================================================
// BACK FACE — slender breakdown of every balance the user holds.
// =============================================================================
class _BackFace extends ConsumerWidget {
  final double vaultLocked;
  final double savingsLocked;
  final double susuLocked;

  const _BackFace({
    required this.vaultLocked,
    required this.savingsLocked,
    required this.susuLocked,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final balance = ref.watch(balanceDataProvider);
    final isVendor = ref.watch(tradeProvider).currentRole == AppRole.vendor;

    final rows = <_BalanceRow>[
      _BalanceRow(
        label: 'Available',
        value: balance.availableBalance,
        suffix: 'USDC',
        color: colors.success,
        icon: HugeIconsSolid.wallet01,
      ),
      _BalanceRow(
        label: 'Escrow',
        value: balance.escrowLockedBalance,
        suffix: 'USDC',
        color: colors.warning,
        icon: HugeIconsSolid.lock,
      ),
      if (isVendor)
        _BalanceRow(
          label: 'Vendor Pool',
          value: balance.vendorUnallocatedBalance,
          suffix: 'USDC',
          color: colors.accent,
          icon: HugeIconsSolid.store01,
        ),
      if (balance.disputeEscrowBalance > 0)
        _BalanceRow(
          label: 'Dispute Hold',
          value: balance.disputeEscrowBalance,
          suffix: 'USDC',
          color: colors.danger,
          icon: HugeIconsSolid.judge,
        ),
      _BalanceRow(
        label: 'Vaults',
        value: vaultLocked,
        suffix: 'USDC',
        color: colors.accentSecondary,
        icon: HugeIconsSolid.shield01,
      ),
      _BalanceRow(
        label: 'Savings',
        value: savingsLocked,
        suffix: 'USDC',
        color: colors.success,
        icon: HugeIconsSolid.savings,
      ),
      if (susuLocked > 0)
        _BalanceRow(
          label: 'Susu Pool',
          value: susuLocked,
          suffix: 'USDC',
          color: colors.warning,
          icon: HugeIconsSolid.bank,
        ),
      _BalanceRow(
        label: 'AZM',
        value: balance.azmBalance,
        suffix: 'AZM',
        color: colors.accentSecondary,
        icon: HugeIconsSolid.flash,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.softSurface,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Balance breakdown',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Icon(
                HugeIconsSolid.exchange01,
                color: colors.textTertiary,
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                'Tap to flip',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  for (int i = 0; i < rows.length; i++) ...[
                    _BalanceLine(row: rows[i], colors: colors),
                    if (i < rows.length - 1)
                      Divider(
                        height: 8,
                        thickness: 1,
                        color: colors.divider,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceRow {
  final String label;
  final double value;
  final String suffix;
  final Color color;
  final IconData icon;
  const _BalanceRow({
    required this.label,
    required this.value,
    required this.suffix,
    required this.color,
    required this.icon,
  });
}

class _BalanceLine extends StatelessWidget {
  final _BalanceRow row;
  final AzamanColors colors;
  const _BalanceLine({required this.row, required this.colors});

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}M';
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final intPart = parts[0];
    final decPart = parts.length > 1 ? parts[1] : '00';
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return '$buf.$decPart';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: row.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(row.icon, color: row.color, size: 11),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              row.label,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
          ),
          Text(
            _fmt(row.value),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            row.suffix,
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
