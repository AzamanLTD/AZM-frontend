// =============================================================================
// AZAMAN — Round-Up Savings Settings
//
// A Cash App / Acorns-style screen where users can:
//   • Toggle round-up savings on/off
//   • See total round-up savings (piggy bank visualization)
//   • See recent round-up contributions
//   • Choose which vault to deposit round-ups into
//
// Reference: Cash App (Boost), Acorns, Monzo (pots), Chime
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:intl/intl.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/round_up_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/premium_glass_container.dart';

class RoundUpSettingsScreen extends ConsumerStatefulWidget {
  const RoundUpSettingsScreen({super.key});

  @override
  ConsumerState<RoundUpSettingsScreen> createState() => _RoundUpSettingsScreenState();
}

class _RoundUpSettingsScreenState extends ConsumerState<RoundUpSettingsScreen> {
  bool _isLoading = true;
  bool _enabled = false;
  double _totalSaved = 0.0;
  List<RoundUpExample> _examples = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final settings = await RoundUpService.getSettings();
    setState(() {
      _enabled = settings.enabled;
      _totalSaved = settings.totalSaved;
      _isLoading = false;
    });
    _generateExamples();
  }

  void _generateExamples() {
    _examples = [
      RoundUpExample(description: 'Sent to friend', amount: 4.30, roundUp: RoundUpService.computeRoundUp(4.30)),
      RoundUpExample(description: 'Susu contribution', amount: 12.50, roundUp: RoundUpService.computeRoundUp(12.50)),
      RoundUpExample(description: 'Business payment', amount: 8.75, roundUp: RoundUpService.computeRoundUp(8.75)),
      RoundUpExample(description: 'Transfer', amount: 15.20, roundUp: RoundUpService.computeRoundUp(15.20)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01, size: 20, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Round-Up Savings',
          style: TextStyle(color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Hero piggy bank card ─────────────────────────────────
                  _buildPiggyBankCard(colors),
                  const SizedBox(height: 20),

                  // ── Toggle ──────────────────────────────────────────────
                  _buildToggleCard(colors),
                  const SizedBox(height: 20),

                  if (_enabled) ...[
                    // ── How it works ────────────────────────────────────────
                    _buildHowItWorks(colors),
                    const SizedBox(height: 20),

                    // ── Example transactions ────────────────────────────────
                    _buildExamples(colors),
                    const SizedBox(height: 20),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildPiggyBankCard(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.accent.withValues(alpha: 0.12),
            colors.accentSecondary.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.accent.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Column(
        children: [
          // Piggy bank icon
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              HugeIconsSolid.piggyBank,
              size: 36,
              color: colors.accent,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Total Round-Up Savings',
            style: TextStyle(color: colors.textTertiary, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            '\$${_totalSaved.toStringAsFixed(2)}',
            style: TextStyle(color: colors.textPrimary, fontSize: 36, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (_enabled)
            Text(
              '🟢 Active — saving on every transaction',
              style: TextStyle(color: colors.success, fontSize: 12, fontWeight: FontWeight.w600),
            )
          else
            Text(
              'Not active yet',
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildToggleCard(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _enabled ? colors.accent.withValues(alpha: 0.12) : colors.softSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              HugeIconsSolid.exchange01,
              size: 20,
              color: _enabled ? colors.accent : colors.textTertiary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Round-Up Savings',
                  style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Round up every transaction to the nearest dollar and save the difference',
                  style: TextStyle(color: colors.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _enabled,
            activeColor: colors.accent,
            onChanged: (v) async {
              AzamanHaptics.nav();
              await RoundUpService.setEnabled(v);
              setState(() => _enabled = v);
            },
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 300.ms);
  }

  Widget _buildHowItWorks(AzamanColors colors) {
    final steps = [
      _HowStep(
        icon: HugeIconsSolid.moneySendSquare,
        title: 'Spend as usual',
        description: 'Send money, pay for things, contribute to Susu — all normally.',
      ),
      _HowStep(
        icon: HugeIconsSolid.exchange01,
        title: 'We round up',
        description: 'Each transaction rounds up to the nearest dollar automatically.',
      ),
      _HowStep(
        icon: HugeIconsSolid.piggyBank,
        title: 'Difference saved',
        description: 'The round-up difference goes into your Round-Up Vault.',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works',
            style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          ...steps.asMap().entries.map((entry) {
            final step = entry.value;
            final isLast = entry.key == steps.length - 1;
            return Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(step.icon, size: 16, color: colors.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.title,
                            style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            step.description,
                            style: TextStyle(color: colors.textTertiary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!isLast)
                  Padding(
                    padding: const EdgeInsets.only(left: 17, top: 8, bottom: 8),
                    child: Container(
                      width: 1.5, height: 16,
                      color: colors.divider,
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 300.ms);
  }

  Widget _buildExamples(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Example Round-Ups',
            style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          ..._examples.map((ex) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(HugeIconsSolid.exchange01, size: 16, color: colors.textTertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ex.description,
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                ),
                Text(
                  '\$${ex.amount.toStringAsFixed(2)}',
                  style: TextStyle(color: colors.textTertiary, fontSize: 13),
                ),
                const SizedBox(width: 8),
                Icon(HugeIconsSolid.arrowRight01, size: 14, color: colors.textTertiary),
                const SizedBox(width: 8),
                Text(
                  '+\$${ex.roundUp.toStringAsFixed(2)}',
                  style: TextStyle(color: colors.success, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          )),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 300.ms);
  }
}

// ── Models ────────────────────────────────────────────────────────────────────

class RoundUpExample {
  final String description;
  final double amount;
  final double roundUp;

  const RoundUpExample({required this.description, required this.amount, required this.roundUp});
}

class _HowStep {
  final IconData icon;
  final String title;
  final String description;

  const _HowStep({required this.icon, required this.title, required this.description});
}
