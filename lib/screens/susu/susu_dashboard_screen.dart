// =============================================================================
// SUSU DASHBOARD SCREEN — Phase 4 (Master Sprint, 2026-05-31)
//
// The single member-facing dashboard for a Susu created via the new
// invite-channel flow. Composes:
//
//   • Hero card           — name, status pill, contribution amount, frequency
//   • Privacy-projected
//     member roster       — display name, avatar, payoutSlot, status (Req 5.4)
//   • Cycle schedule      — collection date, payoutSlot recipient
//   • Upcoming-cycle card — next contribution, "Fund Account" deep-link
//                           when shortfall ≥ $0.01 (Req 12.2 / 12.3)
//   • Frozen banner       — when Susu.status = FROZEN_DISPUTE (Req 11.10)
//
// The screen subscribes to `susu_${susuId}` socket events through the
// `susuDetailV2Provider` notifier (which auto-joins the room on first
// build and leaves on dispose). This keeps the UI in sync with cycle
// execution, member status flips, and Circuit Breaker fires without
// requiring polling.
//
// Privacy: every read here goes through the V2 provider stack which is
// gated server-side on ACTIVE membership. We never expose AZM rank
// keys, availableBalance of co-members, or contact info — those are
// stripped at the API layer (Property 15).
//
// UI guardrails: existing themed background (Eclipse Glow etc.) is
// preserved by leaving Scaffold.backgroundColor transparent.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/susu_service.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class SusuDashboardScreen extends ConsumerWidget {
  final String susuId;
  const SusuDashboardScreen({super.key, required this.susuId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final detail = ref.watch(susuDetailV2Provider(susuId));
    final members = ref.watch(susuMembersProvider(susuId));
    final cycles = ref.watch(susuCyclesProvider(susuId));
    final me = ref.watch(currentUserProvider).value;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01,
              color: colors.textPrimary, size: 18),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/susu');
            }
          },
        ),
        title: detail.maybeWhen(
          data: (s) => Text(
            s.name,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          orElse: () => Text(
            'Susu',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: colors.warning,
          onRefresh: () async {
            // Force-refresh all four data streams in parallel.
            ref.invalidate(susuDetailV2Provider(susuId));
            ref.invalidate(susuMembersProvider(susuId));
            ref.invalidate(susuCyclesProvider(susuId));
            await Future.wait([
              ref.read(susuDetailV2Provider(susuId).future),
              ref.read(susuMembersProvider(susuId).future),
              ref.read(susuCyclesProvider(susuId).future),
            ]);
          },
          child: detail.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: colors.warning),
            ),
            error: (e, _) => _ErrorView(error: e, colors: colors),
            data: (susu) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _Hero(susu: susu, colors: colors)
                    .animate()
                    .fadeIn(duration: 320.ms)
                    .slideY(begin: 0.05, end: 0),
                if (susu.status == SusuStatus.frozenDispute)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _FrozenBanner(susu: susu, colors: colors),
                  ),
                if (susu.status == SusuStatus.configuring &&
                    _isPendingContractFor(me?.id, members.value))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _AcceptContractCta(
                      susuId: susu.id,
                      colors: colors,
                    ),
                  ),
                const SizedBox(height: 16),
                _UpcomingCycleCard(
                  susu: susu,
                  cycles: cycles.valueOrNull ?? const [],
                  members: _bestMembers(susu, members.valueOrNull),
                  meId: me?.id,
                  meAvailableBalance: me?.availableBalance ?? 0.0,
                  colors: colors,
                ),
                if (susu.status == SusuStatus.active) ...[
                  const SizedBox(height: 12),
                  _AutoRetainCard(susuId: susu.id, colors: colors),
                ],
                const SizedBox(height: 18),
                _SectionTitle('Members', colors: colors),
                const SizedBox(height: 8),
                _MembersRoster(
                  members: _bestMembers(susu, members.valueOrNull),
                  meUserId: me?.id,
                  colors: colors,
                ),
                if (cycles.valueOrNull != null && cycles.valueOrNull!.isNotEmpty)
                  _SusuPayoutTimeline(
                    cycles: cycles.valueOrNull!,
                    currentUserId: me?.id,
                    colors: colors,
                  ),
                const SizedBox(height: 18),
                _SectionTitle('Cycle schedule', colors: colors),
                const SizedBox(height: 8),
                _CycleSchedule(
                  cycles: cycles,
                  members: _bestMembers(susu, members.valueOrNull),
                  colors: colors,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The dashboard prefers the roster from `susuDetailV2Provider` because
  /// those member rows carry `userId` (needed for the "YOU" highlight and
  /// isMe comparisons). The separate `susuMembersProvider` roster is
  /// privacy-minimal and omits userId; we fall back to it only if the
  /// detail somehow returned no members.
  List<SusuMemberView> _bestMembers(
      SusuDetail susu, List<SusuMemberView>? rosterFallback) {
    if (susu.members.isNotEmpty) return susu.members;
    return rosterFallback ?? const [];
  }

  bool _isPendingContractFor(dynamic meId, List<SusuMemberView>? members) {
    if (meId == null || members == null) return false;
    final my = members
        .where((m) => m.userId.toString() == meId.toString())
        .firstOrNull;
    return my?.status == SusuMemberStatus.pendingContract;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  final SusuDetail susu;
  final AzamanColors colors;
  const _Hero({required this.susu, required this.colors});

  @override
  Widget build(BuildContext context) {
    final pool = susu.contributionUsdc * susu.totalCycles;
    final (label, color) = switch (susu.status) {
      SusuStatus.configuring => ('PENDING', colors.warning),
      SusuStatus.active => ('ACTIVE', colors.success),
      SusuStatus.completed => ('COMPLETED', colors.accent),
      SusuStatus.cancelled => ('CANCELLED', colors.textTertiary),
      SusuStatus.frozenDispute => ('FROZEN', colors.danger),
      SusuStatus.unknown => ('—', colors.textTertiary),
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.18),
            colors.accent.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.30), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(HugeIconsSolid.bank, color: color, size: 18),
              const SizedBox(width: 6),
              Text(
                'Susu · ${susu.frequency.label}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(4),
                  border:
                      Border.all(color: color.withOpacity(0.30), width: 0.7),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '\$${pool.toStringAsFixed(2)}',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          Text(
            'Pool · ${susu.totalCycles} cycles · '
            '\$${susu.contributionUsdc.toStringAsFixed(2)} per cycle',
            style: TextStyle(color: colors.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _FrozenBanner extends StatelessWidget {
  final SusuDetail susu;
  final AzamanColors colors;
  const _FrozenBanner({required this.susu, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.danger.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          Icon(HugeIconsSolid.lock, color: colors.danger, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Frozen by Circuit Breaker (${susu.frozenReason ?? 'admin review'}).'
              ' Cycle execution and member actions are paused pending operator review.',
              style: TextStyle(
                color: colors.danger,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AcceptContractCta extends StatelessWidget {
  final String susuId;
  final AzamanColors colors;
  const _AcceptContractCta({required this.susuId, required this.colors});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => context.push('/susu/$susuId/contract'),
      icon: const Icon(HugeIconsSolid.judge, size: 16),
      label: const Text(
        'Read & sign Liability Contract',
        style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.warning,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _UpcomingCycleCard extends StatelessWidget {
  final SusuDetail susu;
  final List<SusuCycleView> cycles;
  final List<SusuMemberView> members;
  final dynamic meId;
  final double meAvailableBalance;
  final AzamanColors colors;
  const _UpcomingCycleCard({
    required this.susu,
    required this.cycles,
    required this.members,
    required this.meId,
    required this.meAvailableBalance,
    required this.colors,
  });

  SusuCycleView? get _next {
    for (final c in cycles) {
      if (c.status == SusuCycleStatus.pending ||
          c.status == SusuCycleStatus.collecting ||
          c.status == SusuCycleStatus.collectingGrace) {
        return c;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final next = _next;
    if (next == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Icon(HugeIconsSolid.checkmarkCircle01,
                color: colors.success, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No upcoming cycles. The Susu has either completed or is awaiting activation.',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    final shortfall = (susu.contributionUsdc - meAvailableBalance);
    final ready = shortfall <= 0.0;

    final recipient = members
        .where((m) => m.userId == next.payoutUserId)
        .firstOrNull;
    final recipientLabel = recipient == null
        ? 'recipient pending'
        : '@${recipient.displayName} (slot #${recipient.cycleSlot ?? '—'})';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ready
              ? colors.success.withOpacity(0.30)
              : colors.warning.withOpacity(0.30),
          width: 0.7,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(HugeIconsSolid.clock01,
                  color: ready ? colors.success : colors.warning, size: 16),
              const SizedBox(width: 6),
              Text(
                'Upcoming Cycle ${next.cycleNumber}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Due ${_fmtDate(next.scheduledRunAt)} · payout to $recipientLabel',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _BalanceLine(
                  label: 'You owe',
                  amount: '\$${susu.contributionUsdc.toStringAsFixed(2)}',
                  colors: colors,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BalanceLine(
                  label: 'Your balance',
                  amount: '\$${meAvailableBalance.toStringAsFixed(2)}',
                  amountColor: ready ? colors.success : colors.warning,
                  colors: colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (ready)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colors.success.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: colors.success.withOpacity(0.30), width: 0.7),
              ),
              child: Row(
                children: [
                  Icon(HugeIconsSolid.checkmarkCircle01,
                      color: colors.success, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Ready for cycle',
                    style: TextStyle(
                      color: colors.success,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Req 12.3 deep link — preserve two-decimal formatting.
                  final amount = shortfall.toStringAsFixed(2);
                  final memo = Uri.encodeComponent('susu:${susu.id}');
                  context.push('/deposit?amount=$amount&memo=$memo');
                },
                icon: const Icon(HugeIconsSolid.wallet01,
                    size: 16),
                label: Text(
                  'Fund \$${shortfall.toStringAsFixed(2)} to cover cycle',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.warning,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    final mo = l.month.toString().padLeft(2, '0');
    final dy = l.day.toString().padLeft(2, '0');
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '$mo-$dy $h:$m';
  }
}

class _BalanceLine extends StatelessWidget {
  final String label;
  final String amount;
  final Color? amountColor;
  final AzamanColors colors;
  const _BalanceLine({
    required this.label,
    required this.amount,
    required this.colors,
    this.amountColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            amount,
            style: TextStyle(
              color: amountColor ?? colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MembersRoster extends StatelessWidget {
  final List<SusuMemberView> members;
  final dynamic meUserId;
  final AzamanColors colors;
  const _MembersRoster({
    required this.members,
    required this.meUserId,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final rows = members;
    if (rows.isEmpty) {
      return Text(
        'Roster is hidden until you reach ACTIVE status.',
        style: TextStyle(color: colors.textTertiary, fontSize: 11),
      );
    }
    return Column(
          children: rows.asMap().entries.map((e) {
            final m = e.value;
            final isMe = meUserId != null &&
                m.userId.toString() == meUserId.toString();
            final (statusLabel, statusColor) = switch (m.status) {
              SusuMemberStatus.pendingVouch =>
                ('PENDING_VOUCH', colors.warning),
              SusuMemberStatus.pendingContract =>
                ('PENDING_CONTRACT', colors.warning),
              SusuMemberStatus.active => ('ACTIVE', colors.success),
              SusuMemberStatus.defaulted => ('DEFAULTED', colors.danger),
              SusuMemberStatus.removed => ('REMOVED', colors.textTertiary),
              SusuMemberStatus.unknown => ('—', colors.textTertiary),
            };
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.divider, width: 0.6),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: colors.accent.withOpacity(0.15),
                      child: Text(
                        m.displayName.isEmpty
                            ? '?'
                            : m.displayName[0].toUpperCase(),
                        style: TextStyle(
                          color: colors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '@${m.displayName}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: colors.accent.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'YOU',
                                    style: TextStyle(
                                      color: colors.accent,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                              if (m.role.toUpperCase() == 'ADMIN') ...[
                                const SizedBox(width: 4),
                                Icon(HugeIconsSolid.shield01,
                                    color: colors.warning, size: 12),
                              ],
                            ],
                          ),
                          Text(
                            'Slot #${m.cycleSlot ?? '—'}',
                            style: TextStyle(
                                color: colors.textTertiary, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: statusColor.withOpacity(0.30),
                            width: 0.7),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: (e.key * 30).ms, duration: 240.ms),
            );
          }).toList(),
        );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _CycleSchedule extends StatelessWidget {
  final AsyncValue<List<SusuCycleView>> cycles;
  final List<SusuMemberView> members;
  final AzamanColors colors;
  const _CycleSchedule({
    required this.cycles,
    required this.members,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return cycles.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text(
        e.toString(),
        style: TextStyle(color: colors.danger, fontSize: 11),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Text(
            'Cycles will be scheduled when the Susu activates.',
            style: TextStyle(color: colors.textTertiary, fontSize: 11),
          );
        }
        return Column(
          children: rows.map((c) {
            final winner =
                members.where((m) => m.userId == c.payoutUserId).firstOrNull;
            final (label, color) = switch (c.status) {
              SusuCycleStatus.pending => ('PENDING', colors.textTertiary),
              SusuCycleStatus.collecting => ('COLLECTING', colors.warning),
              SusuCycleStatus.collectingGrace => ('GRACE 24H', colors.danger),
              SusuCycleStatus.paidOut => (
                  c.escrowDivertedAt != null ? 'DIVERTED' : 'PAID',
                  c.escrowDivertedAt != null ? colors.warning : colors.success
                ),
              SusuCycleStatus.defaulted => ('DEFAULTED', colors.danger),
              SusuCycleStatus.unknown => ('—', colors.textTertiary),
            };
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.divider, width: 0.6),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: colors.accent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '#${c.cycleNumber}',
                        style: TextStyle(
                          color: colors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '@${winner?.displayName ?? '—'}'
                            ' · \$${(c.payoutAmount ?? 0).toStringAsFixed(2)}',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            c.scheduledRunAt.toLocal().toString().split('.').first,
                            style: TextStyle(
                                color: colors.textTertiary, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: color.withOpacity(0.30), width: 0.7),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String _title;
  final AzamanColors colors;
  const _SectionTitle(this._title, {required this.colors});

  @override
  Widget build(BuildContext context) => Text(
        _title.toUpperCase(),
        style: TextStyle(
          color: colors.textTertiary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      );
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final AzamanColors colors;
  const _ErrorView({required this.error, required this.colors});

  @override
  Widget build(BuildContext context) {
    final msg = error.toString();
    final notFound = msg.contains('SUSU_NOT_FOUND') || msg.contains('404');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              notFound ? HugeIconsSolid.lock : HugeIconsSolid.alertCircle,
              size: 48,
              color: colors.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              notFound ? 'Susu not visible' : 'Could not load Susu',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              notFound
                  ? 'You either are not a member, your acceptance is still '
                      'pending, or the Susu does not exist.'
                  : msg,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textTertiary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

extension _IterFirst<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// =============================================================================
// AUTO-RETAIN CARD — Phase 5 / Workstream B (2026-06-01)
//
// Educates members that they don't have to withdraw a whole payout at once —
// they can withdraw bit by bit and keep a balance to auto-cover the next
// cycle. Offers an opt-in toggle (POST /api/susu/:id/auto-retain) so the
// platform reserves the next contribution after a payout, removing the need
// for a manual top-up (honoured by the funding logic in Workstream C).
// =============================================================================
class _AutoRetainCard extends ConsumerStatefulWidget {
  final String susuId;
  final AzamanColors colors;
  const _AutoRetainCard({required this.susuId, required this.colors});

  @override
  ConsumerState<_AutoRetainCard> createState() => _AutoRetainCardState();
}

class _AutoRetainCardState extends ConsumerState<_AutoRetainCard> {
  bool _enabled = false;
  bool _busy = false;
  bool _initialised = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    // Seed initial value from the detail's member projection once.
    if (!_initialised) {
      final detail = ref.read(susuDetailV2Provider(widget.susuId)).valueOrNull;
      final me = ref.read(currentUserProvider).value;
      final mine = detail?.members
          .where((m) => m.userId.toString() == me?.id.toString())
          .toList();
      if (mine != null && mine.isNotEmpty) {
        _enabled = mine.first.autoRetainNextCycle;
        _initialised = true;
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(HugeIconsSolid.savings, color: colors.accent, size: 16),
              const SizedBox(width: 8),
              Text('Make payouts work for you',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'You don\'t have to withdraw your whole payout at once. Withdraw '
            'bit by bit and keep some balance on the app — your next '
            'contribution is then ready without a manual top-up.',
            style: TextStyle(
                color: colors.textSecondary, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            value: _enabled,
            onChanged: _busy
                ? null
                : (v) async {
                    setState(() {
                      _enabled = v;
                      _busy = true;
                    });
                    try {
                      await susuService.setAutoRetain(widget.susuId, v);
                      ref.invalidate(susuDetailV2Provider(widget.susuId));
                    } catch (e) {
                      if (mounted) {
                        setState(() => _enabled = !v); // revert
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString())),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            activeColor: colors.accent,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Auto-retain next contribution',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Reserve my next cycle amount from my balance after each payout.',
              style: TextStyle(color: colors.textTertiary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _SusuPayoutTimeline extends StatelessWidget {
  final List<SusuCycleView> cycles;
  final String? currentUserId;
  final AzamanColors colors;

  const _SusuPayoutTimeline({
    required this.cycles,
    required this.currentUserId,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final mySlotIndex = cycles.indexWhere((cycle) =>
      cycle.payoutUserId.toString() == currentUserId);
    final nextPendingIndex = cycles.indexWhere((cycle) =>
      cycle.status == SusuCycleStatus.pending || cycle.status == SusuCycleStatus.collecting || cycle.status == SusuCycleStatus.collectingGrace);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (nextPendingIndex >= 0) ...[
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              colors.accent.withOpacity(0.15),
              colors.accent.withOpacity(0.05)]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.accent.withOpacity(0.25)),
          ),
          child: Row(children: [
            Icon(HugeIconsSolid.calendarCheckIn01, color: colors.accent, size: 24),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Next Payout — Slot ${nextPendingIndex + 1}",
                style: TextStyle(color: colors.accent,
                  fontSize: 13, fontWeight: FontWeight.w800)),
              Text(
                cycles[nextPendingIndex].payoutUserId.toString() == currentUserId
                  ? "Your turn!"
                  : "Slot #${nextPendingIndex + 1}",
                style: TextStyle(color: colors.textPrimary,
                  fontSize: 16, fontWeight: FontWeight.w900)),
              Text(
                _fmtDateInline(cycles[nextPendingIndex].scheduledRunAt),
                style: TextStyle(color: colors.textSecondary, fontSize: 12)),
            ])),
            if (mySlotIndex >= 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text("Your slot: #${mySlotIndex + 1}",
                  style: const TextStyle(color: Colors.white,
                    fontSize: 11, fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
      ],
      SizedBox(
        height: 70,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 12),
          itemCount: cycles.length,
          itemBuilder: (_, i) {
            final cycle = cycles[i];
            final isMe = cycle.payoutUserId.toString() == currentUserId;
            final isDone = cycle.status == SusuCycleStatus.paidOut;
            final isNext = i == nextPendingIndex;
            final color = isDone ? colors.success
                : isMe   ? colors.accent
                : colors.softSurface;
            return Container(
              width: 52, margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: color.withOpacity(isDone || isMe ? 0.15 : 1.0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isNext ? colors.accent : colors.divider,
                  width: isNext ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("#${i + 1}",
                    style: TextStyle(
                      color: isDone ? colors.success : isMe ? colors.accent : colors.textTertiary,
                      fontSize: 14, fontWeight: FontWeight.w800)),
                  if (isDone)
                    Icon(Icons.check, color: colors.success, size: 14)
                  else if (isMe)
                    Icon(HugeIconsSolid.user, color: colors.accent, size: 12)
                  else
                    const SizedBox.shrink(),
                ],
              ),
            );
          },
        ),
      ),
    ]);
  }

  String _fmtDateInline(DateTime dt) {
    final months = ["Jan","Feb","Mar","Apr","May","Jun",
                    "Jul","Aug","Sep","Oct","Nov","Dec"];
    return "${dt.day} ${months[dt.month - 1]} ${dt.year}";
  }
}
