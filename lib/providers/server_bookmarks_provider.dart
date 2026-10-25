// lib/providers/server_bookmarks_provider.dart
// =============================================================================
// Durable business bookmarks — frontend consumer of AZM-backend PR #370
// ("Backend A", BusinessBookmark).
//
// Today the marketplace save toggle rides `savedBusinessesProvider` —
// a device-local SharedPreferences wishlist keyed by DISPLAY "BIZ-..."
// codes. It survives neither reinstall nor device change and pretends
// durability the backend never offered. This provider is the honest
// replacement for real (authenticated, non-demo) sessions:
//
//  * single source of truth = the server (owner-scoped, canonical
//    BusinessProfile.id keys);
//  * optimistic toggle with EXACT rollback when the server rejects
//    (including the contract 404 "wrong business id" — never retried,
//    never simulated);
//  * idempotent semantics both directions: repeat saves converge to
//    BOOKMARKED, repeat removals to NOT_BOOKMARKED;
//  * `alreadyBookmarked` and `removed:false` are surfaced, not treated
//    as errors;
//  * hydrate failure keeps the last known list and records an honest
//    error — it never silently clears the user's bookmarks.
//
// Demo mode keeps the device-local wishlist: there is no backend there,
// and the demo interceptor must never answer for the bookmark contract.
// The single UI seam is [isBusinessSaved] / [toggleBusinessSaved]
// below — real sessions read the durable set, demo reads the wishlist.
//
// MIGRATION NOTE (documented consequence, not a hidden cut): existing
// device-local saves do NOT auto-migrate. The local wishlist keys
// display codes, the contract accepts only canonical BusinessProfile.id
// values, and inventing a server-side save the user never made would
// violate the no-fake-data rule. Users simply re-save.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/config.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/saved_businesses_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/server_bookmark_service.dart';

class ServerBookmarksState {
  /// The caller's bookmarks, newest first (server order).
  final List<ServerBookmark> bookmarks;
  /// Whether the first hydrate has completed.
  final bool loaded;
  /// Honest load failure — the last known list is retained when set.
  final String? error;

  const ServerBookmarksState({
    this.bookmarks = const [],
    this.loaded = false,
    this.error,
  });

  ServerBookmarksState copyWith({
    List<ServerBookmark>? bookmarks,
    bool? loaded,
    String? error,
    bool clearError = false,
  }) {
    return ServerBookmarksState(
      bookmarks: bookmarks ?? this.bookmarks,
      loaded: loaded ?? this.loaded,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ServerBookmarksNotifier extends StateNotifier<ServerBookmarksState> {
  final ServerBookmarkService _service;

  /// [service] injectable so the contract is testable at the provider
  /// boundary. [autoHydrate] false skips the initial list fetch (tests
  /// that seed state directly).
  ServerBookmarksNotifier({ServerBookmarkService? service, bool autoHydrate = true})
      : _service = service ?? ServerBookmarkService(),
        super(const ServerBookmarksState()) {
    if (autoHydrate) hydrate();
  }

  /// Demo mode has no backend; the interceptor must never answer for
  /// the bookmark contract. Every method is a no-op below this gate —
  /// the UI seam routes demo saves to the local wishlist.
  bool get _demo => AppConfig.demoMode;

  bool isSaved(String businessProfileId) =>
      state.bookmarks.any((b) => b.businessProfileId == businessProfileId);

  /// GET /api/bookmarks — converge to the server's durable list.
  Future<void> hydrate() async {
    if (_demo) return;
    try {
      final page = await _service.list();
      // Success clears any stale error AND any optimistic placeholders:
      // the server list is the whole truth.
      state = state.copyWith(bookmarks: page.bookmarks, loaded: true, clearError: true);
    } catch (e) {
      // Keep the last known list; record the honest failure. NEVER
      // clear the user's bookmarks because a load failed.
      state = state.copyWith(
        loaded: state.loaded || state.bookmarks.isNotEmpty,
        error: 'Could not load your saved businesses. Check your connection.',
      );
    }
  }

  /// POST /api/bookmarks — optimistic save with exact rollback.
  /// Returns the durable end state (true = BOOKMARKED).
  Future<bool> save(String businessProfileId) async {
    if (_demo) return false;
    final snapshot = state.bookmarks;
    if (isSaved(businessProfileId)) return true;

    // Optimistic: a placeholder with unknown display fields. The UI
    // must never present those fields as fact before hydrate replaces
    // them with server truth.
    state = state.copyWith(
      bookmarks: [
        ServerBookmark.placeholder(businessProfileId),
        ...snapshot,
      ],
      clearError: true,
    );

    try {
      final result = await _service.save(businessProfileId);
      if (result.bookmarked) {
        // Replace the placeholder with the server-confirmed row. A
        // repeat save (alreadyBookmarked) converges the same way.
        final confirmed = ServerBookmark(
          businessProfileId: result.businessProfileId,
          businessName: '',
          category: '',
          savedAt: result.savedAt ??
              state.bookmarks
                  .firstWhere(
                      (b) => b.businessProfileId == result.businessProfileId)
                  .savedAt,
        );
        state = state.copyWith(
          bookmarks: [
            confirmed,
            ...state.bookmarks
                .where((b) => b.businessProfileId != result.businessProfileId),
          ],
        );
        return true;
      }
      // Defensive: a 2xx without BOOKMARKED is a contract violation —
      // roll back rather than trust it.
      state = state.copyWith(bookmarks: snapshot);
      return false;
    } catch (e) {
      // Includes the contract 404 "wrong business id": no retry, no
      // simulated local save. Restore the exact snapshot.
      state = state.copyWith(bookmarks: snapshot);
      return false;
    }
  }

  /// DELETE /api/bookmarks/:id — optimistic removal with exact
  /// rollback. ANY server 200 is the durable NOT_BOOKMARKED end state
  /// (including the idempotent removed:false).
  Future<bool> remove(String businessProfileId) async {
    if (_demo) return false;
    final snapshot = state.bookmarks;
    if (!isSaved(businessProfileId)) return true;

    state = state.copyWith(
      bookmarks: snapshot
          .where((b) => b.businessProfileId != businessProfileId)
          .toList(),
      clearError: true,
    );

    try {
      final result = await _service.remove(businessProfileId);
      if (result.notBookmarked) {
        return true; // durable end state reached
      }
      // 2xx without NOT_BOOKMARKED = contract violation → roll back.
      state = state.copyWith(bookmarks: snapshot);
      return false;
    } catch (e) {
      state = state.copyWith(bookmarks: snapshot);
      return false;
    }
  }
}

final serverBookmarksProvider =
    StateNotifierProvider<ServerBookmarksNotifier, ServerBookmarksState>(
        (ref) => ServerBookmarksNotifier(
            service: ServerBookmarkService(client: ref.watch(apiClientProvider))));

/// The durable bookmark ids — canonical BusinessProfile.id values.
/// Cards select from this set; it always agrees with the full state.
final serverBookmarkIdsProvider = Provider<Set<String>>((ref) {
  return ref
      .watch(serverBookmarksProvider)
      .bookmarks
      .map((b) => b.businessProfileId)
      .toSet();
});

// ── Single UI seam ───────────────────────────────────────────────────────────
//
// Every bookmark surface (card toggle, screen, store row) goes through
// these two helpers. Real sessions ride the durable server contract;
// demo mode keeps the device-local wishlist because there is no
// backend to talk to and the demo interceptor must never answer for
// the bookmark contract.

bool isBusinessSaved(WidgetRef ref, BusinessProfile business) {
  if (AppConfig.demoMode) {
    return ref.watch(savedBusinessesProvider).contains(business.bizId);
  }
  return ref.watch(serverBookmarkIdsProvider).contains(business.id);
}

/// Toggle + honest failure surface. Returns the durable end state
/// (true = saved). On rejection the optimistic change has already been
/// rolled back, so the icon snaps back on its own; a SnackBar tells
/// the user why.
Future<bool> toggleBusinessSaved(BuildContext context, WidgetRef ref,
    BusinessProfile business) async {
  if (AppConfig.demoMode) {
    await ref.read(savedBusinessesProvider.notifier).toggle(business.bizId);
    return ref.read(savedBusinessesProvider).contains(business.bizId);
  }
  final notifier = ref.read(serverBookmarksProvider.notifier);
  final nowSaved = notifier.isSaved(business.id);
  final ok = nowSaved
      ? await notifier.remove(business.id)
      : await notifier.save(business.id);
  if (!ok) {
    if (!context.mounted) return nowSaved;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(nowSaved
            ? 'Could not remove this bookmark. Not saved — try again.'
            : 'Could not save this business. Not saved — try again.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
  return ok ? !nowSaved : nowSaved;
}
