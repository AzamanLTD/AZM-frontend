// lib/widgets/marketplace/follow_onboarding_spotlight.dart
// =============================================================================
// I1 — Marketplace Follow Onboarding: the spotlight card.
//
// A NON-MODAL, DISMISSIBLE card on Marketplace home. It appears ONLY
// when the eligibility provider proves (via the authoritative
// follow-list request) that the authenticated user follows no
// businesses — loading, errors and malformed data render nothing, so
// onboarding can never masquerade as an eligible state (spec §2).
//
//  * "Choose businesses" opens the selection sheet (real catalogue
//    businesses, honest per-request follows);
//  * "Maybe later" is the explicit dismissal: it persists via the
//    user-scoped store and the card never re-appears for that
//    account — no timers, no surprise re-prompts;
//  * the copy references the EXISTING "Your follows" discovery rail
//    and promises nothing else.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/follow_onboarding_provider.dart';
import 'package:azaman/providers/theme_provider.dart';

class FollowOnboardingSpotlight extends ConsumerWidget {
  const FollowOnboardingSpotlight({
    super.key,
    required this.userId,
    required this.onStart,
  });

  /// The authenticated user id — the eligibility family key. Null
  /// (signed out) renders nothing.
  final String? userId;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eligibility = ref.watch(followOnboardingEligibilityProvider(userId));

    // Every non-eligible state is honest ABSENCE: the card must never
    // appear on a guess (loading, error, dismissed, non-empty list or
    // no user).
    if (eligibility != FollowOnboardingEligibility.eligible) {
      return const SizedBox.shrink(key: ValueKey('follow-onboarding-none'));
    }

    final colors = ref.watch(themeProvider).colors;

    return Container(
      key: const ValueKey('follow-onboarding-spotlight'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accentSurface,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.storefront_outlined,
                  size: 18,
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Follow businesses you care about.',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Following a business puts its latest in your "Your '
            'follows" rail.',
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const ValueKey('follow-onboarding-start'),
                  onPressed: onStart,
                  child: const Text('Choose businesses'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('follow-onboarding-maybe-later'),
                onPressed: () => ref
                    .read(followOnboardingEligibilityProvider(userId).notifier)
                    .maybeLater(),
                child: const Text('Maybe later'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
