// =============================================================================
// GROUP PROFILE SCREEN — Phase 5 / Workstream D (2026-06-01)
//
// Opened by tapping the group header in GroupChatScreen. Shows:
//   • member bubbles (avatar cluster) + full roster
//   • per-member KYC / PoA verification chips (red/yellow/green) when the
//     group is initiating a Susu
//   • add-member control (admin) for plain groups
//   • "Initiate Susu" control (admin) for plain groups → opens the config
//     sheet with dynamic pool math
//   • initiation summary + cancel (admin) while a Susu is configuring
//
// Reuses group_chat_provider (groupDetailProvider, susuInitiationStatusProvider,
// groupActionsProvider) and susuSuppliedRateProvider for cedis conversion.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/susu/initiate_susu_sheet.dart';
import 'package:azaman/widgets/susu/verification_chip.dart';

class GroupProfileScreen extends ConsumerWidget {
  final String groupId;
  const GroupProfileScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final groupAsync = ref.watch(groupDetailProvider(groupId));
    final initAsync = ref.watch(susuInitiationStatusProvider(groupId));
    final me = ref.watch(currentUserProvider).value;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Group',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: colors.warning,
          onRefresh: () async {
            ref.invalidate(groupDetailProvider(groupId));
            ref.invalidate(susuInitiationStatusProvider(groupId));
            await ref.read(groupDetailProvider(groupId).future);
          },
          child: groupAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(e.toString())),
            data: (group) {
              if (group == null) {
                return const Center(child: Text('Group not found'));
              }
              final init = initAsync.valueOrNull;
              final myMember = group.members
                  .where((m) => m.userId.toString() == me?.id.toString())
                  .toList();
              final iAmAdmin =
                  myMember.isNotEmpty && myMember.first.role == 'ADMIN';
              final hasSusu = init?.susuGroupId != null;
              final isConfiguring = init?.isConfiguring == true;

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  _Header(group: group, colors: colors),
                  const SizedBox(height: 18),

                  // ── Susu initiation summary / CTA ──────────────────────
                  if (isConfiguring && init != null)
                    _InitiationSummary(
                      groupId: groupId,
                      init: init,
                      iAmAdmin: iAmAdmin,
                      colors: colors,
                    )
                  else if (init?.isActive == true)
                    _ActiveSusuBadge(colors: colors)
                  else if (iAmAdmin)
                    _InitiateCta(
                      colors: colors,
                      memberCount: group.members.length,
                      onTap: () => _openInitiateSheet(context, ref, group),
                    ),

                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text(
                        'MEMBERS · ${group.members.length}',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const Spacer(),
                      if (iAmAdmin && !hasSusu)
                        TextButton.icon(
                          onPressed: () => _addMember(context, ref),
                          icon: Icon(Icons.person_add_alt_1_rounded,
                              size: 15, color: colors.accent),
                          label: Text('Add',
                              style: TextStyle(
                                  color: colors.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._buildRoster(group, init, colors, me?.id.toString()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildRoster(
    GroupSummary group,
    SusuInitiationStatus? init,
    AzamanColors colors,
    String? myId,
  ) {
    // Index initiation member projections by userId for the chips.
    final initByUser = {
      for (final m in (init?.members ?? const <SusuInitiationMember>[]))
        m.userId: m,
    };
    final showChips = init?.isConfiguring == true;

    return group.members.map((gm) {
      final proj = initByUser[gm.userId];
      final isMe = myId != null && gm.userId.toString() == myId;
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.divider, width: 0.6),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: colors.accent.withOpacity(0.15),
              child: Text(
                (gm.username ?? '?').isNotEmpty
                    ? gm.username![0].toUpperCase()
                    : '?',
                style: TextStyle(
                    color: colors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800),
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
                          '@${gm.username ?? 'member'}',
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
                        _youTag(colors),
                      ],
                      if (gm.role == 'ADMIN') ...[
                        const SizedBox(width: 4),
                        Icon(Icons.shield_rounded,
                            color: colors.warning, size: 12),
                      ],
                    ],
                  ),
                  if (showChips && proj != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        VerificationChip(
                          label: 'KYC',
                          state: proj.kycChip,
                          colors: colors,
                        ),
                        const SizedBox(width: 6),
                        VerificationChip(
                          label: 'PoA',
                          state: proj.poaChip,
                          colors: colors,
                        ),
                        if (proj.ready) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.check_circle_rounded,
                              color: colors.success, size: 14),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _youTag(AzamanColors colors) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: colors.accent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('YOU',
            style: TextStyle(
                color: colors.accent,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5)),
      );

  void _openInitiateSheet(
      BuildContext context, WidgetRef ref, GroupSummary group) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InitiateSusuSheet(
        groupId: group.id,
        memberCount: group.members.length,
      ),
    );
  }

  Future<void> _addMember(BuildContext context, WidgetRef ref) async {
    final colors = ref.read(themeProvider).colors;
    final controller = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Add member',
            style: TextStyle(color: colors.textPrimary, fontSize: 16)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Phone (+233…) or Azaman friend',
            hintStyle: TextStyle(color: colors.textTertiary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (phone == null || phone.isEmpty) return;
    try {
      await ref.read(groupActionsProvider).addMember(groupId, phone: phone);
      ref.invalidate(groupDetailProvider(groupId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member added')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final GroupSummary group;
  final AzamanColors colors;
  const _Header({required this.group, required this.colors});

  @override
  Widget build(BuildContext context) {
    final bubbles = group.members.take(5).toList();
    return Column(
      children: [
        // Avatar bubble cluster
        SizedBox(
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (int i = 0; i < bubbles.length; i++)
                Transform.translate(
                  offset: Offset((i - (bubbles.length - 1) / 2) * 30, 0),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.accent.withOpacity(0.18),
                      border: Border.all(color: colors.surface, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      (bubbles[i].username ?? '?').isNotEmpty
                          ? bubbles[i].username![0].toUpperCase()
                          : '?',
                      style: TextStyle(
                          color: colors.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 16),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          group.name,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900),
        ),
        if (group.description != null && group.description!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            group.description!,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _InitiateCta extends StatelessWidget {
  final AzamanColors colors;
  final int memberCount;
  final VoidCallback onTap;
  const _InitiateCta({
    required this.colors,
    required this.memberCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final canStart = memberCount >= 2 && memberCount <= 24;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          colors.warning.withOpacity(0.16),
          colors.accent.withOpacity(0.05),
        ]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.warning.withOpacity(0.30), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_rounded,
                  color: colors.warning, size: 18),
              const SizedBox(width: 8),
              Text('Start a Susu in this group',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Turn this group into a rotating savings circle. Every member '
            'verifies KYC + proof of residency within a countdown window, '
            'then payouts rotate by AZM rank.',
            style: TextStyle(
                color: colors.textSecondary, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: canStart ? onTap : null,
              icon: const Icon(Icons.rocket_launch_rounded, size: 16),
              label: Text(
                canStart
                    ? 'Initiate Susu'
                    : 'Need 2–24 members (have $memberCount)',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, letterSpacing: 0.3),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.warning,
                foregroundColor: Colors.black,
                disabledBackgroundColor: colors.warning.withOpacity(0.30),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InitiationSummary extends ConsumerWidget {
  final String groupId;
  final SusuInitiationStatus init;
  final bool iAmAdmin;
  final AzamanColors colors;
  const _InitiationSummary({
    required this.groupId,
    required this.init,
    required this.iAmAdmin,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rate = ref.watch(susuSuppliedRateProvider).valueOrNull;
    final contribution = init.contributionUsdc ?? 0;
    final pool = init.projectedPoolUsdc;
    final ghsRate = rate?.usdcToGhs ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.warning.withOpacity(0.30), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_rounded, color: colors.warning, size: 16),
              const SizedBox(width: 6),
              Text('Susu configuring',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('${init.readyCount}/${init.memberCount} ready',
                  style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          _row(colors, 'Per cycle',
              '\$${contribution.toStringAsFixed(2)}'
              '${ghsRate > 0 ? '  ≈ GH₵ ${(contribution * ghsRate).toStringAsFixed(2)}' : ''}'),
          _row(colors, 'Projected pool / cycle',
              '\$${pool.toStringAsFixed(2)}'
              '${ghsRate > 0 ? '  ≈ GH₵ ${(pool * ghsRate).toStringAsFixed(2)}' : ''}'),
          _row(colors, 'Frequency', init.frequency ?? '—'),
          if (init.deadline != null)
            _row(colors, 'Verify before', _fmt(init.deadline!)),
          if (iAmAdmin) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  try {
                    await ref
                        .read(groupActionsProvider)
                        .cancelInitiation(groupId);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    }
                  }
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.danger.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                child: Text('Cancel initiation',
                    style: TextStyle(
                        color: colors.danger, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(AzamanColors colors, String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: TextStyle(color: colors.textTertiary, fontSize: 11.5)),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  String _fmt(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

class _ActiveSusuBadge extends StatelessWidget {
  final AzamanColors colors;
  const _ActiveSusuBadge({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.success.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: colors.success, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This group is an active Susu. Open the Susu dashboard from the chat banner to see the cycle schedule.',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
