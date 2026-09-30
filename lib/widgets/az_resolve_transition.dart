// Skeleton content arrives once, in draw order. Timing belongs to MotionTokens.
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/utils/azaman_haptics.dart';

enum AzResolvePhase { loading, resolved }

class AzResolveTransition extends StatefulWidget {
  final Widget child;
  final int index;
  final AzResolvePhase phase;
  final bool skipEntrance;
  final bool announce;

  const AzResolveTransition({
    super.key,
    required this.child,
    required this.phase,
    this.index = 0,
    this.skipEntrance = false,
    this.announce = false,
  });

  @override
  State<AzResolveTransition> createState() => _AzResolveTransitionState();
}

class _AzResolveTransitionState extends State<AzResolveTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _stagger;
  int _generation = 0;
  bool _arrived = false;
  bool _announced = false;
  bool _reducedVisible = false;
  bool? _reducedMotion;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: MotionTokens.emphasized,
      value: widget.skipEntrance && widget.phase == AzResolvePhase.resolved
          ? 1
          : 0,
    );
    _reducedVisible = _controller.value == 1;
    _scheduleArrival();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = !AzMotion.of(context).travel;
    if (_reducedMotion != reduced) {
      _reducedMotion = reduced;
      _scheduleArrival();
    }
  }

  @override
  void didUpdateWidget(covariant AzResolveTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase ||
        oldWidget.skipEntrance != widget.skipEntrance ||
        oldWidget.index != widget.index) {
      _scheduleArrival();
    }
  }

  void _scheduleArrival() {
    final generation = ++_generation;
    _stagger?.cancel();
    if (widget.phase == AzResolvePhase.loading) {
      _controller.stop();
      _controller.value = 0;
      _reducedVisible = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _generation ||
          widget.phase != AzResolvePhase.resolved) {
        return;
      }
      if (widget.skipEntrance || _arrived) {
        _controller.value = 1;
        setState(() => _reducedVisible = true);
        return;
      }
      if (!AzMotion.of(context).travel) {
        _arrive(reduced: true);
      } else if (MotionTokens.staggerDelay(widget.index) == Duration.zero) {
        _arrive(reduced: false);
      } else {
        _stagger = Timer(MotionTokens.staggerDelay(widget.index), () {
          if (mounted &&
              generation == _generation &&
              widget.phase == AzResolvePhase.resolved) {
            _arrive(reduced: false);
          }
        });
      }
    });
  }

  void _arrive({required bool reduced}) {
    _arrived = true;
    if (widget.announce && widget.index == 0 && !_announced) {
      _announced = true;
      AzamanHaptics.success();
    }
    if (reduced) {
      _controller.value = 1;
      setState(() => _reducedVisible = true);
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    ++_generation;
    _stagger?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolved = widget.phase == AzResolvePhase.resolved;
    final skip = resolved && widget.skipEntrance;
    return IgnorePointer(
      ignoring: !resolved,
      child: ExcludeSemantics(
        excluding: !resolved,
        child: !AzMotion.of(context).travel
            ? AnimatedOpacity(
                duration: widget.skipEntrance
                    ? Duration.zero
                    : MotionTokens.control,
                opacity: resolved && (_reducedVisible || skip) ? 1 : 0,
                child: widget.child,
              )
            : AnimatedBuilder(
                animation: _controller,
                child: widget.child,
                builder: (context, child) {
                  final t = !resolved
                      ? 0.0
                      : skip
                      ? 1.0
                      : MotionTokens.enter.transform(_controller.value);
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, (1 - t) * 6),
                      child: child,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
