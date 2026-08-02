import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/notification_overlay.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final generalUnread = ref.watch(unreadCountProvider);
    final bizUnread = ref.watch(bizUnreadCountProvider);
    final hasBiz = ref.watch(myBusinessProvider).profile != null;

    // Combined unread count — general notifications + business owner
    // notifications (new orders, KYB updates, etc.) so the badge reflects
    // everything the user needs to see at a glance.
    final unread = generalUnread + (hasBiz ? bizUnread : 0);

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

            // Pulsing badge — combined count
            if (unread > 0)
              Positioned(
                top: 6, right: 6,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: 800.ms,
                  curve: Curves.easeInOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
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
                              color: colors.danger.withValues(alpha: 0.4 * value),
                              blurRadius: 6 * value,
                              spreadRadius: 1 * value,
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
                ).animate(onPlay: (c) => c.repeat(reverse: true)),
              ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}
