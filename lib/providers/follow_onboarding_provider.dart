// lib/providers/follow_onboarding_provider.dart
// =============================================================================
// I1 — Marketplace Follow Onboarding: eligibility.
//
// The spotlight card on Marketplace home may appear ONLY when the
// authenticated user's EXISTING, AUTHORITATIVE follow-list request
// succeeds and confirms the user follows no businesses. Honesty rules
// (spec §2, §6):
//
//  * loading, authentication failure, network error, malformed
//    response and missing data are NEVER treated as an empty follow
//    list — the card simply does not appear;
//  * eligibility is proven by a real 200 whose `following` is a List
//    of length 0;
//  * a dismissal ("Maybe later") is read from the user-scoped store
//    BEFORE the network call and is permanent for that account;
//  * the provider is a family keyed by the authenticated user id, so
//    account switching rebuilds eligibility from scratch for the new
//    identity — no state bleeds between accounts by construction;
//  * demo mode has no follow backend: eligibility is honestly
//    unestablished and the card never renders.
// =============================================================================
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/config.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/follow_onboarding_dismissal_store.dart';

/// The full, distinct state set the spotlight and tests reason about.
enum FollowOnboardingEligibility {
  /// The authoritative follow list is in flight.
  loading,

  /// No authenticated user — the card never appears.
  notAuthenticated,

  /// The follow-list request failed, was rejected, or returned a
  /// malformed/missing body. NEVER equivalent to "follows no one".
  error,

  /// This user chose "Maybe later" before (user-scoped store). The
  /// card does not re-appear for this account.
  dismissed,

  /// The authoritative list succeeded and is NON-empty — the user
  /// already follows businesses; onboarding has nothing to offer.
  notEligible,

  /// The authoritative list succeeded and is EMPTY — the spotlight
  /// card may appear.
  eligible,
}

/// Injectable seams so tests drive real behavior, not mocks of logic.
class FollowOnboardingEligibilityController
    extends StateNotifier<FollowOnboardingEligibility> {
  FollowOnboardingEligibilityController({
    required String? userId,
    ApiClient? api,
    FollowOnboardingDismissalStore? store,
    bool? demoMode,
  }) : _userId = userId,
       _api = api ?? apiClient,
       _store = store ?? FollowOnboardingDismissalStore(),
       _demoMode = demoMode ?? AppConfig.demoMode,
       super(FollowOnboardingEligibility.loading) {
    _load();
  }

  final String? _userId;
  final ApiClient _api;
  final FollowOnboardingDismissalStore _store;
  final bool _demoMode;

  static const _eligibilityEndpoint = '/follows/following?limit=1';

  Future<void> _load() async {
    if (_userId == null || _userId!.isEmpty) {
      state = FollowOnboardingEligibility.notAuthenticated;
      return;
    }
    // Demo mode: there is no follow authority — the demo interceptor
    // must never answer for this contract.
    if (_demoMode) {
      state = FollowOnboardingEligibility.error;
      return;
    }
    // A previous explicit dismissal for THIS account wins without a
    // network call. A store read failure is honest absence: fall
    // through to the authoritative request.
    try {
      if (await _store.isDismissed(_userId)) {
        state = FollowOnboardingEligibility.dismissed;
        return;
      }
    } catch (_) {
      // not dismissed — keep going.
    }

    state = FollowOnboardingEligibility.loading;
    try {
      final res = await _api.get(_eligibilityEndpoint);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        state = FollowOnboardingEligibility.error;
        return;
      }
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) {
        state = FollowOnboardingEligibility.error;
        return;
      }
      final following = body['following'];
      // Malformed or missing data is NEVER an empty follow list.
      if (following is! List) {
        state = FollowOnboardingEligibility.error;
        return;
      }
      state = following.isEmpty
          ? FollowOnboardingEligibility.eligible
          : FollowOnboardingEligibility.notEligible;
    } catch (_) {
      state = FollowOnboardingEligibility.error;
    }
  }

  /// The ONLY write path: an explicit "Maybe later" tap. Persists the
  /// user-scoped dismissal and settles the state. A persist failure
  /// still hides the card for this session but does NOT claim durable
  /// dismissal — the state is honest either way (the card may return
  /// next launch, which is the lesser evil vs. nagging after "no").
  Future<void> maybeLater() async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;
    state = FollowOnboardingEligibility.dismissed;
    try {
      await _store.dismiss(userId);
    } catch (_) {
      // Session-level dismissal stands; nothing durable was claimed.
    }
  }
}

final followOnboardingDismissalStoreProvider =
    Provider<FollowOnboardingDismissalStore>(
      (ref) => FollowOnboardingDismissalStore(),
    );

/// Keyed by the authenticated user id — the identity boundary. When
/// the account changes, the old notifier is disposed and the new one
/// loads from the new user's own store key and authoritative list.
final followOnboardingEligibilityProvider = StateNotifierProvider.autoDispose
    .family<
      FollowOnboardingEligibilityController,
      FollowOnboardingEligibility,
      String?
    >(
      (ref, userId) => FollowOnboardingEligibilityController(
        userId: userId,
        api: ref.watch(apiClientProvider),
        store: ref.watch(followOnboardingDismissalStoreProvider),
      ),
    );
