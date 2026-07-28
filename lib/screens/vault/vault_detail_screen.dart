// =============================================================================
// VAULT DETAIL SCREEN  (Master Sprint, 2026-05-27)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/vault_provider.dart';


class VaultDetailScreen extends ConsumerStatefulWidget {
  final String vaultId;
  const VaultDetailScreen({super.key, required this.vaultId});

  @override
  ConsumerState<VaultDetailScreen> createState() => _VaultDetailScreenState();
}

class _VaultDetailScreenState extends ConsumerState<VaultDetailScreen> {
  final _depositCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _depositCtrl.dispose();
    super.dispose();
  }

  Future<void> _deposit() async {
    final amt = double.tryParse(_depositCtrl.text.trim());
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a positive amount.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(vaultsProvider.notifier).deposit(widget.vaultId, amt);
      _depositCtrl.clear();
      ref.invalidate(vaultDetailProvider(widget.vaultId));
      ref.invalidate(vaultDepositsProvider(widget.vaultId));
      if (mounted) HapticFeedback.heavyImpact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmBreak(Vault v, AzamanColors colors) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Break vault early?',
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800)),
        content: Text(
          'You will pay a ${(v.earlyBreakPenaltyPct * 100).toStringAsFixed(1)}% penalty on '
          '\$${v.currentAmountUsdc.toStringAsFixed(2)}. The remainder returns to your wallet. '
          'AZM already earned stays.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Break Vault', style: TextStyle(color: colors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(vaultsProvider.notifier).breakEarly(widget.vaultId);
      ref.invalidate(vaultDetailProvider(widget.vaultId));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final vaultAsync = ref.watch(vaultDetailProvider(widget.vaultId));
    final depositsAsync = ref.watch(vaultDepositsProvider(widget.vaultId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Vault',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            )),
      ),
      body: vaultAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (v) {
          if (v == null) return const Center(child: Text('Vault not found'));
          final isActive = v.status == 'ACTIVE';
          final progress = v.progressFraction;
          final daysLeft = v.maturityDate.difference(DateTime.now()).inDays;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _Hero(v: v, progress: progress, colors: colors, daysLeft: daysLeft)
                  .animate()
                  .fadeIn(duration: 320.ms)
                  .slideY(begin: 0.05, end: 0),
              const SizedBox(height: 16),
              _StatsGrid(v: v, colors: colors)
                  .animate()
                  .fadeIn(delay: 80.ms, duration: 320.ms),
              if (isActive) ...[
                const SizedBox(height: 16),
                _DepositCard(
                  controller: _depositCtrl,
                  busy: _busy,
                  onDeposit: _deposit,
                  colors: colors,
                ).animate().fadeIn(delay: 160.ms, duration: 320.ms),
              ],
              const SizedBox(height: 16),
              Text(
                'Recent Deposits',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              depositsAsync.when(
                loading: () => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator(color: colors.accent)),
                ),
                error: (e, _) => Text(e.toString()),
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'No deposits yet.',
                          style: TextStyle(color: colors.textTertiary, fontSize: 12),
                        ),
                      )
                    : Column(
                        children: list
                            .map((d) => _DepositTile(d: d, colors: colors))
                            .toList(),
                      ),
              ),
              if (isActive) ...[
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _confirmBreak(v, colors),
                  icon: Icon(Icons.key_outlined, color: colors.danger, size: 16),
                  label: Text(
                    'Break Vault Early',
                    style: TextStyle(color: colors.danger, fontWeight: FontWeight.w800),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.danger.withValues(alpha: 0.30)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final Vault v;
  final double progress;
  final AzamanColors colors;
  final int daysLeft;
  const _Hero({
    required this.v,
    required this.progress,
    required this.colors,
    required this.daysLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.accent.withValues(alpha: 0.18),
            colors.accentSecondary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.accent.withValues(alpha: 0.30), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, color: colors.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                v.name,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                daysLeft > 0 ? '$daysLeft days left' : 'Maturity reached',
                style: TextStyle(color: colors.textTertiary, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${v.currentAmountUsdc.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  )),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '/ \$${v.targetAmountUsdc.toStringAsFixed(2)}',
                  style: TextStyle(color: colors.textTertiary, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress.toDouble(),
              backgroundColor: colors.divider,
              valueColor: AlwaysStoppedAnimation(colors.accent),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(progress * 100).toStringAsFixed(1)}% to goal',
            style: TextStyle(color: colors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final Vault v;
  final AzamanColors colors;
  const _StatsGrid({required this.v, required this.colors});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Streak', '${v.streakCount}', Icons.local_fire_department_outlined, colors.warning),
      ('Best', '${v.longestStreak}', Icons.emoji_events_outlined, colors.accent),
      ('AZM', v.totalAzmEarned.toStringAsFixed(0), Icons.bolt_outlined, colors.accentSecondary),
      ('Score', '${v.consistencyScore.toStringAsFixed(0)}%',
          Icons.analytics_outlined, colors.success),
    ];
    return Row(
      children: items
          .map(
            (it) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.divider, width: 0.7),
                  ),
                  child: Column(
                    children: [
                      Icon(it.$3, color: it.$4, size: 16),
                      const SizedBox(height: 6),
                      Text(it.$2,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          )),
                      Text(it.$1,
                          style: TextStyle(color: colors.textTertiary, fontSize: 9)),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _DepositCard extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onDeposit;
  final AzamanColors colors;
  const _DepositCard({
    required this.controller,
    required this.busy,
    required this.onDeposit,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Add to vault',
                prefixText: '\$ ',
                hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
                prefixStyle: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: busy ? null : onDeposit,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.isDark ? Colors.black : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: busy
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Text('Deposit',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          )
        ],
      ),
    );
  }
}

class _DepositTile extends StatelessWidget {
  final VaultDeposit d;
  final AzamanColors colors;
  const _DepositTile({required this.d, required this.colors});

  IconData get _icon => switch (d.type) {
        'AUTO_RULE' => Icons.refresh,
        'BONUS' => Icons.card_giftcard_outlined,
        _ => Icons.arrow_downward,
      };

  Color get _color => switch (d.status) {
        'COMPLETED' => colors.success,
        'FAILED_INSUFFICIENT' => colors.warning,
        'FAILED_OTHER' => colors.danger,
        _ => colors.textTertiary,
      };

  @override
  Widget build(BuildContext context) {
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
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_icon, color: _color, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '\$${d.amountUsdc.toStringAsFixed(2)} · ${d.type}',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  d.failureReason ?? '+${d.azmAwarded.toStringAsFixed(2)} AZM',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textTertiary, fontSize: 10.5),
                ),
              ],
            ),
          ),
          Text(
            _short(d.createdAt),
            style: TextStyle(color: colors.textTertiary, fontSize: 10),
          ),
        ],
      ),
    );
  }

  String _short(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
