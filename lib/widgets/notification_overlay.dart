import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/models/notification_model.dart';

class NotificationOverlay extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const NotificationOverlay({super.key, required this.onClose});

  static void show(BuildContext context) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => NotificationOverlay(onClose: () => entry.remove()),
    );
    overlay.insert(entry);
  }

  @override
  ConsumerState<NotificationOverlay> createState() => _State();
}

class _State extends ConsumerState<NotificationOverlay>
    with TickerProviderStateMixin {
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;
  late AnimationController _bobCtrl;
  late Animation<double> _bobAnim;
  int _tab = 0;
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _slideAnim = Tween<Offset>(
        begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutQuart));
    _slideCtrl.forward();
    _bobCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _bobAnim = Tween<double>(begin: 0, end: 5).animate(
        CurvedAnimation(parent: _bobCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _bobCtrl.dispose();
    super.dispose();
  }

  void _dismiss() => _slideCtrl.reverse().then((_) => widget.onClose());

  bool _isSystem(AppNotification n) {
    if (n.category == NotificationCategory.adminSystem ||
        n.category == NotificationCategory.vendorPriority) return true;
    final t = (n.title + n.body).toLowerCase();
    return t.contains('cfo') || t.contains('balance low') || t.contains('low balance');
  }

  bool _isMoney(AppNotification n) {
    if (n.category != NotificationCategory.general) return false;
    final t = n.title.toLowerCase();
    return t.contains('deposit') || t.contains('withdraw') || t.contains('transfer') ||
        t.contains('payment') || t.contains('vault') || t.contains('susu') ||
        t.contains('route') || t.contains('auction') || t.contains('escrow') ||
        t.contains('invoice');
  }

  bool _isSocial(AppNotification n) =>
      n.category == NotificationCategory.general && !_isMoney(n) && !_isSystem(n);

  bool _isSecurity(AppNotification n) =>
      n.category == NotificationCategory.securityAccount;

  bool _matchesTab(AppNotification n, int tab) {
    switch (tab) {
      case 0: return !n.isRead;
      case 1: return _isSystem(n);
      case 2: return !_isSystem(n);
      default: return false;
    }
  }

  Widget _categoryRow(int idx, IconData icon, String label, int count, AzamanColors colors) {
    final sel = _tab == idx;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _tab = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
            color: sel ? colors.accentSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, size: 18, color: sel ? colors.accent : colors.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(
              color: sel ? colors.accent : colors.textPrimary, fontSize: 14,
              fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
              decoration: TextDecoration.none))),
          if (count > 0) Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: sel ? colors.accent : colors.divider,
                  borderRadius: BorderRadius.circular(10)),
              child: Text('$count', style: TextStyle(
                  color: sel ? Colors.white : colors.textTertiary,
                  fontSize: 11, fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none))),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 16,
              color: sel ? colors.accent : colors.textTertiary),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors  = ref.watch(themeProvider).colors;
    final topPad  = MediaQuery.of(context).padding.top;
    final screenH = MediaQuery.of(context).size.height;
    final all     = ref.watch(generalNotificationsProvider);
    final sec     = ref.watch(securityNotificationsProvider);
    final vendor  = ref.watch(vendorNotificationsProvider);
    final allN = [...all, ...sec, ...vendor]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final filtered = allN.where((n) => _matchesTab(n, _tab)).toList();
    final unread  = allN.where((n) => !n.isRead).length;
    final sysCnt  = allN.where(_isSystem).length;
    final other   = allN.where((n) => !_isSystem(n)).length;

    return Stack(children: [
      GestureDetector(onTap: _dismiss, child: Container(color: Colors.transparent)),
      AnimatedBuilder(
        animation: _slideAnim,
        builder: (_, __) {
          final off = _drag != 0
              ? Offset(0, _drag / screenH) : _slideAnim.value;
          return Transform.translate(
            offset: Offset(0, off.dy * screenH),
            child: GestureDetector(
              onVerticalDragUpdate: (d) {
                if ((d.primaryDelta ?? 0) < 0) {
                  setState(() => _drag += d.primaryDelta!);
                }
              },
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) < -350 || _drag < -80) {
                  _dismiss();
                } else {
                  setState(() => _drag = 0);
                }
              },
              child: SizedBox(
                height: screenH * 0.92,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: DefaultTextStyle(
                      style: const TextStyle(decoration: TextDecoration.none),
                      child: Container(
                        decoration: BoxDecoration(
                            color: colors.isDark
                                ? Colors.black.withOpacity(0.75)
                                : Colors.white.withOpacity(0.72),
                            borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(24))),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: topPad + 14),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(children: [
                                Text('Notifications', style: TextStyle(
                                    color: colors.textPrimary, fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.none)),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    ref.read(notificationProvider.notifier).markAllAsRead();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                        color: colors.accentSurface,
                                        borderRadius: BorderRadius.circular(20)),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(HugeIconsSolid.checkmarkCircle02, size: 13, color: colors.accent),
                                      const SizedBox(width: 5),
                                      Text('Read all', style: TextStyle(
                                          color: colors.accent, fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          decoration: TextDecoration.none)),
                                    ]),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Container(
                                decoration: BoxDecoration(
                                    color: colors.card,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: colors.divider, width: 0.8)),
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  _categoryRow(0, HugeIconsSolid.notification01, 'All Unread', unread, colors),
                                  Divider(height: 1, color: colors.divider),
                                  _categoryRow(1, HugeIconsSolid.shield01, 'System', sysCnt, colors),
                                  Divider(height: 1, color: colors.divider),
                                  _categoryRow(2, HugeIconsSolid.menuSquare, 'Other', other, colors),
                                ]),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: filtered.isEmpty
                                  ? Center(child: Text(
                                  _tab == 0 ? 'No unread notifications' : 'Nothing here',
                                  style: TextStyle(color: colors.textTertiary, fontSize: 13,
                                      decoration: TextDecoration.none)))
                                  : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final n = filtered[i];
                                  return _SlideRevealNotification(
                                    key: ValueKey(n.id),
                                    notification: n,
                                    colors: colors,
                                    onMarkRead: () => ref.read(notificationProvider.notifier).markAsRead(n.id),
                                    onDelete: () => ref.read(notificationProvider.notifier).deleteNotification(n.id),
                                    onSnooze: () {},
                                  );
                                },
                              ),
                            ),
                            AnimatedBuilder(
                              animation: _bobAnim,
                              builder: (_, __) => Padding(
                                padding: EdgeInsets.only(bottom: 10 + _bobAnim.value, top: 6),
                                child: Center(child: Container(
                                    width: 100, height: 5,
                                    decoration: BoxDecoration(
                                        color: colors.textTertiary.withOpacity(0.35),
                                        borderRadius: BorderRadius.circular(3)))),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ]);
  }
}

class _SlideRevealNotification extends StatefulWidget {
  final AppNotification notification;
  final AzamanColors colors;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;
  final VoidCallback onSnooze;
  const _SlideRevealNotification({
    super.key,
    required this.notification,
    required this.colors,
    required this.onMarkRead,
    required this.onDelete,
    required this.onSnooze,
  });

  @override
  State<_SlideRevealNotification> createState() => _SlideState();
}

class _SlideState extends State<_SlideRevealNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _hidden = false;
  static const double _maxReveal = 110.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      lowerBound: -_maxReveal,
      upperBound: _maxReveal,
      value: 0.0,
      duration: const Duration(milliseconds: 240),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snapBack() {
    _controller.animateTo(0.0, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final c = widget.colors;
    final n = widget.notification;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final offset = _controller.value;
        final showRight = offset > 12;
        final showLeft  = offset < -12;

        return GestureDetector(
          onHorizontalDragUpdate: (d) {
            _controller.value = (_controller.value + d.primaryDelta!).clamp(-_maxReveal, _maxReveal);
          },
          onHorizontalDragEnd: (d) {
            final val = _controller.value;
            if (val > 40) {
              _controller.animateTo(_maxReveal, curve: Curves.easeOutCubic);
            } else if (val < -40) {
              _controller.animateTo(-_maxReveal, curve: Curves.easeOutCubic);
            } else {
              _controller.animateTo(0.0, curve: Curves.easeOutCubic);
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: Row(children: [
                  if (showRight)
                    GestureDetector(
                        onTap: () { widget.onMarkRead(); _snapBack(); },
                        child: _chip(c, HugeIconsSolid.checkmarkCircle01,
                            n.isRead ? 'Unread' : 'Read', c.success)),
                  const Spacer(),
                  if (showLeft) ...[
                    GestureDetector(
                        onTap: () { widget.onSnooze(); _snapBack(); },
                        child: _chip(c, HugeIconsSolid.clock01, 'Later', c.warning)),
                    const SizedBox(width: 6),
                    GestureDetector(
                        onTap: () { widget.onDelete(); setState(() => _hidden = true); },
                        child: _chip(c, HugeIconsSolid.delete01, 'Delete', c.danger)),
                  ],
                ]),
              ),
              Transform.translate(
                offset: Offset(offset, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: n.isRead ? c.card : c.accent.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.divider.withOpacity(0.5))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 5),
                        decoration: BoxDecoration(
                            color: n.isRead ? Colors.transparent : c.accent,
                            shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n.title, style: TextStyle(color: c.textPrimary, fontSize: 13,
                          fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
                      const SizedBox(height: 2),
                      Text(n.body, style: TextStyle(color: c.textSecondary,
                          fontSize: 12, height: 1.4, decoration: TextDecoration.none),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(_relTime(n.createdAt), style: TextStyle(
                          color: c.textTertiary, fontSize: 10,
                          decoration: TextDecoration.none)),
                    ])),
                  ]),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _chip(AzamanColors c, IconData icon, String label, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 11,
              fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
        ]),
      );

  String _relTime(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 60) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours   < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
