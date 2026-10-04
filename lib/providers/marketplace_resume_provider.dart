// =============================================================================
// AZAMAN — RESUME (brief §7.4)
//
// "Pick up where you left off". Derived, never stored. At most one intent.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/providers/marketplace_discovery_provider.dart';
import 'package:azaman/providers/marketplace_world_memory_provider.dart';

enum ResumeKind { cart, worldSearch }

class ResumeIntent {
  final ResumeKind kind;
  final String title;
  final String subtitle;
  final String? businessProfileId;
  final String? worldWire;

  const ResumeIntent({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.businessProfileId,
    this.worldWire,
  });
}

final marketplaceResumeProvider = Provider<ResumeIntent?>((ref) {
  final cart = ref.watch(cartProvider);
  if (cart.items.isNotEmpty && !cart.isCheckingOut) {
    final count = cart.items.fold<int>(0, (a, i) => a + i.quantity);
    final name = cart.businessName;
    return ResumeIntent(
      kind: ResumeKind.cart,
      title: name == null || name.isEmpty
          ? 'Finish your order'
          : 'Finish your order at $name',
      subtitle:
          '$count item${count == 1 ? '' : 's'} · GH₵ ${cart.subtotal.toStringAsFixed(2)}',
      businessProfileId: cart.businessProfileId,
    );
  }

  final now = ref.watch(discoveryClockProvider)();
  final memories = ref.watch(worldMemoryProvider);
  MapEntry<String, WorldMemory>? best;
  for (final e in memories.entries) {
    final q = e.value.query;
    if (!e.value.isFresh(now) || q == null || q.isEmpty) continue;
    if (best == null || e.value.touchedAt.isAfter(best.value.touchedAt)) best = e;
  }
  if (best != null) {
    final label = BusinessCategories.labelFor(best.key);
    return ResumeIntent(
      kind: ResumeKind.worldSearch,
      title: 'Back to "${best.value.query}"',
      subtitle: 'in $label',
      worldWire: best.key,
    );
  }
  return null;
});