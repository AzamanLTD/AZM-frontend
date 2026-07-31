// =============================================================================
// AZAMAN — Loyalty Cards Screen (Customer)
//
// View all loyalty/stamp cards across businesses. See stamp progress,
// redeem rewards, and track points.
//
// Reference: Starbucks Rewards, Punchh loyalty cards, Stamp Me
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:azaman/screens/wallet/wallet_pass_screen.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/nav_transitions.dart';

// ── State ─────────────────────────────────────────────────────────────────────

final loyaltyCardsProvider = StateNotifierProvider.autoDispose
    <LoyaltyCardsNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return LoyaltyCardsNotifier()..load();
});

class LoyaltyCardsNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  LoyaltyCardsNotifier() : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final res = await apiClient.get('/loyalty/me/cards');
      if (res.statusCode != 200) throw Exception('Failed');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['data'] as List? ?? [])
          .map((c) => c as Map<String, dynamic>)
          .toList();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<bool> redeem(String programId) async {
    try {
      await apiClient.post('/loyalty/me/programs/$programId/redeem', {});
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _parseBody(dynamic res) {
    if (res is Map<String, dynamic>) return res;
    return <String, dynamic>{};
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class LoyaltyCardsScreen extends ConsumerStatefulWidget {
  const LoyaltyCardsScreen({super.key});

  @override
  ConsumerState<LoyaltyCardsScreen> createState() => _LoyaltyCardsScreenState();
}

class _LoyaltyCardsScreenState extends ConsumerState<LoyaltyCardsScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final cards = ref.watch(loyaltyCardsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text('Loyalty Cards', style: TextStyle(color: colors.textPrimary)),
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: cards.when(
        loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
        error: (_, __) => Center(child: Text('Failed to load loyalty cards',
            style: TextStyle(color: colors.textSecondary))),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(HugeIconsSolid.giftCard, size: 48, color: colors.textTertiary),
                  const SizedBox(height: 12),
                  Text('No loyalty cards yet', style: TextStyle(color: colors.textSecondary, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Order from businesses with loyalty programs\nto start earning rewards',
                      style: TextStyle(color: colors.textTertiary, fontSize: 13),
                      textAlign: TextAlign.center),
                ],
              ).animate().fadeIn(),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (_, i) => _LoyaltyCard(
              card: list[i],
              colors: colors,
              onRedeem: (programId) async {
                AzamanHaptics.confirm();
                final success = await ref.read(loyaltyCardsProvider.notifier).redeem(programId);
                if (success && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Reward redeemed! Show this to the business.'),
                      backgroundColor: colors.success,
                    ),
                  );
                }
              },
            ).animate().fadeIn(delay: 100.ms * i).slideY(begin: 0.05),
          );
        },
      ),
    );
  }
}

// ── Loyalty Card Widget ──────────────────────────────────────────────────────

class _LoyaltyCard extends StatelessWidget {
  final Map<String, dynamic> card;
  final AzamanColors colors;
  final Future<void> Function(String programId) onRedeem;

  const _LoyaltyCard({
    required this.card,
    required this.colors,
    required this.onRedeem,
  });

  @override
  Widget build(BuildContext context) {
    final program = (card['loyaltyProgram'] as Map<String, dynamic>?) ?? {};
    final biz = (program['businessProfile'] as Map<String, dynamic>?) ?? {};
    final type = program['type']?.toString() ?? 'STAMP';
    final stampsCollected = (card['stampsCollected'] as num?)?.toInt() ?? 0;
    final stampsRequired = (program['stampsRequired'] as num?)?.toInt() ?? 10;
    final pointsBalance = (card['pointsBalance'] as num?)?.toDouble() ?? 0;
    final cardColor = _parseColor(program['cardColor']?.toString() ?? '#FFD700');
    final bizName = biz['businessName']?.toString() ?? 'Business';
    final bizLogo = biz['logoUrl']?.toString();
    final rewardDesc = program['rewardDescription']?.toString() ?? 'Reward';
    final totalRedeemed = (card['totalRewardsRedeemed'] as num?)?.toInt() ?? 0;

    final isRedeemable = type == 'STAMP' && stampsCollected >= stampsRequired;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [cardColor, cardColor.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: cardColor.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Decorative circles
            Positioned(
              right: -30, top: -30,
              child: Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),
            Positioned(
              right: 10, bottom: -20,
              child: Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      if (bizLogo != null)
                        CircleAvatar(radius: 18, backgroundImage: NetworkImage(bizLogo),
                            backgroundColor: Colors.white24)
                      else
                        CircleAvatar(radius: 18, backgroundColor: Colors.white24,
                            child: Text(bizName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(bizName, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                            Text(program['name']?.toString() ?? 'Loyalty Program',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                          ],
                        ),
                      ),
                      if (totalRedeemed > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('$totalRedeemed redeemed', style: const TextStyle(color: Colors.white, fontSize: 10)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Type-specific content
                  if (type == 'STAMP') ...[
                    // Stamp grid
                    _StampGrid(
                      collected: stampsCollected,
                      required: stampsRequired,
                      cardColor: cardColor,
                    ),
                    const SizedBox(height: 12),
                    Text('Reward: $rewardDesc',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                    const SizedBox(height: 12),
                    // Redeem button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isRedeemable
                            ? () => onRedeem(program['id'])
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: cardColor,
                          disabledBackgroundColor: Colors.white24,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          isRedeemable ? 'Redeem Reward' : '\$stampsCollected / \$stampsRequired stamps',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                            color: isRedeemable ? cardColor : Colors.white54),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // ── Phase 3: Apple/Google Wallet Pass ──
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => pushWithVerticalTransition(context, WalletPassScreen(passType: 'loyalty',
                            itemId: card['id'] as String,
                            title: program['name'] as String? ?? 'Loyalty Card',)),
                        icon: const Icon(Icons.wallet, size: 16),
                        label: const Text('Add to Wallet', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white30),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ] else if (type == 'POINTS') ...[
                    Row(
                      children: [
                        Text(pointsBalance.toStringAsFixed(0),
                            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 6),
                        Text('points', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Reward: $rewardDesc',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                  ] else ...[
                    // TIER
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(card['currentTier']?.toString() ?? 'BRONZE',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Reward: $rewardDesc',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) { return const Color(0xFFFFD700); }
  }
}

// ── Stamp Grid ──────────────────────────────────────────────────────────────────

class _StampGrid extends StatelessWidget {
  final int collected;
  final int required;
  final Color cardColor;

  const _StampGrid({required this.collected, required this.required, required this.cardColor});

  @override
  Widget build(BuildContext context) {
    // Determine grid columns based on required stamps
    final cols = required <= 6 ? 6 : (required <= 10 ? 5 : 6);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(required, (i) {
        final isStamped = i < collected;
        return Container(
          width: cols == 6 ? 38 : 42,
          height: cols == 6 ? 38 : 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isStamped ? Colors.white : Colors.white.withValues(alpha: 0.15),
            border: Border.all(
              color: isStamped ? Colors.white : Colors.white.withValues(alpha: 0.3),
              width: isStamped ? 0 : 1.5,
            ),
          ),
          child: isStamped
              ? Icon(HugeIconsSolid.checkmarkBadge02, color: cardColor, size: 20)
              : null,
        );
      }),
    );
  }
}
