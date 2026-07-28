import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storefront/providers/storefront_provider.dart';
import '../storefront/models/storefront_models.dart';
import '../providers/theme_provider.dart';

class StorefrontStakingScreen extends ConsumerStatefulWidget {
  const StorefrontStakingScreen({super.key});

  @override
  ConsumerState<StorefrontStakingScreen> createState() => _StorefrontStakingScreenState();
}

class _StorefrontStakingScreenState extends ConsumerState<StorefrontStakingScreen> {
  final _amountController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _stake() async {
    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid AZM amount')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(stakingProvider.notifier).createStake(amount);
      _amountController.clear();
      ref.invalidate(storefrontEligibilityProvider);
      ref.invalidate(stakesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Staked $amount AZM successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stake failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unstake(AzmStake stake) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Unstake'),
        content: Text('Unstake ${stake.amountAzm} AZM? A cooldown period applies before funds are available.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Unstake')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await ref.read(stakingProvider.notifier).requestUnstake(stake.id);
      ref.invalidate(stakesProvider);
      ref.invalidate(storefrontEligibilityProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unstake requested. Cooldown period active.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unstake failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final eligibility = ref.watch(storefrontEligibilityProvider).valueOrNull;
    final stakes = ref.watch(stakesProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Nitro Staking'),
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current tier + balance
            _TierCard(eligibility: eligibility, colors: colors),

            const SizedBox(height: 20),

            // Stake input
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Stake AZM', style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Lock AZM to unlock premium themes and widgets', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: colors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: '0',
                      suffixText: 'AZM',
                      suffixStyle: TextStyle(color: colors.textSecondary),
                      filled: true,
                      fillColor: colors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.accent, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Quick amounts
                  Row(
                    children: [500, 1500, 5000].map((amount) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text('$amount AZM'),
                          backgroundColor: colors.background,
                          side: BorderSide(color: colors.divider),
                          onPressed: () => _amountController.text = amount.toString(),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _stake,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Stake Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Active stakes
            Text('Active Stakes', style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            stakes.when(
              data: (stakeList) {
                if (stakeList.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.divider),
                    ),
                    child: Center(
                      child: Text('No active stakes yet', style: TextStyle(color: colors.textSecondary)),
                    ),
                  );
                }
                return Column(
                  children: stakeList.map((stake) => _StakeItem(stake: stake, colors: colors, onUnstake: () => _unstake(stake), loading: _loading)).toList(),
                );
              },
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
              error: (e, _) => Text('Error: $e', style: TextStyle(color: colors.danger)),
            ),

            const SizedBox(height: 20),

            // Tier ladder
            _TierLadder(colors: colors, currentStake: (eligibility?.stakedBalance ?? 0).toInt()),
          ],
        ),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  final StorefrontEligibility? eligibility;
  final AzamanColors colors;

  const _TierCard({this.eligibility, required this.colors});

  @override
  Widget build(BuildContext context) {
    final tier = eligibility?.tier.name ?? 'FREE';
    final staked = (eligibility?.stakedBalance ?? 0).toInt();
    final tierColor = _tierColor(tier);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tierColor.withOpacity(0.15), tierColor.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tierColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: tierColor, shape: BoxShape.circle),
            child: const Icon(Icons.bolt, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current Tier', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                Text(tier.replaceAll('NITRO_', ''), style: TextStyle(color: colors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Staked', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
              Text('$staked AZM', style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Color _tierColor(String tier) {
    switch (tier) {
      case 'NITRO_BRONZE': return const Color(0xCD7F32);
      case 'NITRO_SILVER': return const Color(0xC0C0C0);
      case 'NITRO_GOLD': return const Color(0xFFD700);
      default: return const Color(0x6C4FD1);
    }
  }
}

class _StakeItem extends StatelessWidget {
  final AzmStake stake;
  final AzamanColors colors;
  final VoidCallback onUnstake;
  final bool loading;

  const _StakeItem({required this.stake, required this.colors, required this.onUnstake, required this.loading});

  @override
  Widget build(BuildContext context) {
    final canUnstake = stake.unstakeAvailableAt != null && DateTime.now().isAfter(stake.unstakeAvailableAt!);
    final inCooldown = stake.unstakeRequestedAt != null && !canUnstake;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${stake.amountAzm} AZM', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('Staked ${_formatDate(stake.stakedAt)}', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                if (inCooldown && stake.unstakeAvailableAt != null)
                  Text('Available ${_formatDate(stake.unstakeAvailableAt!)}', style: TextStyle(color: colors.warning, fontSize: 12)),
              ],
            ),
          ),
          if (stake.unstakeRequestedAt == null)
            TextButton(
              onPressed: loading ? null : onUnstake,
              style: TextButton.styleFrom(foregroundColor: colors.danger),
              child: const Text('Unstake'),
            )
          else if (canUnstake)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: colors.success.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
              child: Text('Ready to claim', style: TextStyle(color: colors.success, fontSize: 12, fontWeight: FontWeight.w600)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: colors.warning.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
              child: Text('Cooldown', style: TextStyle(color: colors.warning, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _TierLadder extends StatelessWidget {
  final AzamanColors colors;
  final int currentStake;

  const _TierLadder({required this.colors, required this.currentStake});

  static const _tiers = [
    {'name': 'FREE', 'min': 0, 'unlocks': '4 themes, 8 widgets'},
    {'name': 'BRONZE', 'min': 500, 'unlocks': '+2 themes, +3 widgets'},
    {'name': 'SILVER', 'min': 1500, 'unlocks': '+2 themes, +2 widgets, drag/reorder'},
    {'name': 'GOLD', 'min': 5000, 'unlocks': '+1 theme, +2 widgets, custom typography'},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tier Ladder', style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ..._tiers.map((tier) {
            final unlocked = currentStake >= (tier['min'] as int);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(unlocked ? Icons.check_circle : Icons.lock, size: 20, color: unlocked ? colors.success : colors.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tier['name'] as String, style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                        Text(tier['unlocks'] as String, style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text('${tier['min']} AZM', style: TextStyle(color: unlocked ? colors.success : colors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
