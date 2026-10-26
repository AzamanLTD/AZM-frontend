// =============================================================================
// AZAMAN — DEPOSIT SETTLEMENT MONITOR (PR #202 last review)
//
// The deposit surface's socket handler confirms what is VISIBLE on it. But
// a submitted Moolre instruction outlives the result view: the user may
// back out to Add Cash, start another deposit, or leave the surface
// entirely while the provider is still processing. No cancellation
// contract exists, so the instruction's settlement must still resolve the
// user's stored continuation for that EXACT reference.
//
// This monitor is the settlement half of that contract, wired once per
// app and alive for the whole session:
//
//   • It listens on SocketService's deposit-settlement fan-out (the SAME
//     seam the deposit surface uses — neither displaces the other).
//   • On an event it asks the continuation authority to resolve the
//     ACTIVE user's continuation whose reference matches EXACTLY.
//     A late event for deposit A can never resolve deposit B, and an
//     event for a reference the active user never submitted resolves
//     nothing (per-user attribution, user-scoped storage keys).
//   • Resolution is idempotent and terminal in the service: a duplicate
//     event, a late retry, or a delayed storage mutation can never
//     resurrect a resolved reference.
//
// The monitor is activated by MainWrapper (the app shell — alive for the
// whole session) and by the deposit surface itself (alive whenever Add
// Cash can mint or show a continuation), so a settlement always lands on
// a live monitor no matter which surface is on screen.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/services/deposit_continuations.dart';
import 'package:azaman/services/socket_service.dart';

/// Wires socket deposit settlements to continuation resolution for the
/// lifetime of the container that activates it. Deliberately a `Provider`
/// (not a stream/notifier): its entire body is a side effect plus an
/// unsubscription, and it exposes nothing — surfaces only `ref.watch` it
/// to keep it alive.
final depositSettlementMonitorProvider = Provider<void>((ref) {
  void onSettlement(
    double amountGhs,
    double amountUsdc,
    String provider,
    String reference,
  ) {
    // Owner-aware attribution: the settlement event carries a reference
    // but no identity, so the controller attributes it to the
    // reference's BOUND owner — the identity recorded at the
    // durable-save moment. The ACTIVE user is only the fallback for a
    // reference this device never bound, and even then resolution
    // requires the ACTIVE user's OWN stored list to contain the exact
    // reference — a foreign or unknown event resolves nothing, so the
    // notification centre never loses another user's way back.
    final activeUserId = ref.read(authProvider).user?.id;
    ref
        .read(depositContinuationsProvider.notifier)
        .handleSettlement(activeUserId, reference);
  }

  SocketService.instance.onDepositSuccess(onSettlement);
  ref.onDispose(() {
    SocketService.instance.removeDepositSuccessListener(onSettlement);
  });
});
