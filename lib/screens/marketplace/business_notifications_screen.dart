// =============================================================================
// BUSINESS NOTIFICATIONS SCREEN — Flutter V3 Marketplace Sprint (2026-06-21)
//
// Owner-facing notification feed with pull-to-refresh, infinite scroll and a
// mark-all-read action. Registers a `biz_notification` socket listener while
// mounted so a fresh notification refreshes the feed in real time.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/biz_notification_card.dart';

class BusinessNotificationsScreen extends ConsumerStatefulWidget {
  const BusinessNotificationsScreen({super.key});

  @override
  ConsumerState<BusinessNotificationsScreen> createState() =>
      _BusinessNotificationsScreenState();
}

class _BusinessNotificationsScreenState
    extends ConsumerState<BusinessNotificationsScreen> {
  final _service = BusinessService();
  final _scrollCtrl = ScrollController();

  final List<BizNotification> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _cursor;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _load();
    // Realtime: a new biz_notification refreshes the feed + badge.
    SocketService.instance.onBizNotification((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    try {
      final feed = await _service.getNotifications();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(feed.notifications);
        _hasMore = feed.hasMore;
        _cursor = feed.nextCursor;
        _loading = false;
      });
      ref.read(bizUnreadCountProvider.notifier).state = feed.unreadCount;
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    final feed = await _service.getNotifications();
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(feed.notifications);
      _hasMore = feed.hasMore;
      _cursor = feed.nextCursor;
    });
    ref.read(bizUnreadCountProvider.notifier).state = feed.unreadCount;
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final feed = await _service.getNotifications(cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _items.addAll(feed.notifications);
        _hasMore = feed.hasMore;
        _cursor = feed.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _service.markAllNotificationsRead();
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _items.length; i++) {
          final n = _items[i];
          _items[i] = BizNotification(
            id: n.id,
            type: n.type,
            title: n.title,
            body: n.body,
            metadata: n.metadata,
            isRead: true,
            createdAt: n.createdAt,
          );
        }
      });
      ref.read(bizUnreadCountProvider.notifier).state = 0;
    } catch (_) {}
  }

  Future<void> _onTap(BizNotification n) async {
    if (!n.isRead) {
      try {
        await _service.markNotificationRead(n.id);
        final idx = _items.indexWhere((x) => x.id == n.id);
        if (idx != -1 && mounted) {
          setState(() {
            _items[idx] = BizNotification(
              id: n.id,
              type: n.type,
              title: n.title,
              body: n.body,
              metadata: n.metadata,
              isRead: true,
              createdAt: n.createdAt,
            );
          });
          final count = ref.read(bizUnreadCountProvider);
          ref.read(bizUnreadCountProvider.notifier).state =
              count > 0 ? count - 1 : 0;
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text('Business Alerts',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Mark all read',
            icon: Icon(Icons.done_all, color: colors.accent),
            onPressed: _markAllRead,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? AzamanEmptyState(
                  icon: Icons.notifications_outlined,
                  title: 'No notifications yet',
                  subtitle: 'Order and payment alerts will appear here.',
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length + (_hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      if (i >= _items.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      return BizNotificationCard(
                        notification: _items[i],
                        onTap: () => _onTap(_items[i]),
                      );
                    },
                  ),
                ),
    );
  }
}
