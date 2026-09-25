// =============================================================================
// TICKET PROVIDER — Phase UI-4 (2026-05-26)
//
// Riverpod state for the Tickets Engine. Two providers:
//
//   • ticketDashboardProvider(friendshipId)  — list of tickets per friendship,
//                                              filtered by status tab.
//   • ticketWorkspaceProvider(ticketId)      — single ticket detail + message
//                                              history with optimistic appends.
//
// Both providers absorb realtime socket events via the bridge methods
// (`onRealtimeTicketCreated`, `onRealtimeTicketStatusChanged`,
// `onRealtimeTicketMessage`) — call them from the unified socket listener
// (already in place in `socket_service.dart`) when the corresponding events
// arrive.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/ticket_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard (one notifier per friendship)
// ─────────────────────────────────────────────────────────────────────────────

class TicketDashboardState {
  final TicketStatus activeTab;
  final List<Ticket> openTickets;
  final List<Ticket> closedTickets;
  final List<Ticket> cancelledTickets;
  final bool isLoading;
  final String? error;

  const TicketDashboardState({
    this.activeTab = TicketStatus.open,
    this.openTickets = const [],
    this.closedTickets = const [],
    this.cancelledTickets = const [],
    this.isLoading = false,
    this.error,
  });

  TicketDashboardState copyWith({
    TicketStatus? activeTab,
    List<Ticket>? openTickets,
    List<Ticket>? closedTickets,
    List<Ticket>? cancelledTickets,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return TicketDashboardState(
      activeTab: activeTab ?? this.activeTab,
      openTickets: openTickets ?? this.openTickets,
      closedTickets: closedTickets ?? this.closedTickets,
      cancelledTickets: cancelledTickets ?? this.cancelledTickets,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  List<Ticket> ticketsFor(TicketStatus s) {
    switch (s) {
      case TicketStatus.open: return openTickets;
      case TicketStatus.closed: return closedTickets;
      case TicketStatus.cancelled: return cancelledTickets;
    }
  }
}

class TicketDashboardNotifier extends StateNotifier<TicketDashboardState> {
  final String friendshipId;
  final TicketService _service;

  TicketDashboardNotifier(this.friendshipId, this._service)
      : super(const TicketDashboardState());

  void setActiveTab(TicketStatus s) {
    if (state.activeTab == s) return;
    state = state.copyWith(activeTab: s);
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _service.listTickets(friendshipId: friendshipId, status: TicketStatus.open),
        _service.listTickets(friendshipId: friendshipId, status: TicketStatus.closed),
        _service.listTickets(friendshipId: friendshipId, status: TicketStatus.cancelled),
      ]);
      state = state.copyWith(
        openTickets: results[0].tickets,
        closedTickets: results[1].tickets,
        cancelledTickets: results[2].tickets,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<Ticket> createTicket({
    required String name,
    required TicketType type,
    required double targetAmount,
    required String targetCurrency,
    String? memo,
  }) async {
    final ticket = await _service.createTicket(
      friendshipId: friendshipId,
      name: name,
      type: type,
      targetAmount: targetAmount,
      targetCurrency: targetCurrency,
      memo: memo,
    );
    onRealtimeTicketCreated(ticket);
    return ticket;
  }

  /// Inject a freshly-created ticket without waiting for the dashboard
  /// REST refresh. Called from the create flow above and from socket
  /// `ticket_created` events for the counterparty's session.
  void onRealtimeTicketCreated(Ticket t) {
    if (t.friendshipId != friendshipId) return;
    final list = List<Ticket>.from(state.openTickets);
    if (list.any((x) => x.id == t.id)) return; // dedup
    list.insert(0, t);
    state = state.copyWith(openTickets: list);
  }

  /// Move a ticket between status buckets in response to a `ticket_status_changed`
  /// socket event (or local mutation).
  void onRealtimeTicketStatusChanged(Ticket t) {
    if (t.friendshipId != friendshipId) return;
    List<Ticket> remove(List<Ticket> source) =>
        source.where((x) => x.id != t.id).toList();
    final newOpen = remove(state.openTickets);
    final newClosed = remove(state.closedTickets);
    final newCancelled = remove(state.cancelledTickets);
    switch (t.status) {
      case TicketStatus.open:
        newOpen.insert(0, t);
        break;
      case TicketStatus.closed:
        newClosed.insert(0, t);
        break;
      case TicketStatus.cancelled:
        newCancelled.insert(0, t);
        break;
    }
    state = state.copyWith(
      openTickets: newOpen,
      closedTickets: newClosed,
      cancelledTickets: newCancelled,
    );
  }
}

final ticketDashboardProvider = StateNotifierProvider.family<
    TicketDashboardNotifier, TicketDashboardState, String>(
  (ref, friendshipId) => TicketDashboardNotifier(friendshipId, TicketService.instance),
);

// ─────────────────────────────────────────────────────────────────────────────
// Workspace (one notifier per ticket)
// ─────────────────────────────────────────────────────────────────────────────

class TicketWorkspaceState {
  final Ticket? ticket;
  final List<TicketMessageRow> messages;
  final bool isLoading;
  final bool isSending;
  final String? error;
  final int? counterpartyViewingUserId; // non-null while presence banner shown

  const TicketWorkspaceState({
    this.ticket,
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.error,
    this.counterpartyViewingUserId,
  });

  TicketWorkspaceState copyWith({
    Ticket? ticket,
    List<TicketMessageRow>? messages,
    bool? isLoading,
    bool? isSending,
    String? error,
    int? counterpartyViewingUserId,
    bool clearError = false,
    bool clearViewing = false,
  }) {
    return TicketWorkspaceState(
      ticket: ticket ?? this.ticket,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      error: clearError ? null : (error ?? this.error),
      counterpartyViewingUserId: clearViewing
          ? null
          : (counterpartyViewingUserId ?? this.counterpartyViewingUserId),
    );
  }
}

class TicketWorkspaceNotifier extends StateNotifier<TicketWorkspaceState> {
  final String ticketId;
  final TicketService _service;

  TicketWorkspaceNotifier(this.ticketId, this._service)
      : super(const TicketWorkspaceState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final detail = await _service.getTicket(ticketId);
      state = state.copyWith(
        ticket: detail.ticket,
        messages: detail.messages,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> sendText(String content) async {
    if (content.trim().isEmpty || state.isSending) return;
    state = state.copyWith(isSending: true);
    try {
      final msg = await _service.sendMessage(
        ticketId: ticketId,
        content: content.trim(),
        type: 'TEXT',
      );
      state = state.copyWith(
        messages: [...state.messages, msg],
        isSending: false,
      );
    } catch (e) {
      state = state.copyWith(isSending: false, error: e.toString());
    }
  }

  /// Append a real-time message arriving via socket.
  void onRealtimeMessage(TicketMessageRow msg) {
    if (msg.ticketId != ticketId) return;
    if (state.messages.any((m) => m.id == msg.id)) return; // dedup
    state = state.copyWith(messages: [...state.messages, msg]);
  }

  /// Update the local ticket status on a socket `ticket_status_changed`.
  void onRealtimeStatusChange(Ticket updated) {
    if (updated.id != ticketId) return;
    state = state.copyWith(ticket: updated);
  }

  /// Toggle the presence banner ("counterparty is viewing the ticket").
  void onRealtimePresence({required int userId, required bool viewing}) {
    if (state.ticket == null) return;
    // Ignore self-events.
    final t = state.ticket!;
    final selfId = userId == t.creatorId
        ? null // server tells us the OTHER user; if it's the creator and we ARE the creator, ignore
        : userId;
    if (selfId == null) return;
    if (viewing) {
      state = state.copyWith(counterpartyViewingUserId: userId);
    } else {
      state = state.copyWith(clearViewing: true);
    }
  }

  Future<void> close() => _change(TicketStatus.closed);
  Future<void> cancel() => _change(TicketStatus.cancelled);
  Future<void> reopen() => _change(TicketStatus.open);

  Future<void> _change(TicketStatus s) async {
    try {
      final updated = await _service.changeStatus(ticketId: ticketId, status: s);
      state = state.copyWith(ticket: updated);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> pingViewing(bool viewing) =>
      _service.pingPresence(ticketId: ticketId, viewing: viewing);
}

final ticketWorkspaceProvider = StateNotifierProvider.family
    .autoDispose<TicketWorkspaceNotifier, TicketWorkspaceState, String>(
  (ref, ticketId) => TicketWorkspaceNotifier(ticketId, TicketService.instance),
);
