import 'package:azaman/services/socket_service.dart';

typedef EscrowEventCallback = void Function(
  Map<String, dynamic> payload,
  String event,
);
typedef EscrowSubscription = void Function();

typedef _EscrowSourceRegistrar = void Function(EscrowEventCallback callback);
typedef _EscrowSourceRemover = void Function(EscrowEventCallback callback);

/// Routes the single global escrow event stream to ticket-scoped consumers.
///
/// SocketService remains the transport owner. This registry owns the feature
/// subscription boundary so multiple ticket workspaces can coexist without
/// each screen filtering or managing the global stream itself.
class EscrowSubscriptionRegistry {
  EscrowSubscriptionRegistry({
    required _EscrowSourceRegistrar addSourceListener,
    required _EscrowSourceRemover removeSourceListener,
  })  : _addSourceListener = addSourceListener,
        _removeSourceListener = removeSourceListener;

  factory EscrowSubscriptionRegistry.fromSocket([SocketService? socket]) {
    final source = socket ?? SocketService.instance;
    return EscrowSubscriptionRegistry(
      addSourceListener: source.onEscrowEvent,
      removeSourceListener: source.removeEscrowEventListener,
    );
  }

  static final EscrowSubscriptionRegistry instance =
      EscrowSubscriptionRegistry.fromSocket();

  static const Set<String> _supportedEvents = <String>{
    'escrow_funded',
    'escrow_settled',
    'escrow_pending_settlement',
    'escrow_disputed',
    'escrow_resolved',
    'escrow_terms_updated',
    'escrow_refunded',
  };

  final _EscrowSourceRegistrar _addSourceListener;
  final _EscrowSourceRemover _removeSourceListener;
  final Map<int, _Subscription> _subscriptions = <int, _Subscription>{};
  int _nextId = 0;
  bool _sourceAttached = false;

  EscrowSubscription subscribe({
    required String ticketId,
    required EscrowEventCallback onEvent,
  }) {
    final normalizedTicketId = ticketId.trim();
    if (normalizedTicketId.isEmpty) {
      throw ArgumentError.value(ticketId, 'ticketId', 'must not be empty');
    }

    if (!_sourceAttached) {
      _addSourceListener(_dispatch);
      _sourceAttached = true;
    }

    final id = _nextId++;
    _subscriptions[id] = _Subscription(
      ticketId: normalizedTicketId,
      onEvent: onEvent,
    );

    var active = true;
    return () {
      if (!active) return;
      active = false;
      _subscriptions.remove(id);
      if (_subscriptions.isEmpty && _sourceAttached) {
        _removeSourceListener(_dispatch);
        _sourceAttached = false;
      }
    };
  }

  void _dispatch(Map<String, dynamic> payload, String event) {
    if (!_supportedEvents.contains(event)) return;

    final ticketId = payload['ticketId']?.toString();
    if (ticketId == null || ticketId.isEmpty) return;

    final snapshot = List<_Subscription>.of(_subscriptions.values);
    for (final subscription in snapshot) {
      if (subscription.ticketId != ticketId) continue;
      try {
        subscription.onEvent(payload, event);
      } catch (_) {
        // A feature callback must never break delivery to other subscribers.
      }
    }
  }

  void dispose() {
    _subscriptions.clear();
    if (_sourceAttached) {
      _removeSourceListener(_dispatch);
      _sourceAttached = false;
    }
  }

  bool get hasSubscriptions => _subscriptions.isNotEmpty;
  int get subscriptionCount => _subscriptions.length;
}

class _Subscription {
  const _Subscription({required this.ticketId, required this.onEvent});

  final String ticketId;
  final EscrowEventCallback onEvent;
}
