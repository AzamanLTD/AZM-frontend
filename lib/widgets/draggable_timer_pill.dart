import 'package:flutter/material.dart';
import 'package:azaman/providers/theme_provider.dart';


class DraggableTimerPill extends StatefulWidget {
  final int secondsRemaining;
  final bool isExpired;
  final bool isDisputed;
  final AzamanColors colors;
  final GlobalKey pillKey;

  const DraggableTimerPill({
    super.key,
    required this.secondsRemaining,
    required this.isExpired,
    required this.isDisputed,
    required this.colors,
    required this.pillKey,
  });

  @override
  State<DraggableTimerPill> createState() => _DraggableTimerPillState();
}

class _DraggableTimerPillState extends State<DraggableTimerPill> {
  double _dx = 0.0;
  double _dy = 0.0;

  @override
  Widget build(BuildContext context) {
    final String timeStr = widget.isExpired
        ? "EXPIRED"
        : "${(widget.secondsRemaining ~/ 60).toString().padLeft(2, '0')}:${(widget.secondsRemaining % 60).toString().padLeft(2, '0')}";

    final Color accent = widget.isDisputed
        ? widget.colors.danger
        : (widget.isExpired ? widget.colors.danger : widget.colors.accent);

    return Positioned(
      left: _dx,
      top: _dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _dx += details.delta.dx;
            _dy += details.delta.dy;
          });
        },
        child: Container(
          key: widget.pillKey,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: widget.colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withValues(alpha: 0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isExpired || widget.isDisputed
                    ? Icons.access_time
                    : Icons.access_time,
                size: 14,
                color: accent,
              ),
              const SizedBox(width: 6),
              Text(
                timeStr,
                style: TextStyle(
                  color: widget.isExpired
                      ? widget.colors.danger
                      : widget.colors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
