// lib/widgets/trade_countdown_chip.dart
// =============================================================================
// TRADE COUNTDOWN CHIP — P2P Premium Sprint (2026-06-21)
//
// A live countdown chip showing time remaining on an active trade.
// Colors transition: green → amber → red as the deadline approaches.
// Used on TradesTabScreen active trade cards.
//
// Usage:
//   TradeCountdownChip(deadlineUtcMs: trade['deadlineUtcMs'])
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';

class TradeCountdownChip extends StatefulWidget {
  /// Unix timestamp in milliseconds (UTC) when the trade expires.
  final int? deadlineUtcMs;

  const TradeCountdownChip({super.key, required this.deadlineUtcMs});

  @override
  State<TradeCountdownChip> createState() => _TradeCountdownChipState();
}

class _TradeCountdownChipState extends State<TradeCountdownChip> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _update() {
    if (!mounted) return;
    final dl = widget.deadlineUtcMs;
    if (dl == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = dl - now;
    setState(() => _remaining =
        diff > 0 ? Duration(milliseconds: diff) : Duration.zero);
  }

  @override
  Widget build(BuildContext context) {
    final expired = _remaining == Duration.zero;
    final minutes = _remaining.inMinutes;
    final Color bg;
    final Color text;
    if (expired) {
      bg = Colors.red.withValues(alpha: 0.15);
      text = Colors.red;
    } else if (minutes < 5) {
      bg = Colors.red.withValues(alpha: 0.15);
      text = Colors.red;
    } else if (minutes < 15) {
      bg = Colors.amber.withValues(alpha: 0.15);
      text = Colors.amber.shade800;
    } else {
      bg = Colors.green.withValues(alpha: 0.12);
      text = Colors.green.shade700;
    }
    final label = expired
        ? 'Expired'
        : '${_remaining.inMinutes.toString().padLeft(2, '0')}:'
            '${(_remaining.inSeconds % 60).toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 12, color: text),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: text,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
