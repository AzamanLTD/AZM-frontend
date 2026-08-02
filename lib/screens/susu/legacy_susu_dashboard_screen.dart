// =============================================================================
// LEGACY SUSU DASHBOARD SCREEN  (Master Sprint, 2026-05-27)
//
// Pre-Phase-4 dashboard, GroupChat-keyed. Still wired into the legacy
// GroupChat → "Configure Susu" flow used by `group_chat_screen.dart` and
// the Savings tab. The Phase 4 (2026-05-31) `SusuDashboardScreen` lives
// alongside it and is keyed off `/susu/:id` (Susu id, not GroupChat id);
// new Susus created via `SusuCreateScreen` route through that new
// dashboard. Both surfaces coexist intentionally during the rollout.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/susu/susu_warning_screen.dart';
import 'package:azaman/widgets/nav_transitions.dart';


class LegacySusuDashboardScreen extends ConsumerWidget {
  final String susuGroupId;
  const LegacySusuDashboardScreen({super.key, required this.susuGroupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final susuAsync = ref.watch(susuDetailProvider(susuGroupId));
    final me = ref.watch(currentUserProvider).value;
    final myId = me?.id;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Susu',
            style: TextStyle(
                color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: susuAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (susu) {
          if (susu == null) return const Center(child: Text('Susu not found'));
          // Match user id to int (backend returns int) — auth user.id is String|int.
          final myMember = myId == null
              ? null
              : susu.members.where((m) => m.userId.toString() == myId.toString()).firstOrNull;

          final needsContract =
              susu.status == 'CONFIGURING' && myMember?.status == 'PENDING_CONTRACT';

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _Hero(susu: susu, colors: colors)
                  .animate()
                  .fadeIn(duration: 320.ms)
                  .slideY(begin: 0.05, end: 0),
              const SizedBox(height: 16),
              if (myMember != null) _MyPosition(member: myMember, colors: colors),
              if (needsContract) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    pushWithVerticalTransition(context, SusuWarningScreen(susuGroupId: susu.id,
                          contributionUsdc: susu.contributionUsdc,
                          frequency: susu.frequency,
                          totalCycles: susu.totalCycles,));
                  },
                  icon: const Icon(Icons.gavel, size: 16),
                  label: const Text(
                    'Read Contract & Sign',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.warning,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                'Cycle Schedule',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              ...susu.cycles.asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _CycleTile(
                        cycle: e.value,
                        members: susu.members,
                        colors: colors,
                      )
                          .animate()
                          .fadeIn(delay: (e.key * 40).ms, duration: 280.ms)
                          .slideY(begin: 0.04, end: 0),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final SusuGroup susu;
  final AzamanColors colors;
  const _Hero({required this.susu, required this.colors});

  @override
  Widget build(BuildContext context) {
    final pool = susu.contributionUsdc * susu.totalCycles;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.warning.withValues(alpha: 0.18),
            colors.accent.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.warning.withValues(alpha: 0.30), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_outlined, color: colors.warning, size: 18),
              const SizedBox(width: 6),
              Text(
                'Susu · ${susu.frequency}',
                style: TextStyle(
                    color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.warning.withValues(alpha: 0.30), width: 0.7),
                ),
                child: Text(
                  susu.status,
                  style: TextStyle(
                    color: colors.warning,
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
            'Pool size · ${susu.totalCycles} cycles · \$${susu.contributionUsdc.toStringAsFixed(2)} per cycle',
            style: TextStyle(color: colors.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _MyPosition extends StatelessWidget {
  final SusuMember member;
  final AzamanColors colors;
  const _MyPosition({required this.member, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.accent.withValues(alpha: 0.10),
              border: Border.all(color: colors.accent.withValues(alpha: 0.30), width: 0.7),
            ),
            alignment: Alignment.center,
            child: Text(
              '#${member.cycleSlot}',
              style: TextStyle(
                color: colors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Your Slot · #${member.cycleSlot}',
                  style: TextStyle(
                      color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Trust ${member.trustScore.toStringAsFixed(1)} · ${member.status}',
                  style: TextStyle(color: colors.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CycleTile extends StatelessWidget {
  final SusuCycle cycle;
  final List<SusuMember> members;
  final AzamanColors colors;
  const _CycleTile(
      {required this.cycle, required this.members, required this.colors});

  @override
  Widget build(BuildContext context) {
    final winner = members.where((m) => m.userId == cycle.payoutUserId).firstOrNull;
    final (label, color) = switch (cycle.status) {
      'PENDING' => ('PENDING', colors.textTertiary),
      'COLLECTING' => ('COLLECTING', colors.warning),
      'PAID_OUT' => ('PAID', colors.success),
      'DEFAULTED' => ('DEFAULTED', colors.danger),
      _ => ('—', colors.textTertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              color: colors.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              '#${cycle.cycleNumber}',
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
                  '@${winner?.username ?? '—'} · \$${cycle.payoutAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                      color: colors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                Text(
                  '${cycle.collectionDate.toLocal()}'.split('.').first,
                  style: TextStyle(color: colors.textTertiary, fontSize: 10),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.30), width: 0.7),
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
    );
  }
}

extension _IterFirst<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
