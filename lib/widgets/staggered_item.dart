// =============================================================================
// AZAMAN — STAGGERED LIST ENTRANCE  (Phase 13)
//
// Wraps any ListView/GridView item build with a per-index stagger so
// list items fade+slide in with a cascade on first appearance.
//
// Respects reduced-motion: when MediaQuery.disableAnimations is true,
// items appear instantly with no stagger.
//
// Usage:
//   ListView.builder(
//     itemCount: items.length,
//     itemBuilder: (context, index) {
//       return StaggeredItem(
//         index: index,
//         child: MyListTile(item: items[index]),
//       );
//     },
//   )
// =============================================================================

import 'package:flutter/material.dart';
import 'package:azaman/theme/motion_tokens.dart';

class StaggeredItem extends StatefulWidget {
  final int index;
  final Widget child;
  final Duration? staggerStep;

  const StaggeredItem({
    super.key,
    required this.index,
    required this.child,
    this.staggerStep,
  });

  @override
  State<StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<StaggeredItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: MotionTokens.standard,
    );

    _fade = CurvedAnimation(parent: _ctrl, curve: MotionTokens.enter);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: MotionTokens.enter));

    // Delay based on index — but cap at 6 items so long lists don't wait
    final step = widget.staggerStep ?? MotionTokens.staggerStep;
    final delay = step * (widget.index.clamp(0, 6));

    Future.delayed(delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return widget.child;
    }

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
