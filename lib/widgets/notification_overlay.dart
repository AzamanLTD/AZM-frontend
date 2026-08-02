import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/models/notification_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/screens/marketplace/business_notifications_screen.dart';

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
  bool _quietHoursEnabled = false;
  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 7, minute: 0);

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
    _loadQuietHours();
  }

  Future<void> _loadQuietHours() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _quietHoursEnabled = prefs.getBool('quiet_hours_enabled') ?? false;
      final startHour = prefs.getInt('quiet_start_hour') ?? 22;
      final startMin = prefs.getInt('quiet_start_min') ?? 0;
      final endHour = prefs.getInt('quiet_end_hour') ?? 7;
      final endMin = prefs.getInt('quiet_end_min') ?? 0;
      _quietStart = TimeOfDay(hour: startHour, minute: startMin);
      _quietEnd = TimeOfDay(hour: endHour, minute: endMin);
    });
  }

  Future<void> _saveQuietHours() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('quiet_hours_enabled', _quietHoursEnabled);
    await prefs.setInt('quiet_start_hour', _quietStart.hour);
    await prefs.setInt('quiet_start_min', _quietStart.minute);
    await prefs.setInt('quiet_end_hour', _quietEnd.hour);
    await prefs.setInt('quiet_end_min', _quietEnd.minute);
  }

  bool _isCurrentlyQuietHours() {
    if (!_quietHoursEnabled) return false;
    final now = TimeOfDay.now();
    final nowMin = now.hour * 60 + now.minute;
    final startMin = _quietStart.hour * 60 + _quietStart.minute;
    final endMin = _quietEnd.hour * 60 + _quietEnd.minute;
    if (startMin <= endMin) {
      return nowMin >= startMin && nowMin < endMin;
    } else {
      // Spans midnight (e.g., 22:00 - 07:00)
      return nowMin >= startMin || nowMin < endMin;
    }
  }

  void _showQuietHoursSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _QuietHoursSheet(
        enabled: _quietHoursEnabled,
        start: _quietStart,
        end: _quietEnd,
        onChanged: (enabled, start, end) {
          setState(() {
            _quietHoursEnabled = enabled;
            _quietStart = start;
            _quietEnd = end;
          });
          _saveQuietHours();
        },
      ),
    );
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
        n.category == NotificationCategory.vendorPriority) {
      return true;
    }
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

  // Business notification card — shown when the Business tab is selected.
  // Business notifications (NEW_ORDER, KYB_STATUS_CHANGED, etc.) live on a
  // separate API + screen, so we show a summary card with a deep-link.
  Widget _buildBusinessSection(BuildContext context, AzamanColors colors, int unread) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              widget.onClose();
              Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BusinessNotificationsScreen()),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.divider, width: 0.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.storefront_rounded,
                        size: 22, color: colors.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Business Notifications',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            )),
                        const SizedBox(height: 2),
                        Text(
                          unread > 0
                              ? '$unread unread notification${unread == 1 ? '' : 's'}'
                              : 'All caught up',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (unread > 0)
                    Container(
                      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: colors.danger,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(
                        '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else
                    Icon(Icons.chevron_right_rounded,
                        size: 22, color: colors.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'New orders, KYB updates, and other business alerts appear here.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  bool _isSecurity(AppNotification n) =>
      n.category == NotificationCategory.securityAccount;

  bool _matchesTab(AppNotification n, int tab) {
    switch (tab) {
      case 0: return !n.isRead;
      case 1: return _isMoney(n);
      case 2: return _isSocial(n);
      case 3: return _isSecurity(n);
      case 4: return _isSystem(n);
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
    final hasBiz  = ref.watch(myBusinessProvider).profile != null;
    final bizUnread = ref.watch(bizUnreadCountProvider);
    final allN = [...all, ...sec, ...vendor]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final filtered = allN.where((n) => _matchesTab(n, _tab)).toList();
    final unread  = allN.where((n) => !n.isRead).length + (hasBiz ? bizUnread : 0);
    final sysCnt  = allN.where(_isSystem).length;
    final money   = allN.where(_isMoney).length;
    final social  = allN.where(_isSocial).length;
    final secCnt  = allN.where(_isSecurity).length;

    // Build the body: business tab shows a link to business notifications,
    // other tabs show the filtered notification list.
    final showBusinessTab = _tab == 5 && hasBiz;

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
                                ? Colors.black.withValues(alpha: 0.75)
                                : Colors.white.withValues(alpha: 0.72),
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
                                // Quiet hours indicator
                                if (_quietHoursEnabled)
                                  GestureDetector(
                                    onTap: _showQuietHoursSheet,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                          color: _isCurrentlyQuietHours()
                                              ? colors.accent.withValues(alpha: 0.15)
                                              : colors.softSurface,
                                          borderRadius: BorderRadius.circular(20)),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(HugeIconsSolid.moon01, size: 13,
                                            color: _isCurrentlyQuietHours() ? colors.accent : colors.textTertiary),
                                        const SizedBox(width: 5),
                                        Text(_isCurrentlyQuietHours() ? 'Quiet' : 'Quiet hrs',
                                            style: TextStyle(
                                                color: _isCurrentlyQuietHours() ? colors.accent : colors.textTertiary,
                                                fontSize: 11, fontWeight: FontWeight.w600,
                                                decoration: TextDecoration.none)),
                                      ]),
                                    ),
                                  ),
                                // Settings gear
                                GestureDetector(
                                  onTap: _showQuietHoursSheet,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                        color: colors.softSurface,
                                        borderRadius: BorderRadius.circular(20)),
                                    child: Icon(HugeIconsSolid.settings02, size: 15, color: colors.textSecondary),
                                  ),
                                ),
                                const SizedBox(width: 8),
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
                                  _categoryRow(0, Icons.mark_chat_unread_rounded, 'All Unread', unread, colors),
                                  Divider(height: 1, color: colors.divider),
                                  _categoryRow(1, Icons.account_balance_wallet_rounded, 'Money', money, colors),
                                  Divider(height: 1, color: colors.divider),
                                  _categoryRow(2, Icons.people_rounded, 'Social', social, colors),
                                  Divider(height: 1, color: colors.divider),
                                  _categoryRow(3, Icons.lock_rounded, 'Security', secCnt, colors),
                                  Divider(height: 1, color: colors.divider),
                                  _categoryRow(4, Icons.admin_panel_settings_rounded, 'System', sysCnt, colors),
                                  if (hasBiz)
                                    _categoryRow(5, Icons.storefront_rounded, 'Business', bizUnread, colors),
                                ]),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: showBusinessTab
                                  ? _buildBusinessSection(context, colors, bizUnread)
                                  : filtered.isEmpty
                                  ? Center(child: Text(
                                  _tab == 0 ? 'No unread notifications' : 'Nothing here',
                                  style: TextStyle(color: colors.textTertiary, fontSize: 13,
                                      decoration: TextDecoration.none)))
                                  : _buildGroupedList(filtered, colors),
                            ),
                            AnimatedBuilder(
                              animation: _bobAnim,
                              builder: (_, __) => Padding(
                                padding: EdgeInsets.only(bottom: 10 + _bobAnim.value, top: 6),
                                child: Center(child: Container(
                                    width: 100, height: 5,
                                    decoration: BoxDecoration(
                                        color: colors.textTertiary.withValues(alpha: 0.35),
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

  // ── Date-grouped notification list ──────────────────────────────────────────
  Widget _buildGroupedList(List<AppNotification> items, AzamanColors colors) {
    final groups = <String, List<AppNotification>>{};
    final now = DateTime.now();
    for (final n in items) {
      final diff = now.difference(n.createdAt);
      String label;
      if (diff.inHours < 24 && now.day == n.createdAt.day) {
        label = 'Today';
      } else if (diff.inHours < 48) {
        label = 'Yesterday';
      } else if (diff.inDays < 7) {
        label = 'This Week';
      } else if (diff.inDays < 30) {
        label = 'This Month';
      } else {
        label = 'Earlier';
      }
      groups.putIfAbsent(label, () => []).add(n);
    }

    final sectionOrder = ['Today', 'Yesterday', 'This Week', 'This Month', 'Earlier'];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: groups.length,
      itemBuilder: (_, sectionIdx) {
        final label = sectionOrder[sectionIdx];
        final sectionItems = groups[label];
        if (sectionItems == null || sectionItems.isEmpty) return const SizedBox();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6, left: 4),
              child: Text(
                label,
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            ...sectionItems.map((n) => _SlideRevealNotification(
              key: ValueKey(n.id),
              notification: n,
              colors: colors,
              onMarkRead: () => ref.read(notificationProvider.notifier).markAsRead(n.id),
              onDelete: () => ref.read(notificationProvider.notifier).deleteNotification(n.id),
              onSnooze: () {},
            )),
          ],
        );
      },
    );
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
                      color: n.isRead ? c.card : c.accent.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.divider.withValues(alpha: 0.5))),
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
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3))),
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


// ── Quiet Hours Bottom Sheet ─────────────────────────────────────────────────

class _QuietHoursSheet extends ConsumerStatefulWidget {
  final bool enabled;
  final TimeOfDay start;
  final TimeOfDay end;
  final void Function(bool enabled, TimeOfDay start, TimeOfDay end) onChanged;

  const _QuietHoursSheet({
    required this.enabled,
    required this.start,
    required this.end,
    required this.onChanged,
  });

  @override
  ConsumerState<_QuietHoursSheet> createState() => _QuietHoursSheetState();
}

class _QuietHoursSheetState extends ConsumerState<_QuietHoursSheet> {
  late bool _enabled;
  late TimeOfDay _start;
  late TimeOfDay _end;

  @override
  void initState() {
    super.initState();
    _enabled = widget.enabled;
    _start = widget.start;
    _end = widget.end;
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:${t.minute.toString().padLeft(2, '0')} $period';
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Icon(HugeIconsSolid.moon01, size: 22, color: colors.accent),
              const SizedBox(width: 10),
              Text('Quiet Hours',
                  style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Suppress non-urgent notifications during your quiet hours. Security alerts will still come through.',
            style: TextStyle(color: colors.textTertiary, fontSize: 13),
          ),
          const SizedBox(height: 24),
          // Enable toggle
          Row(
            children: [
              Expanded(
                child: Text('Enable Quiet Hours',
                    style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500)),
              ),
              Switch.adaptive(
                value: _enabled,
                activeColor: colors.accent,
                onChanged: (v) => setState(() => _enabled = v),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_enabled) ...[
            // Start time
              GestureDetector(
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _start,
                  builder: (_, child) => Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: Theme.of(context).colorScheme.copyWith(
                        primary: colors.accent,
                      ),
                    ),
                    child: child ?? const SizedBox(),
                  ),
                );
                if (picked != null) setState(() => _start = picked);
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    Icon(HugeIconsSolid.moon02, size: 20, color: colors.accent),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Start', style: TextStyle(color: colors.textPrimary, fontSize: 15))),
                    Text(_formatTime(_start),
                        style: TextStyle(color: colors.accent, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded, size: 20, color: colors.textTertiary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // End time
            GestureDetector(
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _end,
                  builder: (_, child) => Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: Theme.of(context).colorScheme.copyWith(
                        primary: colors.accent,
                      ),
                    ),
                    child: child ?? const SizedBox(),
                  ),
                );
                if (picked != null) setState(() => _end = picked);
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    Icon(HugeIconsSolid.sunrise, size: 20, color: colors.accent),
                    const SizedBox(width: 12),
                    Expanded(child: Text('End', style: TextStyle(color: colors.textPrimary, fontSize: 15))),
                    Text(_formatTime(_end),
                        style: TextStyle(color: colors.accent, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded, size: 20, color: colors.textTertiary),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                widget.onChanged(_enabled, _start, _end);
                Navigator.of(context).pop();
              },
              child: const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
