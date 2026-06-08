// =============================================================================
// DASHBOARD BALANCE CARD — "SLENDER BLACK CARD" + restorations
//
// PRESERVED (forbidden to remove):
//   • ISO/IEC 7810 ID-1 aspect ratio (1.586:1) — see kCreditCardAspectRatio.
//   • Pitch-black gradient with 8% white frosted-glass border.
//   • _TitaniumSweep — the slow ambient-light reflection animation.
//   • No Quick Action buttons inside the card (they live in
//     `quick_actions_row.dart` placed BELOW the card by the parent).
//
// SURGICAL RESTORATIONS (this revision):
//   1. User Identity — the static "AZAMAN BLACK" wordmark is replaced
//      by the live `user.username` + `@UID-${user.id}` (read from
//      Riverpod `currentUserProvider`). Falls back to "Guest / @UID-—"
//      when no user is hydrated yet.
//
//   2. Live Oracle Data — a compact pill on the bottom row of the
//      card now shows the live `oracleRateProvider` rate AND a
//      countdown timer ticking down to the next API refresh (the
//      "API Refresh Timer" previously deleted from user_dashboard.dart
//      — see `_OracleRefreshPill`). When the rate value changes
//      mid-cycle, the countdown auto-resets, so the timer always
//      reflects the true time-since-last-sync.
//
// Performance contract:
//   • The chrome (gradient, glass, border, light sweep) is one
//     StatefulWidget with a single AnimationController.
//   • _BalanceDisplay, _CardIdentityHeader and _OracleRefreshPill are
//     ConsumerWidgets so only their subtrees rebuild on Riverpod
//     state changes — the chrome / shell / sweep never repaint
//     because of data ticks.
// =============================================================================

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:hugeicons_pro/hugeicons.dart';

// ── Public constants ────────────────────────────────────────────────────────

/// ISO/IEC 7810 ID-1 credit-card aspect ratio. PROTECTED.
const double kCreditCardAspectRatio = 1.586;

/// Seconds between live oracle refreshes (mirrors the backend cron).
const int kOracleRefreshSeconds = 600;

// =============================================================================
// PUBLIC ENTRY POINT
//
// PROTECTED IMMUTABLE WIDGET (AZAMAN_MASTER_SOUL.md §3):
// The slender black balance card is locked down. Theme colors are read with
// `select()` so the chrome only repaints on a true theme switch — never on
// a data tick. Internal data widgets (_BalanceDisplay, _CardIdentityHeader,
// _OracleRefreshPill) are ConsumerWidgets that select their own slice of
// state so repaints stay surgical.
// =============================================================================
class DashboardBalanceCard extends ConsumerWidget {
  /// Optional label override (defaults to "Total Portfolio Value").
  final String? label;

  const DashboardBalanceCard({
    super.key,
    this.label,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Granular: only repaint when the colors object actually changes.
    final colors = ref.watch(themeProvider.select((t) => t.colors));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: AspectRatio(
        aspectRatio: kCreditCardAspectRatio,
        child: _BlackCardShell(
          colors: colors,
          child: _CardFace(
            colors: colors,
            label: label,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SHELL — frosted glass + deep gradient + 8% border + Titanium Light Sweep
// (UNCHANGED from previous Polish Sprint — preserved verbatim)
// =============================================================================
class _BlackCardShell extends StatefulWidget {
  final AzamanColors colors;
  final Widget child;
  const _BlackCardShell({required this.colors, required this.child});

  @override
  State<_BlackCardShell> createState() => _BlackCardShellState();
}

class _BlackCardShellState extends State<_BlackCardShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    // 6-second slow loop — ambient titanium reflection.
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.55),
            blurRadius: 28,
            spreadRadius: -4,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: widget.colors.glow.withOpacity(0.05),
            blurRadius: 32,
            spreadRadius: -10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF161618),
                  Color(0xFF0B0B0D),
                  Color(0xFF000000),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
                width: 1.0,
              ),
            ),
            child: Stack(
              children: [
                // Static top-edge sheen
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.0),
                          Colors.white.withOpacity(0.16),
                          Colors.white.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Titanium Light Sweep — PROTECTED ───────────────────────
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _sweep,
                        builder: (_, __) =>
                            _TitaniumSweep(progress: _sweep.value),
                      ),
                    ),
                  ),
                ),

                // ── Card content ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: widget.child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TITANIUM LIGHT SWEEP  (UNCHANGED — PROTECTED)
// =============================================================================
class _TitaniumSweep extends StatelessWidget {
  final double progress;
  const _TitaniumSweep({required this.progress});

  @override
  Widget build(BuildContext context) {
    final t = -2.0 + progress * 4.0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(t - 0.4, -1.0),
          end: Alignment(t + 0.4, 1.0),
          colors: [
            Colors.white.withOpacity(0.00),
            Colors.white.withOpacity(0.03),
            Colors.white.withOpacity(0.05),
            Colors.white.withOpacity(0.03),
            Colors.white.withOpacity(0.00),
          ],
          stops: const [0.0, 0.42, 0.50, 0.58, 1.0],
        ),
      ),
    );
  }
}

// =============================================================================
// CARD FACE — three rows (identity / balance / oracle pill)
// =============================================================================
class _CardFace extends StatelessWidget {
  final AzamanColors colors;
  final String? label;
  const _CardFace({
    required this.colors,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // ── Top row: identity + USDC pill ────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _CardIdentityHeader(colors: colors)),
            const SizedBox(width: 12),
            _UsdcPill(colors: colors),
          ],
        ),

        // ── Middle: live balance numerals ────────────────────────────────
        _BalanceDisplay(colors: colors, label: label),

        // ── Bottom: live oracle rate + API refresh timer ─────────────────
        _OracleRefreshPill(colors: colors),
      ],
    );
  }
}

// =============================================================================
// CARD IDENTITY HEADER — uses select() so only username/id changes trigger a
// rebuild here. Balance ticks, ban-status changes, etc. are filtered out.
// =============================================================================
class _CardIdentityHeader extends ConsumerWidget {
  final AzamanColors colors;
  const _CardIdentityHeader({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Granular: extract just the (username, id) tuple. The widget will only
    // repaint when one of those two fields actually changes — every other
    // User mutation (balance updates, role flips, KYC status, ban status)
    // is filtered out at the provider boundary.
    final identity = ref.watch(
      currentUserProvider.select((async) {
        final u = async.value;
        return (u?.username ?? 'Guest', u?.id ?? '—');
      }),
    );
    final username = identity.$1.isEmpty ? 'Guest' : identity.$1;
    final uid      = '@UID-${identity.$2}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          username,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withOpacity(0.96),
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          uid,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.0,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// USDC PILL — live indicator (UNCHANGED)
// =============================================================================
class _UsdcPill extends StatelessWidget {
  final AzamanColors colors;
  const _UsdcPill({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.success,
              boxShadow: [
                BoxShadow(
                  color: colors.success.withOpacity(0.7),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'USDC',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// BALANCE DISPLAY — uses select() so only the GHS numeral repaints on each
// rate / balance tick. The label, eye icon, "GH₵" prefix and surrounding
// layout never repaint while data is streaming.
// =============================================================================
class _BalanceDisplay extends ConsumerWidget {
  final AzamanColors colors;
  final String? label;
  const _BalanceDisplay({required this.colors, this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Granular: the hologram amount and the visibility flag are the only
    // two pieces of state that should ever cause a rebuild here.
    final ghsValue  = ref.watch(hologramBalanceProvider.select((v) => v));
    final isVisible = ref.watch(balanceVisibleProvider.select((v) => v));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              (label ?? 'Total Portfolio Value').toUpperCase(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.50),
                fontSize: 9.5,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(balanceVisibleProvider.notifier).state = !isVisible;
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Icon(
                  isVisible
                      ? HugeIconsSolid.view
                      : HugeIconsSolid.viewOff,
                  color: Colors.white.withOpacity(0.50),
                  size: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'GH₵',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: Text(
                  isVisible ? _formatBalance(ghsValue) : '••••••',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.2,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatBalance(double value, {int decimals = 2}) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    }
    final parts = value.toStringAsFixed(decimals).split('.');
    final intPart = parts[0];
    final decPart = parts.length > 1 ? parts[1] : '';
    final buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
      buffer.write(intPart[i]);
    }
    return decimals > 0 ? '$buffer.$decPart' : buffer.toString();
  }
}

// =============================================================================
// ORACLE REFRESH PILL — restored (live rate + API refresh countdown)
//
// Renders one compact glass pill on the bottom row of the card:
//   ●  GH₵ 11.44   ·   sync 04:32
//
// • Watches `oracleRateProvider` for the live USD→GHS rate.
// • Holds its own `Timer.periodic(Duration(seconds: 1))` ticking the
//   countdown from `kOracleRefreshSeconds` down to 0, then loops back
//   so the user always sees the time remaining until the next sync.
// • Listens to `oracleRateProvider` via `ref.listen` — when a new rate
//   arrives mid-cycle, the countdown resets to full so the timer
//   accurately reflects "time since last sync".
// =============================================================================
class _OracleRefreshPill extends ConsumerStatefulWidget {
  final AzamanColors colors;
  const _OracleRefreshPill({required this.colors});

  @override
  ConsumerState<_OracleRefreshPill> createState() =>
      _OracleRefreshPillState();
}

class _OracleRefreshPillState extends ConsumerState<_OracleRefreshPill> {
  Timer? _ticker;
  int _secondsRemaining = kOracleRefreshSeconds;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsRemaining =
            _secondsRemaining > 0 ? _secondsRemaining - 1 : kOracleRefreshSeconds;
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  @override
  Widget build(BuildContext context) {
    // Granular: when the rate value flips, reset the countdown. We use
    // `.select((r) => r)` to make the dependency explicit — only ticks of
    // the oracle rate provider can wake this listener up.
    ref.listen<double>(
      oracleRateProvider.select((r) => r),
      (prev, next) {
        if (prev != next && mounted) {
          setState(() => _secondsRemaining = kOracleRefreshSeconds);
        }
      },
    );

    final rate = ref.watch(oracleRateProvider.select((r) => r));
    final c = widget.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing live dot
          _LivePulseDot(color: c.success),
          const SizedBox(width: 6),
          Text(
            'GH₵ ${rate.toStringAsFixed(2)}',
            style: TextStyle(
              color: c.success,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 8,
            color: Colors.white.withOpacity(0.10),
          ),
          const SizedBox(width: 8),
          Icon(
            HugeIconsSolid.refresh01,
            size: 10,
            color: Colors.white.withOpacity(0.55),
          ),
          const SizedBox(width: 4),
          Text(
            _fmt(_secondsRemaining),
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// Tiny independent pulsing dot — runs its own animation so it doesn't
// trigger a rebuild of the whole pill on every frame.
class _LivePulseDot extends StatefulWidget {
  final Color color;
  const _LivePulseDot({required this.color});

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withOpacity(0.45 + 0.55 * _ctrl.value),
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(0.45 * _ctrl.value),
              blurRadius: 5,
            ),
          ],
        ),
      ),
    );
  }
}
