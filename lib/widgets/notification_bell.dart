import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/widgets/notification_overlay.dart';
import 'package:azaman/utils/azaman_haptics.dart';

/// Notification bell with a ONE-SHOT attention animation (milestone
/// 2026-09-30). The old version ran an infinite `.repeat(reverse: true)`
/// pulse while unread > 0 — verified animation debt. Behavioral rule now:
///
///   unread == 0            → no attention animation
///   unread 0 → positive    → one short attention pop, then settles
///   unread stays positive  → visually settled (no idle cycles)
///   unread returns to 0     → settled
///
/// No timers, no infinite loops. The controller rests at its end value
/// (scale 1.0), and reduced motion removes the pop entirely via
/// [MotionTokens.accessibleDuration].
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _attention;
  int _lastUnread = 0;

  @override
  void initState() {
    super.initState();
    // Default duration is replaced at fire time with the accessible
    // duration (MediaQuery cannot be read inside initState).
    _attention = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 1.0, // rested = settled (scale 1.0)
    );
  }

  @override
  void dispose() {
    _attention.dispose();
    super.dispose();
  }

  /// Fires the one-shot pop ONLY on the 0 → positive transition.
  void _maybeFireAttention(int unread) {
    if (unread > 0 && _lastUnread == 0) {
      // Existing animation policy: reduced motion collapses the duration
      // to zero, which here means "no pop at all" — the badge appears
      // already settled.
      _attention.duration = MotionTokens.accessibleDuration(
          context, const Duration(milliseconds: 420));
      if (_attention.duration == Duration.zero) {
        _attention.value = 1.0;
      } else {
        _attention.forward(from: 0);
      }
    }
    _lastUnread = unread;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final generalUnread = ref.watch(unreadCountProvider);
    final bizUnread = ref.watch(bizUnreadCountProvider);
    final hasBiz = ref.watch(myBusinessProvider).profile != null;

    // Combined unread count — general notifications + business owner
    // notifications (new orders, KYB updates, etc.) so the badge reflects
    // everything the user needs to see at a glance.
    final unread = generalUnread + (hasBiz ? bizUnread : 0);

    _maybeFireAttention(unread);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AzamanHaptics.nav();
        NotificationOverlay.show(context);
      },
      child: SizedBox(
        width: 40, height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Bell icon
            Icon(
              Icons.notifications_none_rounded,
              size: 22,
              color: colors.textSecondary,
            ),

            // Unread badge — one-shot pop on 0 → positive, then settled.
            if (unread > 0)
              Positioned(
                top: 6, right: 6,
                child: AnimatedBuilder(
                  animation: _attention,
                  builder: (context, _) {
                    // easeOutBack-style pop: overshoot then settle to 1.0.
                    final t = MotionTokens.spring.transform(_attention.value);
                    final scale = 1.0 + (1.35 - 1.0) * (1.0 - t);
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 16, minHeight: 16,
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: colors.danger,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colors.background,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors.danger.withValues(alpha: 0.4),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}
