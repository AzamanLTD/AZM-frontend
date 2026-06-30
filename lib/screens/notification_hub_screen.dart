import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/models/notification_model.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:hugeicons_pro/hugeicons.dart';


({IconData icon, Color color}) _notifStyle(
    NotificationCategory category, AzamanColors colors) {
  switch (category) {
    case NotificationCategory.securityAccount:
      return (icon: HugeIconsSolid.lockKey, color: colors.danger);
    case NotificationCategory.vendorPriority:
      return (icon: HugeIconsSolid.store01, color: colors.success);
    case NotificationCategory.adminSystem:
      return (icon: HugeIconsSolid.shield01, color: colors.textTertiary);
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

class _NotificationHubScreenState
    extends ConsumerState<NotificationHubScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  int _tabCount = 2;
  bool _markingAllRead = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final role = ref.watch(authProvider).user?.role ?? '';
    final isVendor = role.toUpperCase() == 'VENDOR';
    final tabCount = isVendor ? 3 : 2;

    if (tabCount != _tabCount) {
      _tabCount = tabCount;
      final oldIndex = _tabController.index.clamp(0, tabCount - 1);
      _tabController.dispose();
      _tabController = TabController(length: tabCount, vsync: this, initialIndex: oldIndex);
    }

    final generalNotifications = ref.watch(generalNotificationsProvider);
    final securityNotifications = ref.watch(securityNotificationsProvider);
    final vendorNotifications = ref.watch(vendorNotificationsProvider);
    final unreadCount = ref.watch(unreadCountProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('Notification Hub',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        backgroundColor: colors.surface,
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
            context, colors, isVendor,
            generalNotifications.length, securityNotifications.length, vendorNotifications.length,
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildNotificationList(context, colors, generalNotifications),
          _buildNotificationList(context, colors, securityNotifications),
          if (isVendor)
            _buildNotificationList(context, colors, vendorNotifications),
        ],
      ),
    );
  }

  Future<void> _onMarkAllRead() async {
    if (_markingAllRead) return;
    setState(() => _markingAllRead = true);
    AzamanHaptics.confirm();

    final updated = await ref.read(notificationProvider.notifier).markAllAsRead();

    if (!mounted) return;
    setState(() => _markingAllRead = false);

    final colors = ref.read(themeProvider).colors;
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Couldn't reach the server. We'll retry next time you open this screen."),
          backgroundColor: colors.danger,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (updated > 0) {
      AzamanHaptics.commit();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Marked $updated notification${updated == 1 ? '' : 's'} as read.'),
          backgroundColor: colors.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildTabBar(BuildContext context, AzamanColors colors, bool isVendor,
      int generalCount, int securityCount, int vendorCount) {
    return Container(
      color: colors.surface,
      child: TabBar(
        controller: _tabController,
        indicatorColor: colors.accent,
        indicatorWeight: 3,
        labelColor: colors.accent,
        unselectedLabelColor: colors.textTertiary,
        labelStyle:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 14),
        onTap: (_) => AzamanHaptics.toggle(),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('General'),
                const SizedBox(width: 6),
                _TabBadge(label: '$generalCount', color: colors.accent),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Security & Account'),
                const SizedBox(width: 6),
                _TabBadge(label: '$securityCount', color: colors.accent),
              ],
            ),
          ),
          if (isVendor)
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(HugeIconsStroke.store01, size: 16),
                  const SizedBox(width: 6),
                  const Text('Vendor Inbox'),
                  const SizedBox(width: 6),
                  _TabBadge(label: '$vendorCount', color: colors.success),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNotificationList(BuildContext context, AzamanColors colors,
      List<AppNotification> notifications) {
    // Pull-to-refresh works on every tab, even when the list is empty,
    // so users have a way to retry after a transient fetch failure.
    return RefreshIndicator(
      color: colors.accent,
      backgroundColor: colors.surface,
      onRefresh: () => ref.read(notificationProvider.notifier).refresh(),
      child: notifications.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(HugeIconsStroke.notification01,
                            size: 64, color: colors.textTertiary),
                        const SizedBox(height: 16),
                        Text(
                          'No notifications',
                          style: TextStyle(
                              color: colors.textTertiary,
                              fontSize: 16,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: notifications.length,
              separatorBuilder: (_, __) => Divider(
                  color: colors.divider, height: 1, indent: 72, endIndent: 16),
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return _NotificationTile(
                  notification: notification,
                  colors: colors,
                  onTap: () {
                    AzamanHaptics.nav();
                    ref
                        .read(notificationProvider.notifier)
                        .markAsRead(notification.id);
                    _navigateFromNotification(context, notification);
                  },
                );
              },
            ),
    );
  }

  void _navigateFromNotification(
      BuildContext context, AppNotification notification) {
    final payload = notification.actionPayload;
    if (payload == null) return;

    final action = payload['action']?.toString();

    // BUGFIX (2026-05-31): every case below used `context.go(...)` which
    // **replaces** the GoRouter location and clears the imperative
    // navigator stack. The Splash screen had earlier called
    // `Navigator.pushReplacement(MainWrapper)` — that imperative route is
    // wiped by `context.go`, so after deep-linking from a notification the
    // stack reduces to just the destination screen. Pressing back from
    // there has nothing underneath → blank screen.
    //
    // Switching to `context.push(...)` keeps MainWrapper (and this hub)
    // alive underneath the destination, so back-stack pops behave
    // correctly. The hub itself is closed before we deep-link so the user
    // doesn't see it momentarily after popping the trade screen.
    void deepLink(String route) {
      // Capture the root navigator and the GoRouter BEFORE popping so we
      // don't depend on this widget's context after it's been disposed.
      final router = GoRouter.of(context);

      // Close the notification hub first so the back-stack ends up as
      // [MainWrapper → destination], not [MainWrapper → NotificationHub
      // → destination]. Users almost never want to land back on the hub
      // after acting on a notification.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      // Defer the push to the next frame so the pop above completes
      // first and the destination cleanly stacks on MainWrapper.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        router.push(route);
      });
    }

    switch (action) {
      // ── Trade lifecycle ──────────────────────────────────────────────────
      case 'OPEN_TRADE':
      case 'PING_TOPUP':
        final tradeId = payload['tradeId']?.toString();
        if (tradeId != null && tradeId.isNotEmpty) {
          deepLink('/trade/$tradeId');
        }
        break;

      // ── Disputes ────────────────────────────────────────────────────────
      case 'OPEN_DISPUTE':
        final disputeId = payload['disputeId']?.toString();
        if (disputeId != null && disputeId.isNotEmpty) {
          deepLink('/dispute/$disputeId');
        }
        break;

      // ── Friends & DMs ───────────────────────────────────────────────────
      case 'OPEN_FRIEND_REQUEST':
      case 'OPEN_FRIEND_CHAT':
      case 'OPEN_FRIEND_TRANSFER_REQUEST':
        deepLink('/friends');
        break;

      // ── Queue / Waiting Room ────────────────────────────────────────────
      case 'OPEN_QUEUE':
        final queueId = payload['queueId']?.toString() ?? '';
        final position = payload['queuePosition']?.toString() ?? '1';
        final adId = payload['adId']?.toString() ?? '';
        deepLink('/queue?queueId=$queueId&position=$position&adId=$adId');
        break;

      // ── Wallet / balance-related ────────────────────────────────────────
      case 'OPEN_WALLET':
        // No dedicated wallet route — just close the hub, MainWrapper is
        // already underneath.
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        break;

      // ── KYC status updates ──────────────────────────────────────────────
      case 'KYC_STATUS':
        deepLink('/settings');
        break;

      // ── Account status (ban/unban) ──────────────────────────────────────
      case 'ACCOUNT_STATUS':
        deepLink('/settings');
        break;

      // ── Savings ─────────────────────────────────────────────────────────
      case 'VIEW_SAVINGS':
        deepLink('/savings');
        break;

      // ── Marketplace (ad match, boost expired, etc.) ─────────────────────
      case 'OPEN_AD':
      case 'OPEN_MARKETPLACE':
        deepLink('/marketplace');
        break;

      // ── Admin war room ──────────────────────────────────────────────────
      case 'OPEN_WAR_ROOM':
        // Admin screen is imperative nav, not a GoRoute.
        // Silently no-op for now (admin notifications are informational).
        break;

      // ── Fallback: try legacy payload keys (backwards compat) ────────────
      default:
        // Legacy: some older notifications used flat tradeId/disputeId keys
        // without an action field.
        final tradeId = payload['tradeId']?.toString();
        if (tradeId != null && tradeId.isNotEmpty) {
          deepLink('/trade/$tradeId');
          return;
        }
        final disputeId = payload['disputeId']?.toString();
        if (disputeId != null && disputeId.isNotEmpty) {
          deepLink('/dispute/$disputeId');
          return;
        }
        // Route field as last resort
        final route = payload['route']?.toString();
        if (route != null && route.isNotEmpty) {
          deepLink(route);
        }
        break;
    }
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
            : Icon(HugeIconsSolid.checkmarkCircle01, size: 18, color: colors.accent),
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

class _TabBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _TabBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: notification.isRead
            ? Colors.transparent
            : colors.accent.withOpacity(0.04),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLeadingIcon(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                            fontWeight: notification.isRead
                                ? FontWeight.w500
                                : FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _timeAgo(notification.createdAt),
                        style: TextStyle(
                            color: colors.textTertiary, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: TextStyle(
                        color: colors.textSecondary, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeadingIcon() {
    final style = _notifStyle(notification.category, colors);
    return Stack(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: style.color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(style.icon, color: style.color, size: 22),
        ),
        if (!notification.isRead)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: colors.danger,
                shape: BoxShape.circle,
                border:
                    Border.all(color: colors.background, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }

  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${date.day}/${date.month}';
  }
}
