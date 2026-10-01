// =============================================================================
// AZAMAN — SAVE / P2P / SUSU WALLET MODULES  (NEW-HOME §9)
//
// Exactly three compact wallet capabilities directly below the card deck.
// They are capabilities, not three giant cards. Each carries a small
// "notice board": real contextual information when authoritative data is
// ALREADY loaded, and a short educational/product explanation when it is
// not. Never a fabricated value, never a decorative fetch (§16: Home must
// not fetch data solely to look richer).
//
// Data honesty rules, enforced per module:
//   SAVE — the SAVINGS product's real goal data (the module opens
//          /savings), read ONLY from the already-initialised cached
//          savings overview provider (ref.exists → no decorative fetch).
//          Vault semantics never leak into this notice.
//   P2P  — the USER-FACING offer market (/p2p/ads), read ONLY from the
//          already-initialised cached adsProvider (ref.exists → no
//          decorative fetch, the global market provider is never
//          initialised from Home). The vendor-owned /ads/mine list
//          (tradeProvider.myActiveAds) is NOT a live offer market and can
//          never produce a "offers live" notice.
//   SUSU — the susu list Home already watches; the relevant group is
//          chosen DETERMINISTICALLY (earliest upcoming scheduled
//          contribution), and the SAME group drives both the notice text
//          and the navigation target.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/marketplace_provider.dart';
import 'package:azaman/providers/savings_overview_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/p2p/p2p_marketplace_screen.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/nav_transitions.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:azaman/widgets/scale_tap.dart';

/// One notice-board line: [populated] distinguishes real contextual data
/// (true) from the educational copy (false) — the rule from the brief.
class WalletNotice {
  final String line;
  final bool populated;
  const WalletNotice._(this.line, this.populated);

  const WalletNotice.educational(String line) : this._(line, false);
  const WalletNotice.real(String line) : this._(line, true);
}

// ── NOTICE-BOARD PROVIDERS ────────────────────────────────────────────────

/// SAVE. The module opens /savings, so the notice represents the SAVINGS
/// product. `ref.exists` is load-bearing: it returns false (and initialises
/// nothing) when the savings overview provider has never been built — i.e.
/// the user has not opened Savings — so Home never triggers a savings fetch
/// just to decorate the notice board. Vault data is never read here.
final saveModuleNoticeProvider = Provider<WalletNotice>((ref) {
  if (!ref.exists(savingsOverviewProvider)) {
    return const WalletNotice.educational(
        "Put money aside for something you're building.");
  }
  final overview = ref.watch(savingsOverviewProvider).valueOrNull;
  final goal = overview?.mostRelevantGoal();
  if (goal == null) {
    return const WalletNotice.educational(
        "Put money aside for something you're building.");
  }
  final name = goal['name']?.toString() ?? 'your goal';
  final current = (goal['currentAmountGhs'] as num?)?.toDouble() ?? 0.0;
  final target = (goal['targetAmountGhs'] as num?)?.toDouble() ?? 0.0;
  if (target <= 0) {
    return const WalletNotice.educational(
        "Put money aside for something you're building.");
  }
  final progress = (current / target).clamp(0.0, 1.0);
  return WalletNotice.real(
      '${AzMoney.ghs(current)} · ${name.split(' ').first} ${(progress * 100).round()}%');
});

/// P2P. The notice represents the USER-FACING offer market (`/p2p/ads`).
/// `ref.exists` is load-bearing: it initialises nothing, so Home never
/// boots the global market provider just to decorate itself. When the
/// market IS cached (the user visited the marketplace), the real offer
/// count shows. The vendor-owned `tradeProvider.myActiveAds` list is
/// deliberately NOT read here: a user's own ads must never produce a false
/// "offers live" notice.
final p2pModuleNoticeProvider = Provider<WalletNotice>((ref) {
  if (!ref.exists(adsProvider)) {
    return const WalletNotice.educational(
        'Buy or sell directly with verified vendors.');
  }
  final offers = ref.watch(adsProvider).valueOrNull ?? const <AdListing>[];
  if (offers.isEmpty) {
    return const WalletNotice.educational(
        'Buy or sell directly with verified vendors.');
  }
  final n = offers.length;
  return WalletNotice.real(
      '$n offer${n == 1 ? '' : 's'} live · Buy / Sell');
});

/// SUSU. Same authoritative list Home already watches. The relevant group
/// is chosen DETERMINISTICALLY — the earliest upcoming scheduled
/// contribution among ACTIVE groups (groups without a schedule lose to
/// scheduled ones; ties broken by group id so the choice is stable) — and
/// the SAME selection drives both the notice text and the navigation
/// target.
SusuSummary? chooseMostRelevantSusu(List<SusuSummary> groups) {
  SusuSummary? best;
  DateTime? bestRunAt;
  for (final g in groups) {
    if (g.status != SusuStatus.active) continue;
    final runAt = g.nextCycle?.scheduledRunAt;
    if (best == null) {
      best = g;
      bestRunAt = runAt;
      continue;
    }
    if (runAt == null) continue; // best already chosen; unscheduled loses
    if (bestRunAt == null || runAt.isBefore(bestRunAt)) {
      best = g;
      bestRunAt = runAt;
    }
  }
  return best;
}

/// SUSU notice for [group] — null when no active group exists.
WalletNotice susuNoticeFor(SusuSummary? group) {
  if (group == null) {
    return const WalletNotice.educational(
        'Save together with your circle.');
  }
  final runAt = group.nextCycle?.scheduledRunAt;
  final cycle = group.nextCycle?.cycleNumber ?? 1;
  final total = group.totalCycles > 0 ? group.totalCycles : 1;
  if (runAt == null) {
    return WalletNotice.real('Cycle $cycle of $total');
  }
  final days = runAt.difference(DateTime.now()).inDays;
  final when = days <= 0
      ? 'today'
      : days == 1
          ? 'tomorrow'
          : 'in $days days';
  return WalletNotice.real(
      'Next contribution $when · Cycle $cycle of $total');
}

final susuModuleNoticeProvider = Provider<WalletNotice>((ref) {
  final groups =
      ref.watch(susuListProvider).valueOrNull ?? const <SusuSummary>[];
  return susuNoticeFor(chooseMostRelevantSusu(groups));
});

// ── WIDGETS ───────────────────────────────────────────────────────────────

class WalletModulesRow extends ConsumerWidget {
  const WalletModulesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
      // IntrinsicHeight so the three tiles share the tallest module's
      // height — the parent Column gives unbounded height, so a bare
      // CrossAxisAlignment.stretch would assert.
      child: IntrinsicHeight(
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: WalletModule(
              key: const ValueKey('wallet-module-save'),
              icon: HugeIconsSolid.piggyBank,
              label: 'Save',
              notice: ref.watch(saveModuleNoticeProvider),
              onTap: () {
                AzamanHaptics.nav();
                context.push('/savings');
              },
            ),
          ),
          const SizedBox(width: AzSpace.md),
          Expanded(
            child: WalletModule(
              key: const ValueKey('wallet-module-p2p'),
              icon: HugeIconsSolid.creditCard,
              label: 'P2P',
              notice: ref.watch(p2pModuleNoticeProvider),
              onTap: () {
                AzamanHaptics.nav();
                pushWithVerticalTransition(context, const P2PMarketplaceScreen());
              },
            ),
          ),
          const SizedBox(width: AzSpace.md),
          const Expanded(child: _SusuModule()),
        ],
        ),
      ),
    );
  }
}

/// Susu module — needs the notice + a data-aware destination (active group
/// detail when one exists, hub otherwise), same as the old shortcut card.
class _SusuModule extends ConsumerWidget {
  const _SusuModule();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups =
        ref.watch(susuListProvider).valueOrNull ?? const <SusuSummary>[];
    // The SAME deterministic selection the notice uses — the notice text
    // and the navigation target can never disagree.
    final active = chooseMostRelevantSusu(groups);
    return WalletModule(
      key: const ValueKey('wallet-module-susu'),
      icon: HugeIconsSolid.userGroup,
      label: 'Susu',
      notice: ref.watch(susuModuleNoticeProvider),
      onTap: () {
        AzamanHaptics.nav();
        context.push(active != null ? '/susu/${active.id}' : '/susu');
      },
    );
  }
}

/// One compact capability tile: icon, label, and the small notice board
/// attached beneath — NOT a second card.
class WalletModule extends ConsumerWidget {
  const WalletModule({
    super.key,
    required this.icon,
    required this.label,
    required this.notice,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final WalletNotice notice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return ScaleTap(
      onTap: onTap,
      child: PremiumGlassContainer(
        blur: 10,
        opacity: 0.05,
        borderRadius: 18,
        padding: const EdgeInsets.all(AzSpace.lg),
        enableShadow: false,
        border: Border.all(color: colors.divider, width: 0.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: colors.accent),
                const SizedBox(width: AzSpace.sm),
                Expanded(
                  child: Text(
                    label,
                    style: AzText.title.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AzSpace.sm),
            // The notice board: real data reads in the app's primary text;
            // educational copy reads as a quiet caption.
            Text(
              notice.line,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AzText.bodyS.copyWith(
                color: notice.populated
                    ? colors.textPrimary
                    : colors.textTertiary,
                fontWeight:
                    notice.populated ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
