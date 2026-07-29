// =============================================================================
// AZAMAN — Susu Credit Score Screen
//
// Shows the user's aggregated Susu credit score across all groups:
//   • Overall score (0-850 scale, FICO-like)
//   • Score breakdown: payment timeliness, participation, completion, trust
//   • Score history sparkline
//   • Active groups contributing to score
//   • Tips to improve score
//   • Score tier badge (Excellent / Good / Fair / Poor)
//
// Reference: Credit Karma score dashboard, Apple Card credit score view
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/theme_provider.dart';

class SusuCreditScoreScreen extends ConsumerStatefulWidget {
  const SusuCreditScoreScreen({super.key});

  @override
  ConsumerState<SusuCreditScoreScreen> createState() => _SusuCreditScoreScreenState();
}

class _SusuCreditScoreScreenState extends ConsumerState<SusuCreditScoreScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final susuListAsync = ref.watch(susuListProvider);
    final auth = ref.watch(authProvider);

    final groups = susuListAsync.valueOrNull ?? [];
    final activeGroups = groups.where((g) => g.status == SusuStatus.active).length;
    final completedGroups = groups.where((g) => g.status == SusuStatus.completed).length;
    final totalGroups = groups.length;

    // Simulated score components based on participation
    final paymentTimeliness = totalGroups > 0
        ? ((completedGroups / totalGroups) * 100).clamp(0.0, 100.0).toDouble()
        : 75.0;
    final participationRate = totalGroups > 0
        ? ((activeGroups + completedGroups) / totalGroups * 100).clamp(0.0, 100.0).toDouble()
        : 50.0;
    final completionRate = totalGroups > 0
        ? (completedGroups / totalGroups * 100).clamp(0.0, 100.0).toDouble()
        : 0.0;
    final trustFactor = groups.isNotEmpty
        ? groups.fold<double>(0, (sum, g) {
            double base = 50.0;
            if (g.status == SusuStatus.active) base = 75.0;
            if (g.status == SusuStatus.completed) base = 90.0;
            if (g.myStatus == SusuMemberStatus.active) base += 10;
            return sum + base;
          }) / groups.length
        : 50.0;

    // FICO-like score (300-850 range)
    final creditScore = (300 +
        (paymentTimeliness * 2.0) +
        (participationRate * 1.5) +
        (completionRate * 1.5) +
        (trustFactor * 1.0)
    ).clamp(300, 850).round();

    final scoreTier = _getScoreTier(creditScore);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        title: Text(
          'Susu Credit Score',
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero Score Card ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scoreTier.color.withValues(alpha: 0.15),
                    colors.surface,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.divider),
              ),
              child: Column(
                children: [
                  // Score ring
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Ring
                        SizedBox(
                          width: 180,
                          height: 180,
                          child: CircularProgressIndicator(
                            value: (creditScore - 300) / 550,
                            strokeWidth: 12,
                            backgroundColor: colors.divider,
                            valueColor: AlwaysStoppedAnimation(scoreTier.color),
                          ),
                        ),
                        // Score number
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$creditScore',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                              ),
                            ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.1),
                            Text(
                              'out of 850',
                              style: TextStyle(
                                color: colors.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Tier badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: scoreTier.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: scoreTier.color.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(scoreTier.icon, color: scoreTier.color, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          scoreTier.label,
                          style: TextStyle(
                            color: scoreTier.color,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 300.ms),
                  const SizedBox(height: 8),
                  Text(
                    scoreTier.description,
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms),

            const SizedBox(height: 24),

            // ── Score Breakdown ──
            Text(
              'Score Breakdown',
              style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),

            _ScoreFactor(
              label: 'Payment Timeliness',
              value: paymentTimeliness,
              color: colors.accent,
              icon: Icons.schedule,
              colors: colors,
            ).animate().fadeIn(delay: 200.ms),
            _ScoreFactor(
              label: 'Participation Rate',
              value: participationRate,
              color: colors.accentSecondary,
              icon: Icons.group,
              colors: colors,
            ).animate().fadeIn(delay: 300.ms),
            _ScoreFactor(
              label: 'Completion Rate',
              value: completionRate,
              color: colors.success,
              icon: Icons.check_circle,
              colors: colors,
            ).animate().fadeIn(delay: 400.ms),
            _ScoreFactor(
              label: 'Trust Factor',
              value: trustFactor,
              color: colors.warning,
              icon: Icons.verified_user,
              colors: colors,
            ).animate().fadeIn(delay: 500.ms),

            const SizedBox(height: 24),

            // ── Score History Sparkline ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.trending_up, color: colors.accent, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Score History',
                        style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        '+${(creditScore - 650).abs().toDouble()} pts',
                        style: TextStyle(
                          color: creditScore >= 650 ? colors.success : colors.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 100,
                    child: LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _generateHistorySpots(creditScore),
                            isCurved: true,
                            color: colors.accent,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: colors.accent.withValues(alpha: 0.1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 600.ms),

            const SizedBox(height: 24),

            // ── Active Groups ──
            Text(
              'Contributing Groups',
              style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (groups.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.divider),
                ),
                child: Column(
                  children: [
                    Icon(Icons.savings, color: colors.textTertiary, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'No Susu groups yet',
                      style: TextStyle(color: colors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Join a Susu to start building your credit score',
                      style: TextStyle(color: colors.textTertiary, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ...groups.take(5).map((g) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.divider),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: (g.status == SusuStatus.active ? colors.accent : colors.textTertiary).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.savings,
                        color: g.status == SusuStatus.active ? colors.accent : colors.textTertiary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            g.name,
                            style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${g.status.name.toUpperCase()} · ${g.myRole}',
                            style: TextStyle(color: colors.textTertiary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: colors.textTertiary, size: 20),
                  ],
                ),
              )),

            const SizedBox(height: 24),

            // ── Tips to Improve ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.accentSecondary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.accentSecondary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb, color: colors.accentSecondary, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Tips to Improve Your Score',
                        style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._getTips(creditScore, colors),
                ],
              ),
            ).animate().fadeIn(delay: 700.ms),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  List<FlSpot> _generateHistorySpots(int currentScore) {
    // Generate a simulated 6-month history trending toward current score
    final spots = <FlSpot>[];
    final baseScore = (currentScore - 80).clamp(300, 850).toDouble();
    for (int i = 0; i < 6; i++) {
      final progress = i / 5;
      final noise = (i % 2 == 0 ? 10 : -10);
      final score = baseScore + (currentScore - baseScore) * progress + noise;
      spots.add(FlSpot(i.toDouble(), score));
    }
    return spots;
  }

  List<Widget> _getTips(int score, AzamanColors colors) {
    final tips = <String>[];
    if (score < 650) {
      tips.add('Make all Susu contributions on time — timeliness is 40% of your score');
      tips.add('Complete your current Susu cycles to boost completion rate');
      tips.add('Join additional Susu groups to improve participation');
    } else if (score < 750) {
      tips.add('You\'re doing well! Complete your active cycles to push higher');
      tips.add('Maintain consistent on-time payments for 3+ cycles');
    } else {
      tips.add('Excellent score! You qualify for priority Susu payouts');
      tips.add('Consider vouching for trusted members to build community trust');
    }

    return tips.map((tip) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, color: colors.accentSecondary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tip,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    )).toList();
  }
}

_ScoreTier _getScoreTier(int score) {
  if (score >= 750) {
    return _ScoreTier(
    label: 'Excellent',
    color: const Color(0xFF00D97E),
    icon: Icons.star,
    description: 'Top-tier reliability — priority payout eligibility',
  );
  }
  if (score >= 670) {
    return _ScoreTier(
    label: 'Good',
    color: const Color(0xFF00B4D8),
    icon: Icons.thumb_up,
    description: 'Solid track record — trusted by the community',
  );
  }
  if (score >= 580) {
    return _ScoreTier(
    label: 'Fair',
    color: const Color(0xFFFF9500),
    icon: Icons.trending_up,
    description: 'Building trust — complete cycles to improve',
  );
  }
  return _ScoreTier(
    label: 'Needs Work',
    color: const Color(0xFFFF3B30),
    icon: Icons.warning,
    description: 'Focus on on-time payments to boost your score',
  );
}

class _ScoreTier {
  final String label;
  final Color color;
  final IconData icon;
  final String description;

  _ScoreTier({required this.label, required this.color, required this.icon, required this.description});
}

class _ScoreFactor extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final IconData icon;
  final AzamanColors colors;

  const _ScoreFactor({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: value / 100,
                      backgroundColor: colors.divider,
                      valueColor: AlwaysStoppedAnimation(color),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${value.toStringAsFixed(0)}%',
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
