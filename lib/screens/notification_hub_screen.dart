import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/models/notification_model.dart';
import 'package:azaman/services/notification_action_dispatcher.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';

({IconData icon, Color color}) _notifStyle(
  NotificationCategory category,
  AzamanColors colors,
) {
  switch (category) {
    case NotificationCategory.securityAccount:
      return (icon: HugeIconsSolid.lockKey, color: colors.danger);
    case NotificationCategory.vendorPriority:
      return (icon: HugeIconsSolid.store01, color: colors.success);
    case NotificationCategory.adminSystem:
    case NotificationCategory.system:
      return (icon: HugeIconsSolid.shield01, color: colors.textTertiary);
    case NotificationCategory.money:
      return (
        icon: HugeIconsSolid.moneyReceiveFlow01,
        color: const Color(0xFFFFD700),
      );
    case NotificationCategory.social:
      return (icon: HugeIconsSolid.userGroup, color: const Color(0xFF9C59FF));
    case NotificationCategory.chat:
      return (icon: HugeIconsSolid.message01, color: const Color(0xFF3B97F7));
    case NotificationCategory.general:
      return (icon: HugeIconsSolid.notification01, color: colors.accent);
  }
}

class NotificationHubScreen extends ConsumerStatefulWidget {
  const NotificationHubScreen({super.key});

  @override
  ConsumerState<NotificationHubScreen> createState() =>
      _NotificationHubScreenState();
}

class _NotificationHubScreenState extends ConsumerState<NotificationHubScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  static const int _tabCount =
      6; // All / Money / Security / Social / Chat / System
  bool _markingAllRead = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final allNotifications = ref.watch(notificationProvider);
    final unreadCount = ref.watch(unreadCountProvider);

    // Derived category lists
    final moneyNotifs = allNotifications
        .where((n) => n.category == NotificationCategory.money)
        .toList();
    final securityNotifs = allNotifications
        .where((n) => n.category == NotificationCategory.securityAccount)
        .toList();
    final socialNotifs = allNotifications
        .where((n) => n.category == NotificationCategory.social)
        .toList();
    final chatNotifs = allNotifications
        .where((n) => n.category == NotificationCategory.chat)
        .toList();
    final systemNotifs = allNotifications
        .where(
          (n) =>
              n.category == NotificationCategory.system ||
              n.category == NotificationCategory.adminSystem ||
              n.category == NotificationCategory.vendorPriority,
        )
        .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
          56 + MediaQuery.of(context).padding.top + 48,
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: AppBar(
              title: Text(
                'Notifications',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              backgroundColor: colors.surface.withValues(alpha: 0.7),
              elevation: 0,
              iconTheme: IconThemeData(color: colors.textPrimary),
              actions: [
                if (unreadCount > 0)
                  _MarkAllReadAction(
                    colors: colors,
                    busy: _markingAllRead,
                    onTap: _onMarkAllRead,
                  ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: _buildTabBar(
                  colors,
                  allNotifications.length,
                  moneyNotifs.length,
                  securityNotifs.length,
                  socialNotifs.length,
                  chatNotifs.length,
                  systemNotifs.length,
                ),
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildNotificationList(context, colors, allNotifications),
          _buildNotificationList(context, colors, moneyNotifs),
          _buildNotificationList(context, colors, securityNotifs),
          _buildNotificationList(context, colors, socialNotifs),
          _buildNotificationList(context, colors, chatNotifs),
          _buildNotificationList(context, colors, systemNotifs),
        ],
      ),
    );
  }

  Future<void> _onMarkAllRead() async {
    if (_markingAllRead) return;
    setState(() => _markingAllRead = true);
    AzamanHaptics.confirm();

    final updated = await ref
        .read(notificationProvider.notifier)
        .markAllAsRead();

    if (!mounted) return;
    setState(() => _markingAllRead = false);

    final colors = ref.read(themeProvider).colors;
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "Couldn't reach the server. We'll retry next time you open this screen.",
          ),
          backgroundColor: colors.danger,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (updated > 0) {
      AzamanHaptics.commit();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Marked $updated notification${updated == 1 ? '' : 's'} as read.',
          ),
          backgroundColor: colors.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildTabBar(
    AzamanColors colors,
    int allCount,
    int moneyCount,
    int securityCount,
    int socialCount,
    int chatCount,
    int systemCount,
  ) {
    final tabs = [
      ('All', allCount, Icons.notifications_outlined),
      ('Money', moneyCount, Icons.monetization_on_outlined),
      ('Security', securityCount, Icons.security_outlined),
      ('Social', socialCount, Icons.people_outline),
      ('Chat', chatCount, Icons.chat_bubble_outline),
      ('System', systemCount, Icons.info_outline),
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final tab = tabs[i];
          final isSelected = _tabController.index == i;
          return GestureDetector(
            onTap: () {
              AzamanHaptics.toggle();
              setState(() => _tabController.animateTo(i));
            },
            child: AnimatedContainer(
              duration: 250.ms,
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected ? colors.accent : colors.softSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? colors.accent : colors.divider,
                  width: isSelected ? 1.5 : 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    tab.$3,
                    size: 13,
                    color: isSelected ? Colors.white : colors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    tab.$1,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : colors.textSecondary,
                    ),
                  ),
                  if (tab.$2 > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.3)
                            : colors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${tab.$2}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: isSelected ? Colors.white : colors.accent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationList(
    BuildContext context,
    AzamanColors colors,
    List<AppNotification> notifications,
  ) {
    if (notifications.isEmpty) {
      return _premiumEmptyState(colors);
    }

    // Group by date
    final groups = <String, List<AppNotification>>{};
    for (final n in notifications) {
      final key = _dateGroupKey(n.createdAt);
      groups.putIfAbsent(key, () => []).add(n);
    }

    return AzPullToRefresh(
      color: colors.accent,
      onRefresh: () => ref.read(notificationProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: groups.length,
        itemBuilder: (context, groupIndex) {
          final entry = groups.entries.elementAt(groupIndex);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date header
              Padding(
                padding: EdgeInsets.only(
                  top: groupIndex > 0 ? 20.0 : 0.0,
                  bottom: 10.0,
                ),
                child: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colors.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
              ).animate().fadeIn(duration: 200.ms),
              // Notification tiles
              ...entry.value.map((n) => _premiumNotificationTile(n, colors)),
            ],
          );
        },
      ),
    );
  }

  String _dateGroupKey(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final date = DateTime(dt.year, dt.month, dt.day);
    if (date == today) return 'TODAY';
    if (date == yesterday) return 'YESTERDAY';
    return '${dt.day} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][dt.month - 1]}';
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _premiumEmptyState(AzamanColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated bell icon
          Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: colors.accentSurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications_none_rounded,
                  size: 36,
                  color: colors.accent,
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                begin: const Offset(1, 1),
                end: const Offset(1.05, 1.05),
                duration: 1500.ms,
                curve: Curves.easeInOut,
              ),
          const SizedBox(height: 16),
          Text(
            'All caught up!',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'You have no unread notifications',
            style: TextStyle(fontSize: 13, color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _premiumNotificationTile(AppNotification notif, AzamanColors colors) {
    final style = _notifStyle(notif.category, colors);

    return Dismissible(
          key: ValueKey(notif.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: colors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.delete_outline_rounded,
              color: colors.danger,
              size: 22,
            ),
          ),
          confirmDismiss: (_) async {
            AzamanHaptics.warn();
            ref.read(notificationProvider.notifier).markAsRead(notif.id);
            // Note: Full delete not in scope currently, this marks read or triggers action
            return true;
          },
          child: GestureDetector(
            onTap: () {
              AzamanHaptics.nav();
              ref.read(notificationProvider.notifier).markAsRead(notif.id);
              _navigateFromNotification(context, notif);
            },
            child: PremiumGlassContainer(
              blur: 8,
              opacity: notif.isRead ? 0.03 : 0.06,
              borderRadius: 14,
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 8),
              enableShadow: false,
              border: Border.all(
                color: notif.isRead
                    ? colors.divider
                    : colors.accent.withValues(alpha: 0.15),
                width: notif.isRead ? 0.5 : 1,
              ),
              child: Row(
                children: [
                  // Category icon with glow
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: style.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: notif.isRead
                          ? null
                          : [
                              BoxShadow(
                                color: style.color.withValues(alpha: 0.1),
                                blurRadius: 8,
                              ),
                            ],
                    ),
                    child: Icon(style.icon, color: style.color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                notif.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: notif.isRead
                                      ? FontWeight.w600
                                      : FontWeight.w800,
                                ),
                              ),
                            ),
                            if (!notif.isRead) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: colors.accent,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: colors.accent.withValues(
                                        alpha: 0.4,
                                      ),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          notif.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formatTimeAgo(notif.createdAt),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colors.textTertiary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(delay: 50.ms, duration: 250.ms)
        .slideX(begin: 0.1, end: 0, delay: 50.ms, duration: 250.ms);
  }

  void _navigateFromNotification(
    BuildContext context,
    AppNotification notification,
  ) {
    final action = NotificationActionDispatcher.resolve(
      notification.actionPayload,
    );
    if (action.resolution != NotificationActionResolution.navigable) {
      // REVIEW 4.1 — informational payloads and unsupported actions tell
      // the truth here too: nothing opens, nothing pretends to succeed.
      if (action.resolution == NotificationActionResolution.unsupportedAction) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("This notification's action isn't available yet."),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    final route = action.route!;

    // BUGFIX (2026-05-31): navigation uses `context.push` (not `context.go`)
    // so the imperative MainWrapper stack survives the deep-link and back
    // pops to a live screen.
    void deepLink() {
      final router = GoRouter.of(context);
      // Close the notification hub first so the back-stack ends up as
      // [MainWrapper → destination], not [MainWrapper → NotificationHub
      // → destination].
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      // Defer the push to the next frame so the pop above completes first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        router.push(route);
      });
    }

    deepLink();
  }
}

// =============================================================================
// Local presentation helpers
// =============================================================================

class _MarkAllReadAction extends StatelessWidget {
  final AzamanColors colors;
  final bool busy;
  final VoidCallback onTap;

  const _MarkAllReadAction({
    required this.colors,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton.icon(
        onPressed: busy ? null : onTap,
        icon: busy
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(colors.accent),
                ),
              )
            : Icon(
                HugeIconsSolid.checkmarkCircle01,
                size: 18,
                color: colors.accent,
              ),
        label: Text(
          'Mark all read',
          style: TextStyle(
            color: busy ? colors.textTertiary : colors.accent,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

// Removed _NotificationTile as it is replaced by _premiumNotificationTile
