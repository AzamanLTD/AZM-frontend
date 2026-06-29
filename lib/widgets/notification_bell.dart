import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/notification_overlay.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    final colors = ref.watch(themeProvider).colors;

    return GestureDetector(
      onTap: () => NotificationOverlay.show(context),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            HugeIconsSolid.notification01,
            color: colors.textPrimary,
            size: 22,
          ),
          if (unread > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.danger,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
