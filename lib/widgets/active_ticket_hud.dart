// =============================================================================
// ACTIVE TICKET HUD  (2026-07-11)
//
// A draggable vertical pill that floats on the right edge of the chat screen
// whenever there is at least one open ticket in the friendship.
//
// Behaviour:
//   • Positioned on the right edge, vertically draggable (Y-axis only)
//   • Tapping it opens a compact bottom sheet showing the active ticket details
//   • Hidden automatically when there are no open tickets
//
// Usage — wrap the chat screen body in a Stack, then add this widget:
//
//   Stack(
//     children: [
//       ChatBody(...),
//       ActiveTicketHud(
//         tickets: openTickets,
//         peerName: widget.contactName,
//         onTap: _openTicketWorkspace,
//       ),
//     ],
//   )
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:azaman/services/ticket_service.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ActiveTicketHud extends ConsumerStatefulWidget {
  final List<Ticket> tickets;
  final String peerName;

  /// Called when the user taps the HUD or selects a ticket from the sheet.
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
    with SingleTickerProviderStateMixin {
  // Vertical offset from top of the safe area (initialised in build to 35% of screen)
  double? _topOffset;
  bool _initialised = false;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails d, double maxTop) {
    setState(() {
      _topOffset = ((_topOffset ?? 200) + d.delta.dy)
          .clamp(0.0, maxTop);
    });
  }

  void _showSheet(BuildContext context) {
    HapticFeedback.mediumImpact();
    final colors = ref.read(themeProvider).colors;

    if (widget.tickets.length == 1) {
      widget.onTap(widget.tickets.first);
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    if (widget.tickets.isEmpty) return const SizedBox.shrink();

    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    if (!_initialised) {
      _topOffset = screenH * 0.35;
      _initialised = true;
    }
    final maxTop = screenH - mq.padding.bottom - 120.0;

    return Positioned(
      top: _topOffset!,
      right: 0,
      child: GestureDetector(
        onPanUpdate: (d) => _onPanUpdate(d, maxTop),
        onTap: () => _showSheet(context),
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) => Transform.scale(
            alignment: Alignment.centerRight,
            scale: _pulseAnim.value,
            child: child,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B), // amber — "active deal" signal
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(16)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                  blurRadius: 14,
                  spreadRadius: -2,
                  offset: const Offset(-2, 0),
                ),
              ],
            ),
            padding:
                const EdgeInsets.only(left: 10, right: 6, top: 12, bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded,
                    color: Color(0xFF0E1116), size: 16),
                const SizedBox(height: 6),
                // Rotated "DEAL" label
                RotatedBox(
                  quarterTurns: 1,
                  child: Text(
                    widget.tickets.length == 1
                        ? 'ACTIVE DEAL'
                        : '${widget.tickets.length} DEALS',
                    style: const TextStyle(
                      color: Color(0xFF0E1116),
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bottom sheet shown when there are multiple active tickets ─────────────────
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
          // Handle
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
              Icon(Icons.lock_rounded, color: const Color(0xFFF59E0B), size: 18),
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
