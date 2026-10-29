// =============================================================================
// BOUNDED REALTIME EVENT DEDUPLICATOR
//
// Realtime delivery is a convergence signal, not a durable queue. A persisted
// notification can occasionally be observed more than once by a client (for
// example, because an upstream workflow retries an emit). This helper keeps
// the singleton socket layer from applying the same persisted event twice.
//
// The cache is intentionally bounded and session-scoped. It is not a source of
// truth and must never replace the canonical API read.
// =============================================================================

class RealtimeEventDeduper {
  RealtimeEventDeduper({this.maxEntries = 256})
      : assert(maxEntries > 0),
        _seen = <String>{},
        _order = <String>[];

  final int maxEntries;
  final Set<String> _seen;
  final List<String> _order;

  /// Returns true when [eventId] has not been observed in this session.
  ///
  /// Missing IDs are deliberately accepted because anonymous realtime events
  /// cannot be safely deduplicated without inventing identity semantics.
  bool accept(String? eventId) {
    final id = eventId?.trim();
    if (id == null || id.isEmpty) return true;
    if (!_seen.add(id)) return false;

    _order.add(id);
    if (_order.length > maxEntries) {
      final evicted = _order.removeAt(0);
      _seen.remove(evicted);
    }
    return true;
  }

  void clear() {
    _seen.clear();
    _order.clear();
  }

  int get length => _order.length;
}
