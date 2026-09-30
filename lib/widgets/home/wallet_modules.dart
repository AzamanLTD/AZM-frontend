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
//   SAVE — vaults are read ONLY if the vault provider was already
//          initialised elsewhere (ref.exists, no listening → no fetch).
//   P2P  — the in-memory active-ad count from the trade provider, read
//          without triggering a fetch.
//   SUSU — the susu list Home already watches (NEW-D data logic, kept).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/providers/vault_provider.dart';
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

/// SAVE. `ref.exists` is load-bearing: it returns false (and initialises
/// nothing) when the vault provider has never been built, so Home never
/// triggers a vault fetch just to decorate the notice board.
final saveModuleNoticeProvider = Provider<WalletNotice>((ref) {
  if (!ref.exists(vaultsProvider)) {
    return const WalletNotice.educational(
        "Put money aside for something you're building.");
  }
  final vaults = ref.watch(vaultsProvider).valueOrNull ?? const <Vault>[];
  Vault? active;
  for (final v in vaults) {
    if (v.status == 'ACTIVE') {
      active = v;
      break;
    }
  }
  if (active == null || active.targetAmountUsdc <= 0) {
    return const WalletNotice.educational(
        "Put money aside for something you're building.");
  }
  final progress = (active.currentAmountUsdc / active.targetAmountUsdc)
      .clamp(0.0, 1.0);
  return WalletNotice.real(
      '${AzMoney.usdc(active.currentAmountUsdc)} saved · Goal ${(progress * 100).round()}%');
});

/// P2P. In-memory active ads only — no fetch is triggered by watching here.
final p2pModuleNoticeProvider = Provider<WalletNotice>((ref) {
  final ads = ref.watch(tradeProvider.select((t) => t.myActiveAds.length));
  if (ads <= 0) {
    return const WalletNotice.educational(
        'Buy or sell directly with verified vendors.');
  }
  return WalletNotice.real(
      '$ads offer${ads == 1 ? '' : 's'} live · Buy / Sell');
});

/// SUSU. Same authoritative list Home already watches.
final susuModuleNoticeProvider = Provider<WalletNotice>((ref) {
  final groups = ref.watch(susuListProvider).valueOrNull ?? const <SusuSummary>[];
  SusuSummary? active;
  for (final g in groups) {
    if (g.status == SusuStatus.active) {
      active = g;
      break;
    }
  }
  if (active == null) {
    return const WalletNotice.educational(
        'Save together with your circle.');
  }
  final runAt = active.nextCycle?.scheduledRunAt;
  final cycle = active.nextCycle?.cycleNumber ?? 1;
  final total = active.totalCycles > 0 ? active.totalCycles : 1;
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
    SusuSummary? active;
    for (final g in groups) {
      if (g.status == SusuStatus.active) {
        active = g;
        break;
      }
    }
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
