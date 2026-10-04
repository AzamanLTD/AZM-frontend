// =============================================================================
// AZAMAN — STORY VIEWER: PROGRESS BAR
//
// One segment per story in the active creator's group. Reads the playback
// controller's AnimationController via AnimatedBuilder so the segments tick
// without rebuilding the page (Overhaul 05 §4.1).
// =============================================================================

import 'package:flutter/material.dart';

class StoryProgressBar extends StatelessWidget {
  const StoryProgressBar({
    super.key,
    required this.count,
    required this.index,
    required this.progress,
    required this.boosted,
  });

  final int count;
  final int index;
  final Animation<double> progress;
  final bool boosted;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: progress,
            builder: (_, __) => Row(
              children: [
                for (var i = 0; i < count; i++) ...[
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        value: i < index
                            ? 1
                            : (i == index ? progress.value : 0),
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation(
                            boosted ? Colors.amberAccent : Colors.white),
                      ),
                    ),
                  ),
                  if (i < count - 1) const SizedBox(width: 3),
                ],
              ],
            ),
          ),
        ),
      );
}
