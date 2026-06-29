import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/models/notification_model.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class NotificationOverlay extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const NotificationOverlay({super.key, required this.onClose});

  static void show(BuildContext context) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => NotificationOverlay(
        onClose: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  @override
  ConsumerState<NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends ConsumerState<NotificationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnim;
  int _selectedTab = 0;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutQuart,
    ));
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  void _dismiss() {
    _slideController.reverse().then((_) => widget.onClose());
  }

  bool _matchesTab(AppNotification n, int tab) {
    switch (tab) {
      case 0: return true; // ALL
      case 1: // MONEY
        if (n.category == NotificationCategory.general) {
          final t = n.title.toLowerCase();
          if (t.contains('deposit') || t.contains('withdraw') || t.contains('transfer') || t.contains('payment')) return true;
        }
        return false;
      case 2: // SOCIAL
        return n.category == NotificationCategory.general;
      case 3: // SECURITY
        return n.category == NotificationCategory.securityAccount;
      case 4: // SYSTEM
        return n.category == NotificationCategory.adminSystem || n.category == NotificationCategory.vendorPriority;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final all = ref.watch(generalNotificationsProvider);
    final security = ref.watch(securityNotificationsProvider);
    final vendor = ref.watch(vendorNotificationsProvider);

    final allNotifications = [...all, ...security, ...vendor]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final unread = allNotifications.where((n) => !n.isRead).toList();
    final filtered = _selectedTab == 0
        ? allNotifications
        : allNotifications.where((n) => _matchesTab(n, _selectedTab)).toList();

    final screenHeight = MediaQuery.of(context).size.height;
    final overlayHeight = screenHeight * 0.92;

    return GestureDetector(
      onVerticalDragUpdate: (d) {
        setState(() => _dragOffset += d.primaryDelta!);
      },
      onVerticalDragEnd: (d) {
        if (d.primaryVelocity != null && d.primaryVelocity! < -500) {
          _dismiss();
        } else if (_dragOffset > 60) {
          _dismiss();
        } else {
          setState(() => _dragOffset = 0);
        }
      },
      child: Stack(
        children: [
          GestureDetector(
            onTap: _dismiss,
            child: Container(color: Colors.transparent),
          ),
          AnimatedBuilder(
            animation: _slideAnim,
            builder: (_, __) {
              final offset = _dragOffset != 0
                  ? Offset(0, _dragOffset / screenHeight)
                  : _slideAnim.value;
              return Transform.translate(
                offset: Offset(0, offset.dy * screenHeight),
                child: SizedBox(
                  height: overlayHeight,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(24),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: Container(
                        decoration: BoxDecoration(
                          color: colors.isDark
                            ? Colors.black.withOpacity(0.72)
                            : Colors.white.withOpacity(0.68),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(24)),
                        ),
                        child: Column(
                          children: [
                            // Handle
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                children: [
                                  Container(
                                    width: 40, height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'swipe up to close',
                                    style: TextStyle(
                                      color: colors.isDark
                                        ? Colors.white.withOpacity(0.5)
                                        : Colors.black.withOpacity(0.4),
                                      fontSize: 10,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Tab pills
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  'ALL', 'MONEY', 'SOCIAL', 'SECURITY', 'SYSTEM',
                                ].asMap().entries.map((e) {
                                  final i = e.key;
                                  final label = e.value;
                                  final isSelected = _selectedTab == i;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: GestureDetector(
                                      onTap: () => setState(() => _selectedTab = i),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? colors.accent
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(14),
                                          border: isSelected
                                              ? null
                                              : Border.all(
                                                  color: colors.textTertiary.withOpacity(0.3),
                                                ),
                                        ),
                                        child: Text(
                                          label,
                                          style: TextStyle(
                                            color: isSelected
                                                ? Colors.white
                                                : colors.textTertiary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            // Unread strip
                            if (unread.isNotEmpty)
                              Container(
                                height: 40,
                                margin: const EdgeInsets.only(top: 8),
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  children: unread.take(10).map((n) {
                                    return Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.accent.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            HugeIconsSolid.notification01,
                                            size: 14,
                                            color: colors.accent,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            n.title.length > 20
                                                ? '${n.title.substring(0, 20)}…'
                                                : n.title,
                                            style: TextStyle(
                                              color: colors.accent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            // Notifications list
                            Expanded(
                              child: filtered.isEmpty
                                  ? Center(
                                      child: Text(
                                        'No notifications',
                                        style: TextStyle(
                                          color: colors.textTertiary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8,
                                      ),
                                      itemCount: filtered.length,
                                      itemBuilder: (_, i) {
                                        final n = filtered[i];
                                        return _NotificationItem(
                                          notification: n,
                                          colors: colors,
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NotificationItem extends StatelessWidget {
  final AppNotification notification;
  final AzamanColors colors;

  const _NotificationItem({
    required this.notification,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: notification.isRead
            ? Colors.transparent
            : colors.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6, height: 6,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: notification.isRead
                  ? Colors.transparent
                  : colors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  notification.body,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            HugeIconsSolid.arrowRight01,
            color: colors.textTertiary,
            size: 14,
          ),
        ],
      ),
    );
  }
}
