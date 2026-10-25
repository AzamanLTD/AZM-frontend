import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/models/notification_model.dart';
import 'package:azaman/services/notification_action_dispatcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/widgets/azaman_sheet.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:go_router/go_router.dart';

/// WORKSTREAM A (2026-10-24) — the driven reveal hand-off.
///
/// The Home header's bounded pull-down progressively reveals this panel:
/// the finger owns the panel's position through [update]; on release the
/// session issues a single [commit] (the panel settles open) or [cancel]
/// (it animates back to closed and removes itself). The controller is a
/// dumb command channel — every piece of panel positioning, animation and
/// entry lifecycle stays inside [NotificationOverlay]'s state, so there
/// is exactly one owner per stage of the interaction.
class NotificationRevealController extends ChangeNotifier {
  NotificationRevealController();

  double _reveal = 0;
  double get reveal => _reveal;

  int _command = 0; // 0 none, 1 commit, 2 cancel
  int get command => _command;

  /// The finger moved: [t] is the 0..1 reveal progress. Clamped — the
  /// panel never renders beyond fully open, and a reversed drag below
  /// zero simply holds it closed.
  void update(double t) {
    final clamped = t.clamp(0.0, 1.0);
    if (clamped == _reveal) return;
    _reveal = clamped;
    notifyListeners();
  }

  /// Release past the opening threshold: settle open.
  void commit() {
    _command = 1;
    notifyListeners();
  }

  /// Release below the threshold (or an interrupted/cancelled gesture):
  /// settle closed and remove the entry.
  void cancel() {
    _command = 2;
    notifyListeners();
  }
}

class NotificationOverlay extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  /// When non-null the panel is DRIVEN: it mounts hidden and its on-screen
  /// position follows [drivenReveal] instead of its own entrance animation.
  final NotificationRevealController? drivenReveal;

  const NotificationOverlay({
    super.key,
    required this.onClose,
    this.drivenReveal,
  });

  /// One panel at a time, ever. A second `show` while the centre is open
  /// (or mid-reveal) is a bounce, not a stacked second entry.
  static bool _panelMounted = false;

  static void show(BuildContext context) {
    if (_panelMounted) return;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => NotificationOverlay(onClose: () => entry.remove()),
    );
    overlay.insert(entry);
  }

  /// Begins the finger-driven reveal: mounts the panel hidden above the
  /// top edge and returns the controller the caller drags. Returns null
  /// if a panel is already mounted (the bell tap handles that case).
  static NotificationRevealController? beginReveal(BuildContext context) {
    if (_panelMounted) return null;
    final overlay = Overlay.of(context);
    final controller = NotificationRevealController();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => NotificationOverlay(
        onClose: () => entry.remove(),
        drivenReveal: controller,
      ),
    );
    overlay.insert(entry);
    return controller;
  }

  @override
  ConsumerState<NotificationOverlay> createState() => _State();
}

class _State extends ConsumerState<NotificationOverlay>
    with TickerProviderStateMixin {
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;
  int _tab = 0;
  double _drag = 0;

  /// REVIEW 4.1 — set the moment a card's open action begins closing the
  /// panel so a second tap (or the dismiss tap underneath) can't fire a
  /// second navigation for the same notification.
  bool _closing = false;

  // WORKSTREAM A — driven reveal state. In driven mode the panel's
  // vertical fraction (dy of screen height; 0 = open, negative = above
  // the top edge) is derived from the controller's reveal value. On
  // commit/cancel a short settle animation takes over FROM THE LIVE
  // FRACTION so the hand-off is continuous — never a jump to a canned
  // position.
  bool _drivenMode = false;
  bool _entranceStarted = false;
  NotificationRevealController? _driver;

  /// The continuous settle from a driven state (or the downward
  /// dismissal): animates a raw dy fraction from → to. The CONTROLLER is
  /// persistent (one per State — the panel's rebuild listener watches it,
  /// so it must never be swapped mid-flight); the TWEEN is re-created per
  /// settle with the live from/to fractions.
  late final AnimationController _settleCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  Animation<double>? _settleAnim;
  bool _quietHoursEnabled = false;
  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 7, minute: 0);

  @override
  void initState() {
    super.initState();
    NotificationOverlay._panelMounted = true;
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _driver = widget.drivenReveal;
    _drivenMode = _driver != null;
    if (_drivenMode) {
      _driver!.addListener(_onDriverCommand);
      // Driven panels mount HIDDEN — the entrance animation never runs;
      // the finger supplies the position.
      _slideCtrl.value = 1.0;
    }
    // The non-driven entrance starts in didChangeDependencies: forward()
    // captures the controller's duration at call time, and the accessible
    // (reduced-motion) duration is only resolvable once the inherited
    // MediaQuery is available — starting it here would lock in the 420ms
    // default and animate under reduced motion.
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutQuart));
    _slideCtrl.forward();
    // REVIEW 4.1 — the grab handle no longer bobs on a repeating idle
    // loop. Idle motion exists only to be looked at; the handle is a
    // dismissal affordance, and its affordance is communicated by its
    // position and the panel's own arrival — not by a permanent shimmy.
    // (Motion in this panel now happens only on interaction: the driven
    // reveal, the settle hand-off and the drag dismissal.)
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
    // NEW-B: Panel weight. With quiet hours enabled this body carries a
    // header, a description, a toggle and two time pickers — well past the
    // 45% whisper ceiling — and the Save row must stay reachable. Pinned.
    AzamanSheet.showPanel<void>(
      context,
      builder: (ctx, scrollController) => _QuietHoursSheet(
        enabled: _quietHoursEnabled,
        start: _quietStart,
        end: _quietEnd,
        scrollController: scrollController,
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
    _driver?.removeListener(_onDriverCommand);
    NotificationOverlay._panelMounted = false;
    _settleCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // WORKSTREAM A: reduced motion receives direct state transitions — the
    // entrance/dismissal slide collapses to zero duration. MediaQuery is
    // not readable in initState, so the duration lands here (the first
    // build happens after dependencies resolve, before any animation can
    // matter — the same pattern the notification bell documents).
    _slideCtrl.duration = MotionTokens.accessibleDuration(
      context,
      const Duration(milliseconds: 420),
    );
    _settleCtrl.duration = MotionTokens.accessibleDuration(
      context,
      const Duration(milliseconds: 260),
    );
    if (!_entranceStarted && !_drivenMode) {
      _entranceStarted = true;
      _slideCtrl.forward();
    }
  }

  /// The driven command channel: every controller notification lands
  /// here. A reveal update is a plain position change; commit/cancel are
  /// consumed once and hand the panel to a continuous settle from the
  /// live fraction.
  void _onDriverCommand() {
    if (!mounted) return;
    switch (_driver!.command) {
      case 1: // commit
        _driver!.update(_driver!.reveal); // keep position; clear command
        _startSettle(from: _currentDrivenDy(), to: 0.0, thenRemove: false);
        break;
      case 2: // cancel
        _driver!.update(_driver!.reveal);
        _startSettle(from: _currentDrivenDy(), to: -0.92, thenRemove: true);
        break;
      default:
        setState(() {});
    }
  }

  /// The live dy fraction while driven.
  double _currentDrivenDy() => -(1 - (_driver?.reveal ?? 0)) * 0.92;

  /// Animates the raw dy fraction [from] → [to]; when [thenRemove] the
  /// entry is removed at the end (settle-closed). Continuous with the
  /// live position — the settle always starts from where the panel
  /// actually is (the finger's last reveal, or the drag offset), never
  /// from a canned position.
  void _startSettle({
    required double from,
    required double to,
    required bool thenRemove,
  }) {
    _drivenMode = false;
    _settleAnim = Tween<double>(
      begin: from,
      end: to,
    ).animate(CurvedAnimation(parent: _settleCtrl, curve: Curves.easeOutCubic));
    if (thenRemove) {
      _settleCtrl.forward(from: 0).then((_) {
        if (mounted) widget.onClose();
      });
    } else {
      _settleCtrl.forward(from: 0);
    }
    setState(() {});
  }

  void _dismiss() => _slideCtrl.reverse().then((_) => widget.onClose());

  /// Opens a notification: marks it read, resolves its actionPayload
  /// through the shared canonical dispatcher, and either navigates to
  /// the verified destination (closing this overlay first, exactly like
  /// the hub closes itself before deep-linking) or tells the truth when
  /// there is no supported destination.
  void _openNotification(AppNotification n) {
    // Never double-dispatch while the overlay is already closing.
    if (_closing) return;
    ref.read(notificationProvider.notifier).markAsRead(n.id);

    final action = NotificationActionDispatcher.resolve(n.actionPayload);
    switch (action.resolution) {
      case NotificationActionResolution.navigable:
        final route = action.route!;
        final router = GoRouter.of(context);
        _closing = true;
        _dismiss();
        // Push after the overlay reverse completes so the deep-link stacks
        // on MainWrapper, not on top of a dying overlay. The router is
        // captured BEFORE the async gap; the overlay widget itself is
        // disposed by then, so nothing may touch its context here.
        Future<void>.delayed(const Duration(milliseconds: 260), () {
          router.push(route);
        });
      case NotificationActionResolution.unsupportedAction:
        // Truthful fallback: the payload names an action this app build
        // does not support. Saying nothing would make the tap feel dead;
        // pretending success would be a lie.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("This notification's action isn't available yet."),
            duration: Duration(seconds: 2),
          ),
        );
      case NotificationActionResolution.informational:
        // Purely informational notice — opening it is just reading it.
        break;
    }
  }

  // REVIEW 4.1 — classification is AUTHORITATIVE on the server's explicit
  // NotificationCategory. Title keyword matching survives only as the
  // LEGACY fallback for old `general` notifications (which predate the
  // category field) and can never override or re-file an explicit
  // category. A notification the server filed as MONEY is a money
  // notification whatever its title says — and vice versa.

  bool _isSystem(AppNotification n) {
    if (n.category == NotificationCategory.system ||
        n.category == NotificationCategory.adminSystem ||
        n.category == NotificationCategory.vendorPriority) {
      return true;
    }
    if (n.category != NotificationCategory.general) return false;
    // Legacy fallback only.
    final t = (n.title + n.body).toLowerCase();
    return t.contains('cfo') ||
        t.contains('balance low') ||
        t.contains('low balance');
  }

  bool _isMoney(AppNotification n) {
    if (n.category == NotificationCategory.money) return true;
    if (n.category != NotificationCategory.general) return false;
    // Legacy fallback only.
    final t = n.title.toLowerCase();
    return t.contains('deposit') ||
        t.contains('withdraw') ||
        t.contains('transfer') ||
        t.contains('payment') ||
        t.contains('vault') ||
        t.contains('susu') ||
        t.contains('route') ||
        t.contains('auction') ||
        t.contains('escrow') ||
        t.contains('invoice');
  }

  bool _isSocial(AppNotification n) {
    if (n.category == NotificationCategory.social ||
        n.category == NotificationCategory.chat) {
      return true;
    }
    if (n.category != NotificationCategory.general) return false;
    // Legacy fallback only: old uncategorised mail that is not money or
    // system surfaces under Social.
    return !_isMoney(n) && !_isSystem(n);
  }

  // Business notification card — shown when the Business tab is selected.
  // Business notifications (NEW_ORDER, KYB_STATUS_CHANGED, etc.) live on a
  // separate API + screen, so we show a summary card with a deep-link.
  Widget _buildBusinessSection(
    BuildContext context,
    AzamanColors colors,
    int unread,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              widget.onClose();
              // NEW-A: canonical business notifications route.
              context.push(AzRoutes.businessNotifications);
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
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.storefront_rounded,
                      size: 22,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Business Notifications',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
                      constraints: const BoxConstraints(
                        minWidth: 22,
                        minHeight: 22,
                      ),
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
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: colors.textSecondary,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'New orders, KYB updates, and other business alerts appear here.',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
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
      case 0:
        return !n.isRead;
      case 1:
        return _isMoney(n);
      case 2:
        return _isSocial(n);
      case 3:
        return _isSecurity(n);
      case 4:
        return _isSystem(n);
      default:
        return false;
    }
  }

  Widget _categoryRow(
    int idx,
    IconData icon,
    String label,
    int count,
    AzamanColors colors,
  ) {
    final sel = _tab == idx;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _tab = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: sel ? colors.accentSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: sel ? colors.accent : colors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: sel ? colors.accent : colors.textPrimary,
                  fontSize: 14,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            if (count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: sel ? colors.accent : colors.divider,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: sel ? Colors.white : colors.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: sel ? colors.accent : colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final topPad = MediaQuery.of(context).padding.top;
    final screenH = MediaQuery.of(context).size.height;
    final hasBiz = ref.watch(myBusinessProvider).profile != null;
    final bizUnread = ref.watch(bizUnreadCountProvider);
    // REVIEW 4.1 — the visible list is derived from the ONE canonical
    // server-notification source (notificationProvider), never from a
    // hand-picked subset of category slices. The previous three-way merge
    // (general + security + vendor) silently omitted every notification
    // the server explicitly categorised as money, social, chat or
    // system — supported by the model and provider, invisible here.
    // Deriving from the single source also makes omission and duplicates
    // structurally impossible: every notification appears exactly once.
    final allN = [...ref.watch(notificationProvider)]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final filtered = allN.where((n) => _matchesTab(n, _tab)).toList();
    final unread =
        allN.where((n) => !n.isRead).length + (hasBiz ? bizUnread : 0);
    final sysCnt = allN.where(_isSystem).length;
    final money = allN.where(_isMoney).length;
    final social = allN.where(_isSocial).length;
    final secCnt = allN.where(_isSecurity).length;

    // Build the body: business tab shows a link to business notifications,
    // other tabs show the filtered notification list.
    final showBusinessTab = _tab == 5 && hasBiz;

    return Stack(
      children: [
        GestureDetector(
          onTap: _dismiss,
          child: Container(color: Colors.transparent),
        ),
        AnimatedBuilder(
          // The settle controller carries the driven reveal hand-off and
          // the downward dismissal — without it in the listenable the
          // panel would freeze at the hand-off position (the controller
          // ticks but nobody rebuilds).
          animation: Listenable.merge([_slideAnim, _settleCtrl]),
          builder: (_, __) {
            // WORKSTREAM A — one priority order for the panel's vertical
            // fraction: an in-flight settle (driven hand-off or downward
            // dismissal) wins; then the live driven reveal; then the
            // legacy finger drag; then the canned entrance animation.
            final double dy;
            if (_settleAnim != null) {
              dy = _settleAnim!.value;
            } else if (_drivenMode) {
              dy = _currentDrivenDy();
            } else if (_drag != 0) {
              dy = _drag / screenH;
            } else {
              dy = _slideAnim.value.dy;
            }
            final off = Offset(0, dy);
            return Transform.translate(
              offset: Offset(0, off.dy * screenH),
              child: GestureDetector(
                // WORKSTREAM A — the chrome's drag is BIDIRECTIONAL and
                // finger-attached. Upward stays the legacy dismissal;
                // downward now follows the finger too (the panel hangs
                // from the top edge — dragging it back down toward its
                // origin dismisses it, matching how it arrived). Drags
                // that START on the notification list itself are claimed
                // by the list's own scrollable and never reach this
                // recognizer, so list scrolling stays a normal scroll.
                onVerticalDragStart: (d) {
                  setState(() => _drag = 0);
                },
                onVerticalDragUpdate: (d) {
                  final delta = d.primaryDelta ?? 0;
                  if (delta != 0) {
                    setState(() => _drag += delta);
                  }
                },
                onVerticalDragCancel: () {
                  setState(() => _drag = 0);
                },
                onVerticalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v < -350 || _drag < -80) {
                    // Legacy upward dismissal.
                    _drag = 0;
                    _dismiss();
                  } else if (_drag > 90 || v > 700) {
                    // Downward dismissal: the panel settles DOWN past
                    // its origin and the entry is removed.
                    _drag = 0;
                    _startSettle(from: 0, to: 0.92, thenRemove: true);
                  } else {
                    setState(() => _drag = 0);
                  }
                },
                child: SizedBox(
                  height: screenH * 0.92,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(24),
                    ),
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
                              bottom: Radius.circular(24),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(height: topPad + 14),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  children: [
                                    // Overflow-safe title (pre-existing
                                    // defect surfaced by the Workstream A
                                    // tests): at 400dp and below — and at
                                    // large text scales — the trailing
                                    // controls (quiet-hours chip, gear,
                                    // Read all) alone can exceed the row.
                                    // The title yields first, with a clean
                                    // ellipsis fallback; at normal widths
                                    // nothing changes.
                                    Flexible(
                                      child: Text(
                                        'Notifications',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: colors.textPrimary,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    // Quiet hours indicator
                                    if (_quietHoursEnabled)
                                      GestureDetector(
                                        onTap: _showQuietHoursSheet,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          margin: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _isCurrentlyQuietHours()
                                                ? colors.accent.withValues(
                                                    alpha: 0.15,
                                                  )
                                                : colors.softSurface,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                HugeIconsSolid.moon01,
                                                size: 13,
                                                color: _isCurrentlyQuietHours()
                                                    ? colors.accent
                                                    : colors.textTertiary,
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                _isCurrentlyQuietHours()
                                                    ? 'Quiet'
                                                    : 'Quiet hrs',
                                                style: TextStyle(
                                                  color:
                                                      _isCurrentlyQuietHours()
                                                      ? colors.accent
                                                      : colors.textTertiary,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  decoration:
                                                      TextDecoration.none,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    // Settings gear
                                    GestureDetector(
                                      onTap: _showQuietHoursSheet,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: colors.softSurface,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Icon(
                                          HugeIconsSolid.settings02,
                                          size: 15,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        ref
                                            .read(notificationProvider.notifier)
                                            .markAllAsRead();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.accentSurface,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              HugeIconsSolid.checkmarkCircle02,
                                              size: 13,
                                              color: colors.accent,
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              'Read all',
                                              style: TextStyle(
                                                color: colors.accent,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                decoration: TextDecoration.none,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: colors.card,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: colors.divider,
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _categoryRow(
                                        0,
                                        Icons.mark_chat_unread_rounded,
                                        'All Unread',
                                        unread,
                                        colors,
                                      ),
                                      Divider(height: 1, color: colors.divider),
                                      _categoryRow(
                                        1,
                                        Icons.account_balance_wallet_rounded,
                                        'Money',
                                        money,
                                        colors,
                                      ),
                                      Divider(height: 1, color: colors.divider),
                                      _categoryRow(
                                        2,
                                        Icons.people_rounded,
                                        'Social',
                                        social,
                                        colors,
                                      ),
                                      Divider(height: 1, color: colors.divider),
                                      _categoryRow(
                                        3,
                                        Icons.lock_rounded,
                                        'Security',
                                        secCnt,
                                        colors,
                                      ),
                                      Divider(height: 1, color: colors.divider),
                                      _categoryRow(
                                        4,
                                        Icons.admin_panel_settings_rounded,
                                        'System',
                                        sysCnt,
                                        colors,
                                      ),
                                      if (hasBiz)
                                        _categoryRow(
                                          5,
                                          Icons.storefront_rounded,
                                          'Business',
                                          bizUnread,
                                          colors,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: showBusinessTab
                                    ? _buildBusinessSection(
                                        context,
                                        colors,
                                        bizUnread,
                                      )
                                    : filtered.isEmpty
                                    ? Center(
                                        child: Text(
                                          _tab == 0
                                              ? 'No unread notifications'
                                              : 'Nothing here',
                                          style: TextStyle(
                                            color: colors.textTertiary,
                                            fontSize: 13,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      )
                                    : _buildGroupedList(filtered, colors),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: 10,
                                  top: 6,
                                ),
                                child: Center(
                                  child: Container(
                                    width: 100,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: colors.textTertiary.withValues(
                                        alpha: 0.35,
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
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
      ],
    );
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

    // REVIEW 4.1 BUGFIX — the list previously had `itemCount:
    // groups.length` while the builder indexed `sectionOrder[i]`.
    // Those two lists are UNRELATED: with a single 'Yesterday' group the
    // builder asked for sectionOrder[0] == 'Today', found nothing, and
    // rendered an empty box — so every notification older than today
    // silently vanished from the panel while the unread badge still
    // counted them. Iterate the ACTUAL present sections (in canonical
    // section order) instead.
    final sectionOrder = [
      'Today',
      'Yesterday',
      'This Week',
      'This Month',
      'Earlier',
    ];
    final present = [
      for (final label in sectionOrder)
        if (groups.containsKey(label)) label,
      // Defensive: a label outside the canonical order still renders
      // (grouped last) rather than being dropped.
      ...groups.keys.where((label) => !sectionOrder.contains(label)),
    ];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: present.length,
      itemBuilder: (_, sectionIdx) {
        final label = present[sectionIdx];
        final sectionItems = groups[label]!;
        if (sectionItems.isEmpty) {
          return const SizedBox();
        }

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
            ...sectionItems.map(
              (n) => _SlideRevealNotification(
                key: ValueKey(n.id),
                notification: n,
                colors: colors,
                onMarkRead: () =>
                    ref.read(notificationProvider.notifier).markAsRead(n.id),
                onDelete: () => ref
                    .read(notificationProvider.notifier)
                    .deleteNotification(n.id),
                // REVIEW 4.1 — the card itself is tappable: opening a
                // notification marks it read and dispatches its real
                // actionPayload through the shared action-to-route
                // resolver (the same one the notification hub uses).
                onTap: () => _openNotification(n),
              ),
            ),
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
  // Honest delete: resolves false when the SERVER rejected the
  // dismissal — the row must return with its read state untouched.
  final Future<bool> Function() onDelete;
  final VoidCallback onTap;
  const _SlideRevealNotification({
    super.key,
    required this.notification,
    required this.colors,
    required this.onMarkRead,
    required this.onDelete,
    required this.onTap,
  });

  @override
  State<_SlideRevealNotification> createState() => _SlideState();
}

class _SlideState extends State<_SlideRevealNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _hidden = false;
  // Set only when the SERVER rejected a dismissal — the row returns and
  // an honest caption explains why. Cleared on the next interaction.
  bool _dismissFailed = false;
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
        final showLeft = offset < -12;

        return GestureDetector(
          // REVIEW 4.1 — the card is tappable. A tap that ends without a
          // horizontal drag (i.e. not a swipe-reveal gesture) opens the
          // notification. This recognizer is on the SAME GestureDetector
          // as the horizontal drag, so Flutter arbitrates between the
          // two: a horizontal drag claim suppresses the tap.
          onTapUp: (d) {
            if (_controller.value.abs() < 8) {
              widget.onTap();
            }
          },
          onHorizontalDragUpdate: (d) {
            _controller.value = (_controller.value + d.primaryDelta!).clamp(
              -_maxReveal,
              _maxReveal,
            );
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
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Row(
                    children: [
                      if (showRight)
                        GestureDetector(
                          onTap: () {
                            widget.onMarkRead();
                            _snapBack();
                          },
                          child: _chip(
                            c,
                            HugeIconsSolid.checkmarkCircle01,
                            n.isRead ? 'Unread' : 'Read',
                            c.success,
                          ),
                        ),
                      const Spacer(),
                      // Left-swipe offers ONLY Delete, now backed by the
                      // durable owner-scoped soft-dismissal contract
                      // (PATCH :id/dismiss). Optimistic hide, server is
                      // the authority, a rejection un-hides the row with
                      // its read state untouched and an honest inline
                      // error. No snooze/mute affordance exists because
                      // the backend has no such operation.
                      if (showLeft) ...[
                        GestureDetector(
                          onTap: () async {
                            // Optimistic hide first so the chip feels
                            // instant; the server is the durable
                            // authority and a rejection un-hides the
                            // row (retry = tap Delete again).
                            setState(() => _hidden = true);
                            final dismissed = await widget.onDelete();
                            if (!mounted) return;
                            if (!dismissed) {
                              setState(() {
                                _hidden = false;
                                _dismissFailed = true;
                              });
                            } else if (_dismissFailed) {
                              setState(() => _dismissFailed = false);
                            }
                          },
                          child: Semantics(
                            button: true,
                            label: 'Delete notification from this list',
                            child: _chip(
                              c,
                              HugeIconsSolid.delete01,
                              'Delete',
                              c.danger,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Transform.translate(
                  offset: Offset(offset, 0),
                  child: Semantics(
                    button: true,
                    label: n.isRead
                        ? 'Notification from ${n.title}. Opens details.'
                        : 'Unread notification from ${n.title}. Opens details.',
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: n.isRead
                            ? c.card
                            : c.accent.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: c.divider.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(top: 5),
                            decoration: BoxDecoration(
                              color: n.isRead ? Colors.transparent : c.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  n.title,
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  n.body,
                                  style: TextStyle(
                                    color: c.textSecondary,
                                    fontSize: 12,
                                    height: 1.4,
                                    decoration: TextDecoration.none,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _relTime(n.createdAt),
                                  style: TextStyle(
                                    color: c.textTertiary,
                                    fontSize: 10,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              if (_dismissFailed) ...[
                                const SizedBox(height: 2),
                                Text(
                                  "Couldn't dismiss — not saved. Try again.",
                                  style: TextStyle(
                                    color: c.danger,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      );

  String _relTime(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 60) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

// ── Quiet Hours Bottom Sheet ─────────────────────────────────────────────────

class _QuietHoursSheet extends ConsumerStatefulWidget {
  final bool enabled;
  final TimeOfDay start;
  final TimeOfDay end;
  final void Function(bool enabled, TimeOfDay start, TimeOfDay end) onChanged;

  /// The sheet's own scroll controller, supplied by the Panel that hosts it.
  final ScrollController scrollController;

  const _QuietHoursSheet({
    required this.enabled,
    required this.start,
    required this.end,
    required this.onChanged,
    required this.scrollController,
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

    // NEW-B: the weight owns surface, radius and safe-area, so the old
    // Container and inline handle are deleted. Scrolls through the sheet's own
    // controller; Save is pinned below the scroll area.
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: SingleChildScrollView(
              controller: widget.scrollController,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        HugeIconsSolid.moon01,
                        size: 22,
                        color: colors.accent,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Quiet Hours',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
                        child: Text(
                          'Enable Quiet Hours',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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
                              colorScheme: Theme.of(
                                context,
                              ).colorScheme.copyWith(primary: colors.accent),
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
                            Icon(
                              HugeIconsSolid.moon02,
                              size: 20,
                              color: colors.accent,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Start',
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Text(
                              _formatTime(_start),
                              style: TextStyle(
                                color: colors.accent,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: colors.textTertiary,
                            ),
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
                              colorScheme: Theme.of(
                                context,
                              ).colorScheme.copyWith(primary: colors.accent),
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
                            Icon(
                              HugeIconsSolid.sunrise,
                              size: 20,
                              color: colors.accent,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'End',
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Text(
                              _formatTime(_end),
                              style: TextStyle(
                                color: colors.accent,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: colors.textTertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Save pinned.
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                widget.onChanged(_enabled, _start, _end);
                Navigator.of(context).pop();
              },
              child: const Text(
                'Save',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
