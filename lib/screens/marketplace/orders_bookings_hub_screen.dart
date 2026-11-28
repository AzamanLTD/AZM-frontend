// lib/screens/marketplace/orders_bookings_hub_screen.dart
// =============================================================================
// ORDERS & BOOKINGS — one place for everything a customer has bought or
// booked in the marketplace, and what each one is waiting for.
//
// Before, each kind lived somewhere else or nowhere: store orders behind the
// marketplace receipt icon, trips only from the transit success sheet, no
// list of hotel or table reservations at all (the check-in QR showed once and
// was lost), invoices only from a store that sent one.
//
//   Needs you  the few things waiting on the customer right now, most urgent
//              first: answer an ID-check boarding, pay a saved order, today's
//              boarding pass or check-in QR, confirm a handed-over order, an
//              unpaid bill. Each opens the thing itself.
//   Orders     store orders, with Pay / Got it / Report a problem
//   Trips      transit bookings, boarding QR, the ID-check answer
//   Reservations  stays and tables, with the check-in QR on the day
//   Bills      invoices, unpaid first
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/my_transit_trips_screen.dart';
import 'package:azaman/screens/storefront_order_history_screen.dart';
import 'package:azaman/storefront/providers/storefront_provider.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/marketplace/store_order_pay.dart';
import 'package:azaman/widgets/security/second_factor.dart';

enum HubTab { orders, trips, reservations, bills }

HubTab hubTabFromQuery(String? raw) => switch ((raw ?? '').toLowerCase()) {
  'trips' => HubTab.trips,
  'reservations' || 'stays' => HubTab.reservations,
  'bills' || 'invoices' => HubTab.bills,
  _ => HubTab.orders,
};

enum HubTaskKind {
  answerBoarding,
  payOrder,
  boardingPass,
  checkIn,
  confirmOrder,
  payBill,
}

/// One thing waiting on the customer. [route] opens it directly; without
/// one, the hub switches to [tab], where the item's own actions are.
@immutable
class HubTask {
  const HubTask({
    required this.kind,
    required this.title,
    required this.detail,
    required this.tab,
    this.route,
    this.id,
  });
  final HubTaskKind kind;
  final String title;
  final String detail;
  final HubTab tab;
  final String? route;
  final String? id;
}

String _clock(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _day(DateTime t) {
  final l = t.toLocal();
  return '${_days[l.weekday - 1]} ${l.day} ${_months[l.month - 1]}';
}

/// What needs the customer now, most urgent first. Pure, for tests.
List<HubTask> hubTasks({
  List<Map<String, dynamic>> orders = const [],
  List<TransitBookingSummary> trips = const [],
  List<ReservationSummary> reservations = const [],
  List<BusinessInvoice> invoices = const [],
  required DateTime now,
}) {
  final out = <HubTask>[];
  for (final t in trips.where((t) => t.awaitsBoardingAnswer)) {
    out.add(
      HubTask(
        kind: HubTaskKind.answerBoarding,
        title: 'Was this you?',
        detail: 'Boarded by ID check · ${t.origin} → ${t.destination}',
        tab: HubTab.trips,
        id: t.id,
      ),
    );
  }
  for (final o in orders) {
    final payment = StoreOrderPayment.fromOrder(o);
    if (payment == null) continue;
    out.add(
      HubTask(
        kind: HubTaskKind.payOrder,
        title: 'Pay ${storeUsdcLabel(payment.totalUsdc)}',
        detail: '${payment.storeName} · not paid yet',
        tab: HubTab.orders,
        id: o['id']?.toString(),
      ),
    );
  }
  for (final t in trips) {
    final at = t.departureAt;
    if (!t.canShowBoardingQr || at == null) continue;
    if (at.isAfter(now.add(const Duration(hours: 24))) ||
        at.isBefore(now.subtract(const Duration(hours: 1)))) {
      continue;
    }
    out.add(
      HubTask(
        kind: HubTaskKind.boardingPass,
        title: 'Boarding pass',
        detail: '${t.origin} → ${t.destination} · ${_clock(at)}',
        tab: HubTab.trips,
        route: '/marketplace/transit/boarding/${t.id}',
        id: t.id,
      ),
    );
  }
  for (final r in reservations) {
    if (!r.canShowCheckInQr(now)) continue;
    out.add(
      HubTask(
        kind: HubTaskKind.checkIn,
        title: 'Check-in QR',
        detail: '${r.businessName} · ${r.start != null ? _day(r.start!) : ''}',
        tab: HubTab.reservations,
        route: '/marketplace/booking/checkin-qr/${r.id}',
        id: r.id,
      ),
    );
  }
  for (final o in orders) {
    if (storeOrderStage(o) != StoreOrderStage.confirm) continue;
    final store = o['businessProfile'] is Map
        ? (o['businessProfile']['businessName']?.toString() ?? 'The store')
        : 'The store';
    out.add(
      HubTask(
        kind: HubTaskKind.confirmOrder,
        title: 'Got your order?',
        detail: '$store handed it over',
        tab: HubTab.orders,
        id: o['id']?.toString(),
      ),
    );
  }
  for (final i in invoices.where((i) => i.status == InvoiceStatus.sent)) {
    out.add(
      HubTask(
        kind: HubTaskKind.payBill,
        title: 'Pay ${storeUsdcLabel(i.billTotalUsdc)}',
        detail: '${i.businessName ?? 'A bill'} · ${i.invoiceRef}',
        tab: HubTab.bills,
        route: '/business-market/invoices/${i.id}',
        id: i.id,
      ),
    );
  }
  return out;
}

class OrdersBookingsHubScreen extends ConsumerStatefulWidget {
  const OrdersBookingsHubScreen({
    super.key,
    this.initialTab = HubTab.orders,
    this.secondFactorPrompt,
    this.now,
  });

  final HubTab initialTab;

  /// Replaces the second-factor sheet (tests).
  final Future<SecondFactor?> Function({
    required SecondFactorKind kind,
    String? errorText,
  })?
  secondFactorPrompt;

  /// A fixed clock (tests and captures).
  final DateTime? now;

  @override
  ConsumerState<OrdersBookingsHubScreen> createState() =>
      _OrdersBookingsHubScreenState();
}

class _OrdersBookingsHubScreenState
    extends ConsumerState<OrdersBookingsHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: HubTab.values.length,
    vsync: this,
    initialIndex: widget.initialTab.index,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final invoices = ref.read(myInvoicesProvider);
      if (invoices.invoices.isEmpty && !invoices.isLoading) {
        ref.read(myInvoicesProvider.notifier).load();
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _open(HubTask task) {
    if (task.route != null) {
      context.push(task.route!);
    } else {
      _tabs.animateTo(task.tab.index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final tasks = hubTasks(
      orders: ref.watch(myStoreOrdersProvider).valueOrNull ?? const [],
      trips: ref.watch(myTransitBookingsProvider).valueOrNull ?? const [],
      reservations: ref.watch(myReservationsProvider).valueOrNull ?? const [],
      invoices: ref.watch(myInvoicesProvider).invoices,
      now: widget.now ?? DateTime.now(),
    );
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text(
          'Orders & bookings',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
      ),
      body: Column(
        children: [
          if (tasks.isNotEmpty)
            _NeedsYou(tasks: tasks, colors: colors, onOpen: _open),
          Material(
            color: colors.surface,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: colors.accent,
              unselectedLabelColor: colors.textTertiary,
              indicatorColor: colors.accent,
              labelStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
              tabs: const [
                Tab(key: ValueKey('hub-tab-orders'), text: 'Orders'),
                Tab(key: ValueKey('hub-tab-trips'), text: 'Trips'),
                Tab(
                  key: ValueKey('hub-tab-reservations'),
                  text: 'Reservations',
                ),
                Tab(key: ValueKey('hub-tab-bills'), text: 'Bills'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                StoreOrdersView(secondFactorPrompt: widget.secondFactorPrompt),
                const MyTransitTripsView(),
                MyReservationsView(now: widget.now),
                const MyBillsView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NeedsYou extends StatelessWidget {
  const _NeedsYou({
    required this.tasks,
    required this.colors,
    required this.onOpen,
  });
  final List<HubTask> tasks;
  final AzamanColors colors;
  final void Function(HubTask) onOpen;

  IconData _icon(HubTaskKind k) => switch (k) {
    HubTaskKind.answerBoarding => Icons.badge_outlined,
    HubTaskKind.payOrder => Icons.account_balance_wallet_outlined,
    HubTaskKind.boardingPass => Icons.qr_code_2_rounded,
    HubTaskKind.checkIn => Icons.qr_code_scanner_rounded,
    HubTaskKind.confirmOrder => Icons.inventory_2_outlined,
    HubTaskKind.payBill => Icons.receipt_long_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('hub-needs-you'),
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'NEEDS YOU',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 11.5,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: tasks.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final t = tasks[i];
                return Material(
                  color: colors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    key: ValueKey('hub-task-${t.kind.name}-${t.id ?? i}'),
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onOpen(t),
                    child: Container(
                      width: 232,
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: colors.accent.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _icon(t.kind),
                              color: colors.accent,
                              size: 21,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    fontFeatures: AzText.tabular,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  t.detail,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: colors.textTertiary,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reservations: stays and tables ──────────────────────────────────────────

class MyReservationsView extends ConsumerWidget {
  const MyReservationsView({super.key, this.now});
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final list = ref.watch(myReservationsProvider);
    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _HubMessage(
        colors: colors,
        icon: Icons.hotel_outlined,
        title: 'We could not load your reservations.',
        action: 'Try again',
        onAction: () => ref.invalidate(myReservationsProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return _HubMessage(
            colors: colors,
            icon: Icons.hotel_outlined,
            title: 'No reservations yet.',
          );
        }
        // Upcoming and current first, then the rest as they came.
        final sorted = [...items]
          ..sort((a, b) {
            if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
            final at = a.start ?? DateTime(0);
            final bt = b.start ?? DateTime(0);
            return a.isActive ? at.compareTo(bt) : bt.compareTo(at);
          });
        return RefreshIndicator(
          onRefresh: () => ref.refresh(myReservationsProvider.future),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: sorted.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _ReservationCard(
              r: sorted[i],
              colors: colors,
              now: now ?? DateTime.now(),
            ),
          ),
        );
      },
    );
  }
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({
    required this.r,
    required this.colors,
    required this.now,
  });
  final ReservationSummary r;
  final AzamanColors colors;
  final DateTime now;

  String get _status => switch (r.status.toUpperCase()) {
    'PENDING' => 'Requested · waiting for the business',
    'CONFIRMED' => 'Confirmed',
    'CHECKED_IN' => 'Checked in',
    'CHECKED_OUT' || 'COMPLETED' => 'Completed',
    'CANCELLED_CUSTOMER' || 'CANCELLED_BUSINESS' => 'Cancelled',
    'NO_SHOW' => 'Missed',
    _ => r.status,
  };

  String get _when {
    final s = r.start;
    if (s == null) return '';
    if (r.isStay && r.end != null) {
      final n = r.nights;
      return '${_day(s)} → ${_day(r.end!)} · $n ${n == 1 ? 'night' : 'nights'}';
    }
    return '${_day(s)} · ${_clock(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final guests = r.isStay
        ? '${r.partySize} ${r.partySize == 1 ? 'guest' : 'guests'}'
        : 'Table for ${r.partySize}';
    return Container(
      key: ValueKey('reservation-${r.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.divider, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                r.isStay ? Icons.hotel_outlined : Icons.restaurant_outlined,
                color: colors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.businessName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [if (_when.isNotEmpty) _when, guests].join(' · '),
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12.5,
              fontFeatures: AzText.tabular,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$_status · ${r.reservationRef}',
                  style: TextStyle(color: colors.textTertiary, fontSize: 12),
                ),
              ),
              if (r.canShowCheckInQr(now))
                FilledButton.icon(
                  key: ValueKey('reservation-qr-${r.id}'),
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () =>
                      context.push('/marketplace/booking/checkin-qr/${r.id}'),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: const Text('Check-in QR'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Bills: invoices, unpaid first ───────────────────────────────────────────

class MyBillsView extends ConsumerWidget {
  const MyBillsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(myInvoicesProvider);
    if (state.isLoading && state.invoices.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final bills =
        state.invoices.where((i) => i.status != InvoiceStatus.draft).toList()
          ..sort((a, b) {
            final ua = a.status == InvoiceStatus.sent;
            final ub = b.status == InvoiceStatus.sent;
            if (ua != ub) return ua ? -1 : 1;
            return b.createdAt.compareTo(a.createdAt);
          });
    if (bills.isEmpty) {
      return _HubMessage(
        colors: colors,
        icon: Icons.receipt_long_outlined,
        title: 'No bills yet.',
        detail: 'When a business sends you a bill, it shows here.',
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(myInvoicesProvider.notifier).load(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          for (final i in bills) ...[
            _BillTile(invoice: i, colors: colors),
            const SizedBox(height: 10),
          ],
          Center(
            child: TextButton(
              onPressed: () => context.push('/business-market/invoices'),
              child: const Text('All invoices'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.invoice, required this.colors});
  final BusinessInvoice invoice;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    final unpaid = invoice.status == InvoiceStatus.sent;
    final label = switch (invoice.status) {
      InvoiceStatus.sent => 'Unpaid',
      InvoiceStatus.paid => 'Paid',
      InvoiceStatus.voided => 'Void',
      InvoiceStatus.draft => 'Draft',
    };
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: ValueKey('bill-${invoice.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/business-market/invoices/${invoice.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.businessName ?? 'Bill',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        invoice.invoiceRef,
                        if (invoice.tableLabel != null) invoice.tableLabel!,
                      ].join(' · '),
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    storeUsdcLabel(invoice.billTotalUsdc),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontFeatures: AzText.tabular,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: unpaid ? colors.warning : colors.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubMessage extends StatelessWidget {
  const _HubMessage({
    required this.colors,
    required this.icon,
    required this.title,
    this.detail,
    this.action,
    this.onAction,
  });
  final AzamanColors colors;
  final IconData icon;
  final String title;
  final String? detail;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: colors.textTertiary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textPrimary, fontSize: 15),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    ),
  );
}
