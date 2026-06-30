// =============================================================================
// TICKET DASHBOARD SCREEN — Phase UI-4 (2026-05-26)
//
// Tabbed dashboard listing all tickets between two friends. Three tabs:
// Open | Closed | Cancelled. Floating Action Button at the bottom-right
// spawns a new ticket workspace via `TicketCreateSheet`.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/ticket_provider.dart';
import 'package:azaman/screens/tickets/ticket_create_sheet.dart';
import 'package:azaman/screens/tickets/ticket_workspace_screen.dart';
import 'package:azaman/services/ticket_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';


class TicketDashboardScreen extends ConsumerStatefulWidget {
  final String friendshipId;
  final String friendUsername;
  const TicketDashboardScreen({
    super.key,
    required this.friendshipId,
    required this.friendUsername,
  });

  @override
  ConsumerState<TicketDashboardScreen> createState() =>
      _TicketDashboardScreenState();
}

class _TicketDashboardScreenState extends ConsumerState<TicketDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(ticketDashboardProvider(widget.friendshipId).notifier).refresh();
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChange() {
    if (_tabController.indexIsChanging) AzamanHaptics.toggle();
    final s = TicketStatus.values[_tabController.index];
    ref
        .read(ticketDashboardProvider(widget.friendshipId).notifier)
        .setActiveTab(s);
  }

  Future<void> _openCreateSheet() async {
    AzamanHaptics.confirm();
    final newTicket = await showModalBottomSheet<Ticket>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TicketCreateSheet(friendshipId: widget.friendshipId),
    );
    if (newTicket != null && mounted) {
      _openTicket(newTicket);
    }
  }

  void _openTicket(Ticket t) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TicketWorkspaceScreen(
          ticketId: t.id,
          friendUsername: widget.friendUsername,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(ticketDashboardProvider(widget.friendshipId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tickets',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'with ${widget.friendUsername}',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: colors.surface,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Container(
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: colors.isDark ? Colors.black : Colors.white,
                unselectedLabelColor: colors.textSecondary,
                labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4),
                unselectedLabelStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
                dividerColor: Colors.transparent,
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                tabs: const [
                  Tab(height: 32, text: 'Open'),
                  Tab(height: 32, text: 'Closed'),
                  Tab(height: 32, text: 'Cancelled'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _List(
            tickets: state.openTickets,
            isLoading: state.isLoading && state.openTickets.isEmpty,
            error: state.error,
            emptyLabel: 'No open tickets yet.',
            onTap: _openTicket,
            onRetry: () => ref
                .read(ticketDashboardProvider(widget.friendshipId).notifier)
                .refresh(),
            colors: colors,
          ),
          _List(
            tickets: state.closedTickets,
            isLoading: state.isLoading && state.closedTickets.isEmpty,
            error: state.error,
            emptyLabel: 'No closed tickets.',
            onTap: _openTicket,
            onRetry: () => ref
                .read(ticketDashboardProvider(widget.friendshipId).notifier)
                .refresh(),
            colors: colors,
          ),
          _List(
            tickets: state.cancelledTickets,
            isLoading: state.isLoading && state.cancelledTickets.isEmpty,
            error: state.error,
            emptyLabel: 'No cancelled tickets.',
            onTap: _openTicket,
            onRetry: () => ref
                .read(ticketDashboardProvider(widget.friendshipId).notifier)
                .refresh(),
            colors: colors,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateSheet,
        backgroundColor: colors.accent,
        foregroundColor: colors.isDark ? Colors.black : Colors.white,
        elevation: 2,
        icon: const Icon(Icons.add),
        label: const Text(
          'New Ticket',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  final List<Ticket> tickets;
  final bool isLoading;
  final String? error;
  final String emptyLabel;
  final void Function(Ticket) onTap;
  final VoidCallback onRetry;
  final AzamanColors colors;
  const _List({
    required this.tickets,
    required this.isLoading,
    required this.error,
    required this.emptyLabel,
    required this.onTap,
    required this.onRetry,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (error != null && tickets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  color: colors.danger, size: 36),
              const SizedBox(height: 10),
              Text('Could not load tickets',
                  style: TextStyle(
                      color: colors.textPrimary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textTertiary, fontSize: 11)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.accent.withOpacity(0.4)),
                ),
                child: Text('Retry',
                    style: TextStyle(color: colors.accent)),
              ),
            ],
          ),
        ),
      );
    }
    if (tickets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.confirmation_number_outlined,
                  color: colors.textTertiary, size: 44),
              const SizedBox(height: 10),
              Text(emptyLabel,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 6),
              Text('Tap the + button to start one.',
                  style: TextStyle(color: colors.textTertiary, fontSize: 11)),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      color: colors.accent,
      backgroundColor: colors.card,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: tickets.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) =>
            _TicketTile(ticket: tickets[i], onTap: onTap, colors: colors),
      ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  final Ticket ticket;
  final void Function(Ticket) onTap;
  final AzamanColors colors;
  const _TicketTile({
    required this.ticket,
    required this.onTap,
    required this.colors,
  });

  Color get _statusColor {
    switch (ticket.status) {
      case TicketStatus.open: return colors.success;
      case TicketStatus.closed: return colors.textTertiary;
      case TicketStatus.cancelled: return colors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onTap(ticket),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.accent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.confirmation_number_outlined,
                  color: colors.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ticket.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _statusColor.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          ticket.status.label.toUpperCase(),
                          style: TextStyle(
                            color: _statusColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${ticket.type.label} · ${ticket.targetAmount.toStringAsFixed(2)} ${ticket.targetCurrency}',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (ticket.memo != null && ticket.memo!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      ticket.memo!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: colors.textTertiary, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward,
                color: colors.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }
}
