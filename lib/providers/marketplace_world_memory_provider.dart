// =============================================================================
// AZAMAN — WORLD MEMORY (brief §7.1)
//
// In-memory (not persisted) per-world UI context: query, subcategory, scroll
// offset. NEVER stores transactional state — carts live in `cartProvider`;
// the resume surface reads them read-only.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorldMemory {
  final String? query;
  final String? subcategory;
  final double scrollOffset;
  final DateTime touchedAt;

  const WorldMemory({
    this.query,
    this.subcategory,
    this.scrollOffset = 0,
    required this.touchedAt,
  });

  static const freshness = Duration(minutes: 30);

  bool isFresh(DateTime now) => now.difference(touchedAt) < freshness;
}

class WorldMemoryNotifier extends StateNotifier<Map<String, WorldMemory>> {
  WorldMemoryNotifier({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        super(const {});

  final DateTime Function() _clock;

  void remember(String wire,
      {String? query, String? subcategory, double? scrollOffset}) {
    final prev = state[wire];
    state = {
      ...state,
      wire: WorldMemory(
        query: query ?? prev?.query,
        subcategory: subcategory ?? prev?.subcategory,
        scrollOffset: scrollOffset ?? prev?.scrollOffset ?? 0,
        touchedAt: _clock(),
      ),
    };
  }

  /// Fresh memory for [wire], or null.
  WorldMemory? recall(String wire) {
    final m = state[wire];
    return (m != null && m.isFresh(_clock())) ? m : null;
  }

  /// Most recently touched fresh world, or null.
  String? mostRecentWire() {
    final now = _clock();
    String? best;
    DateTime? bestAt;
    for (final e in state.entries) {
      if (!e.value.isFresh(now)) continue;
      if (bestAt == null || e.value.touchedAt.isAfter(bestAt)) {
        best = e.key;
        bestAt = e.value.touchedAt;
      }
    }
    return best;
  }

  void forget(String wire) {
    if (!state.containsKey(wire)) return;
    state = {...state}..remove(wire);
  }
}

final worldMemoryProvider =
    StateNotifierProvider<WorldMemoryNotifier, Map<String, WorldMemory>>(
  (_) => WorldMemoryNotifier(),
);