// =============================================================================
// DRAWER PEEK HINT — First-time affordance for the settings `endDrawer`
//
// The SettingsDrawer (Root Access / Profile / Worker portal / etc.) only had
// one way in: an edge-swipe-from-right gesture with zero visual cue that it
// existed. This widget teaches the user it's there, once, on first load:
// a small handle at the right edge of the screen peeks/pulls into view and
// springs back out a few times, each pull smaller than the last — like a
// gentle knock — then fades away and never shows again (persisted via
// SharedPreferences, same pattern as TapHintOverlay).
//
// Tapping the handle at any time opens the drawer immediately and dismisses
// the hint for good.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kHasSeenDrawerPeekHintKey = 'has_seen_drawer_peek_hint';

class DrawerPeekHint extends StatefulWidget {
  /// Opens the actual endDrawer — pass `() => scaffoldKey.currentState?.openEndDrawer()`.
  final VoidCallback onOpenDrawer;

  const DrawerPeekHint({super.key, required this.onOpenDrawer});

  @override
  State<DrawerPeekHint> createState() => _DrawerPeekHintState();
}

class _DrawerPeekHintState extends State<DrawerPeekHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _show = false;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _checkIfShouldShow();
  }

  Future<void> _checkIfShouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_kHasSeenDrawerPeekHintKey) ?? false;
    if (!seen && mounted) {
      // Small delay so it doesn't compete with the balance-card tap hint
      // that fires at the same moment the home screen mounts.
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() => _show = true);
      await _ctrl.forward();
      _dismiss();
    }
  }

  Future<void> _dismiss() async {
    if (_dismissing || !_show) return;
    _dismissing = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHasSeenDrawerPeekHintKey, true);
    if (mounted) setState(() => _show = false);
  }

  void _handleTap() {
    widget.onOpenDrawer();
    _dismiss();
  }

  /// Decaying oscillation: 0 at rest, swells out into a few diminishing
  /// pulls, and settles back to 0. Each successive peak is smaller than
  /// the last, exactly like a knock that trails off.
  double _pullAmount(double t) {
    final decay = math.exp(-4.2 * t);
    final osc = math.sin(t * math.pi * 5.0);
    return decay * osc.clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFF00D97E) : const Color(0xFF00B364);

    return Positioned(
      right: 0,
      top: MediaQuery.of(context).size.height * 0.40,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final pull = _pullAmount(_ctrl.value);
          // 0 -> mostly hidden past the edge; 1 -> pulled ~30px into view.
          final dx = -30.0 * pull;
          return Transform.translate(
            offset: Offset(dx, 0),
            child: GestureDetector(
              onTap: _handleTap,
              child: Container(
                width: 22,
                height: 58,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.85),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.35 * (0.4 + pull)),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.chevron_left,
                  color: isDark ? Colors.black87 : Colors.white,
                  size: 18,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
