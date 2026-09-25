// =============================================================================
// ACTIVE TICKET HUD  (2026-07-11 v2)
//
// A draggable side-tag on the RIGHT edge of the chat screen — directly modelled
// after VendorPullTab in vendor_pull_tab.dart.
//
// DRAG BEHAVIOUR (mirrors VendorPullTab exactly):
//   • User drags LEFT (toward the screen) — tab slides out from the right
//   • Past 50% screen width → heavy haptic + opens ticket immediately
//   • Released before threshold → elastic snap-back (Curves.elasticOut)
//   • Single listener installed in initState (no per-drag addListener leak)
//   • Also vertically draggable along the right edge (Y-axis clamped)
//
// VISUAL:
//   • Amber vertical pill with lock icon + rotated 'ACTIVE DEAL' text
//   • Idle: slow floating oscillation (same as VendorPullTab's bobbing)
//   • Dragging: oscillation paused, thumb stretches slightly
//
// When there are multiple open tickets, dragging past threshold opens a
// compact bottom-sheet picker instead of jumping straight to one workspace.
// =============================================================================


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/ticket_service.dart';

class ActiveTicketHud extends ConsumerStatefulWidget {
  final List<Ticket> tickets;
  final String peerName;
  final ValueChanged<Ticket> onTap;

  const ActiveTicketHud({
    super.key,
    required this.tickets,
    required this.peerName,
    required this.onTap,
  });

  @override
  ConsumerState<ActiveTicketHud> createState() => _ActiveTicketHudState();
}

class _ActiveTicketHudState extends ConsumerState<ActiveTicketHud>
    with TickerProviderStateMixin {
  // ── Float (idle bob) ───────────────────────────────────────────────────────
  late final AnimationController _floatCtrl;
  late final Animation<double> _floatAnim;

  // ── Snap-back (elastic return after release) ───────────────────────────────
  late final AnimationController _snapCtrl;
  Animation<double> _snapAnim; // reassigned per drag-end (same pattern as VendorPullTab)
  late final VoidCallback _snapListener;

  // ── Drag state ─────────────────────────────────────────────────────────────
  double _dragX = 0; // how far LEFT the tab has been pulled (0 = flush to edge)
  bool _isDragging = false;
  bool _passedThreshold = false;

  // ── Vertical position ──────────────────────────────────────────────────────
  double? _topOffset;

  _ActiveTicketHudState() : _snapAnim = const AlwaysStoppedAnimation(0);

  @override
  void initState() {
    super.initState();

    // Idle float
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -3.0, end: 3.0).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );

    // Snap-back — listener installed ONCE (avoids the leak VendorPullTab docs warn about)
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _snapAnim = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _snapCtrl, curve: Curves.elasticOut),
    );
    _snapListener = () {
      if (mounted) setState(() => _dragX = _snapAnim.value);
    };
    _snapCtrl.addListener(_snapListener);
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _snapCtrl.removeListener(_snapListener);
    _snapCtrl.dispose();
    super.dispose();
  }

  // ── Drag handlers ──────────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails _) {
    _floatCtrl.stop();
    setState(() {
      _isDragging = true;
      _passedThreshold = false;
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final sw = MediaQuery.of(context).size.width;
    // Dragging LEFT = negative dx → we invert to make _dragX positive
    setState(() {
      _dragX = (_dragX - d.delta.dx).clamp(0.0, sw);
      if (_dragX > sw * 0.5 && !_passedThreshold) {
        _passedThreshold = true;
        HapticFeedback.heavyImpact();
      }
    });
  }

  void _onDragEnd(DragEndDetails _) {
    if (_passedThreshold) {
      // Commit — navigate
      HapticFeedback.heavyImpact();
      setState(() {
        _dragX = 0;
        _isDragging = false;
        _passedThreshold = false;
      });
      _floatCtrl.repeat(reverse: true);
      _openDestination();
    } else {
      // Snap back with elastic
      HapticFeedback.lightImpact();
      _snapAnim = Tween<double>(begin: _dragX, end: 0).animate(
        CurvedAnimation(parent: _snapCtrl, curve: Curves.elasticOut),
      );
      _snapCtrl.forward(from: 0).then((_) {
        if (mounted) setState(() => _dragX = 0);
      });
      setState(() {
        _isDragging = false;
        _passedThreshold = false;
      });
      _floatCtrl.repeat(reverse: true);
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    final mq = MediaQuery.of(context);
    final maxTop = mq.size.height - mq.padding.bottom - 120.0;
    setState(() {
      _topOffset = ((_topOffset ?? mq.size.height * 0.35) + d.delta.dy)
          .clamp(0.0, maxTop);
    });
  }

  void _openDestination() {
    if (widget.tickets.length == 1) {
      widget.onTap(widget.tickets.first);
      return;
    }
    final colors = ref.read(themeProvider).colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _TicketPickerSheet(
        colors: colors,
        tickets: widget.tickets,
        peerName: widget.peerName,
        onSelect: widget.onTap,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (widget.tickets.isEmpty) return const SizedBox.shrink();

    final mq = MediaQuery.of(context);
    _topOffset ??= mq.size.height * 0.35;

    // Tab visual width (flush to right edge, pulled LEFT by _dragX)

    return Positioned(
      top: _topOffset,
      right: -_dragX, // negative = moves left as _dragX grows
      child: GestureDetector(
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        child: AnimatedBuilder(
          animation: Listenable.merge([_floatAnim, _snapCtrl]),
          builder: (_, child) {
            final floatOffset =
                _isDragging ? 0.0 : _floatAnim.value;
            final scaleX =
                1.0 + (_dragX / (mq.size.width * 2)).clamp(0.0, 0.15);
            return Transform.translate(
              offset: Offset(0, floatOffset),
              child: Transform.scale(
                alignment: Alignment.centerRight,
                scaleX: scaleX,
                child: child,
              ),
            );
          },
          child: _TabBody(
            count: widget.tickets.length,
            dragProgress:
                (_dragX / (MediaQuery.of(context).size.width * 0.5))
                    .clamp(0.0, 1.0),
          ),
        ),
      ),
    );
  }
}

// ── Tab body (the pill itself) ────────────────────────────────────────────────
class _TabBody extends StatelessWidget {
  final int count;
  final double dragProgress; // 0–1
  const _TabBody({required this.count, required this.dragProgress});

  static const _amber = Color(0xFFF59E0B);
  static const _dark = Color(0xFF0E1116);

  @override
  Widget build(BuildContext context) {
    // Tab glows brighter as user pulls more
    final glowOpacity = 0.25 + dragProgress * 0.5;
    return Container(
      decoration: BoxDecoration(
        color: _amber,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
        boxShadow: [
          BoxShadow(
            color: _amber.withValues(alpha: glowOpacity),
            blurRadius: 18 + dragProgress * 12,
            spreadRadius: -2,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      padding: const EdgeInsets.only(left: 8, right: 4, top: 14, bottom: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            dragProgress > 0.4
                ? Icons.arrow_back_ios_rounded
                : Icons.lock_rounded,
            color: _dark,
            size: 14,
          ),
          const SizedBox(height: 6),
          RotatedBox(
            quarterTurns: 1,
            child: Text(
              count == 1 ? 'ACTIVE DEAL' : '$count DEALS',
              style: const TextStyle(
                color: _dark,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Multi-ticket picker sheet ─────────────────────────────────────────────────
class _TicketPickerSheet extends StatelessWidget {
  final AzamanColors colors;
  final List<Ticket> tickets;
  final String peerName;
  final ValueChanged<Ticket> onSelect;

  const _TicketPickerSheet({
    required this.colors,
    required this.tickets,
    required this.peerName,
    required this.onSelect,
  });

  Color _statusColor(TicketStatus s) => switch (s) {
        TicketStatus.open => const Color(0xFFF59E0B),
        TicketStatus.closed => const Color(0xFF22C55E),
        TicketStatus.cancelled => const Color(0xFFEF4444),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.lock_rounded, color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 8),
              Text(
                'Active Deals with $peerName',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...tickets.map((t) {
            final sc = _statusColor(t.status);
            return GestureDetector(
              onTap: () {
                Navigator.pop(context);
                onSelect(t);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.divider),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: sc, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.name,
                              style: TextStyle(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(
                            '${t.targetAmount.toStringAsFixed(2)} ${t.targetCurrency}  ·  ${t.type.label}',
                            style: TextStyle(
                                color: colors.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        color: colors.textTertiary, size: 18),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
