// =============================================================================
// SUSU HUB SCREEN — Phase 4 (Master Sprint, 2026-05-31)
//
// Lists the caller's own Susus, grouped by status (Pending / Active /
// Completed / Frozen). Each tile shows next-cycle countdown, payoutSlot,
// and role. The FAB routes to /susu/create.
//
// Privacy: this screen only renders Susus the caller is a member of —
// the backend's `GET /api/susu/me` already filters appropriately. We
// never call any list endpoint that could leak non-member Susus.
//
// UI guardrails: the screen sits over the existing themed background
// (Eclipse Glow, etc.) by leaving Scaffold.backgroundColor transparent.
// We never override the gamification XP bars or oracle timers — those
// belong to other surfaces (home, vendor dashboard) and are not touched.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';


class SusuHubScreen extends ConsumerWidget {
  const SusuHubScreen({super.key});

  void _showStartHelp(BuildContext context, AzamanColors colors) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Start a Susu',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text(
              'A Susu now starts inside a group chat:\n\n'
              '1.  Go to the Chat tab and create a group (or open one).\n'
              '2.  Add the members you want in the Susu.\n'
              '3.  Open the group profile and tap "Initiate Susu".\n'
              '4.  Everyone verifies KYC + proof of residency before the '
              'countdown ends, and the Susu activates automatically.',
              style: TextStyle(
                  color: colors.textSecondary, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  ctx.push('/messages');
                },
                icon: const Icon(Icons.chat_outlined, size: 16),
                label: const Text('Go to Chats',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.warning,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final listAsync = ref.watch(susuListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Susu',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.warning,
        foregroundColor: Colors.black,
        elevation: 1,
        onPressed: () => _showStartHelp(context, colors),
        icon: const Icon(Icons.add, size: 18),
        label: const Text(
          'Start a Susu',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: colors.warning,
          onRefresh: () => ref.read(susuListProvider.notifier).refresh(),
          child: listAsync.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: colors.warning),
            ),
            error: (e, _) => _ErrorView(error: e, colors: colors),
            data: (rows) => _HubBody(rows: rows, colors: colors),
          ),
        ),
      ),
    );
  }
}

class _HubBody extends StatelessWidget {
  final List<SusuSummary> rows;
  final AzamanColors colors;
  const _HubBody({required this.rows, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return _EmptyState(colors: colors);

    final pending = rows.where((s) => s.status == SusuStatus.configuring).toList();
    final active = rows.where((s) => s.status == SusuStatus.active).toList();
    final frozen =
        rows.where((s) => s.status == SusuStatus.frozenDispute).toList();
    final completed =
        rows.where((s) => s.status == SusuStatus.completed).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (frozen.isNotEmpty)
          _Section(title: 'Frozen', rows: frozen, colors: colors, danger: true),
        if (pending.isNotEmpty)
          _Section(title: 'Pending', rows: pending, colors: colors),
        if (active.isNotEmpty)
          _Section(title: 'Active', rows: active, colors: colors),
        if (completed.isNotEmpty)
          _Section(title: 'Completed', rows: completed, colors: colors),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<SusuSummary> rows;
  final AzamanColors colors;
  final bool danger;
  const _Section({
    required this.title,
    required this.rows,
    required this.colors,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              '${title.toUpperCase()} · ${rows.length}',
              style: TextStyle(
                color: danger ? colors.danger : colors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          ...rows.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SusuTile(row: e.value, colors: colors)
                      .animate()
                      .fadeIn(delay: (e.key * 35).ms, duration: 260.ms)
                      .slideY(begin: 0.04, end: 0),
                ),
              ),
        ],
      ),
    );
  }
}

class _SusuTile extends StatelessWidget {
  final SusuSummary row;
  final AzamanColors colors;
  const _SusuTile({required this.row, required this.colors});

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = switch (row.status) {
      SusuStatus.configuring => ('PENDING', colors.warning),
      SusuStatus.active => ('ACTIVE', colors.success),
      SusuStatus.completed => ('COMPLETED', colors.accent),
      SusuStatus.cancelled => ('CANCELLED', colors.textTertiary),
      SusuStatus.frozenDispute => ('FROZEN', colors.danger),
      SusuStatus.unknown => ('—', colors.textTertiary),
    };

    final countdown = _renderCountdown();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/susu/${row.id}'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: row.status == SusuStatus.frozenDispute
                  ? colors.danger.withOpacity(0.40)
                  : colors.divider,
              width: 0.7,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: statusColor.withOpacity(0.30), width: 0.7),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '\$${row.contributionUsdc.toStringAsFixed(2)} · '
                '${row.frequency.label} · ${row.totalCycles} cycles',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (row.myCycleSlot != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.accent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: colors.accent.withOpacity(0.30),
                            width: 0.7),
                      ),
                      child: Text(
                        'Slot #${row.myCycleSlot}',
                        style: TextStyle(
                          color: colors.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  if (row.myCycleSlot != null) const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.divider,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      row.myRole.toUpperCase(),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (countdown != null)
                    Text(
                      countdown,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _renderCountdown() {
    final next = row.nextCycle;
    if (next == null) return null;
    final diff = next.scheduledRunAt.difference(DateTime.now());
    if (diff.isNegative) return 'Cycle ${next.cycleNumber} due';
    if (diff.inDays >= 1) return 'Next: ${diff.inDays}d';
    if (diff.inHours >= 1) return 'Next: ${diff.inHours}h';
    if (diff.inMinutes >= 1) return 'Next: ${diff.inMinutes}m';
    return 'Next: <1m';
  }
}

class _EmptyState extends StatelessWidget {
  final AzamanColors colors;
  const _EmptyState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 32),
      children: [
        Icon(Icons.account_balance_outlined,
            size: 56, color: colors.warning.withOpacity(0.30)),
        const SizedBox(height: 14),
        Text(
          'No Susus yet',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'A Susu is a private rotating savings group. Tap "Create Susu" to '
          'configure a contribution amount, frequency, and invite up to 23 '
          'trusted members.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textTertiary, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final AzamanColors colors;
  const _ErrorView({required this.error, required this.colors});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 32),
      children: [
        Icon(Icons.error_outline, size: 48, color: colors.danger),
        const SizedBox(height: 12),
        Text(
          'Could not load your Susus',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          error.toString(),
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textTertiary, fontSize: 11),
        ),
      ],
    );
  }
}
