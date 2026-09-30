// lib/widgets/offline_hairline.dart
// =============================================================================
// OFFLINE HAIRLINE  (TASK-023)
//
// 24px tall, edge-to-edge, no shadow, no icon, no card. It changes colour and
// nothing else moves — the app never re-lays out because the radio dropped.
//
// Why: the previous banner was a floating pill with a 35%-alpha glow that sat on
// top of content. A premium app states the truth quietly and keeps working.
// =============================================================================

import 'package:flutter/material.dart';

class OfflineHairline extends StatelessWidget {
  final bool offline;
  final bool justReconnected;

  const OfflineHairline({
    super.key,
    required this.offline,
    this.justReconnected = false,
  });

  /// 24 logical pixels: tall enough to read, too short to be a bar.
  static const double height = 24;

  @override
  Widget build(BuildContext context) {
    final bool visible = offline || justReconnected;
    final Color background = offline
        ? const Color(0xFFFFF3D6)
        : const Color(0xFFDFF5E6);
    final Color foreground = offline
        ? const Color(0xFF7A5B00)
        : const Color(0xFF0B5B33);
    final String label =
        offline ? 'Offline — showing your last update' : 'Back online';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: visible ? height : 0,
      width: double.infinity,
      color: visible ? background : Colors.transparent,
      alignment: Alignment.center,
      child: ClipRect(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: visible ? 1 : 0,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
