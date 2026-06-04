// =============================================================================
// INITIATE SUSU SHEET — Phase 5 / Workstreams B+D (2026-06-01)
//
// The "Initiate Susu" config, launched from the group profile by an admin.
// Replaces the retired standalone "Create Susu" screen. Captures:
//   • contribution per cycle (USDC, 0 < x ≤ 1,000,000)
//   • frequency (Daily / Weekly / Bi-weekly / Monthly)
//   • verification countdown window (24h … 7d)
//
// Shows the dynamic pool math live: pool/cycle = contribution × member
// count, in USDC and cedis (using the Azaman supplied retail rate). Member
// count is the group's current size (the source of truth) — the pool grows
// or shrinks as members are added/removed before initiation.
//
// On submit: POST /api/group-chats/:id/susu/initiate via groupActions.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';

class InitiateSusuSheet extends ConsumerStatefulWidget {
  final String groupId;
  final int memberCount;
  const InitiateSusuSheet({
    super.key,
    required this.groupId,
    required this.memberCount,
  });

  @override
  ConsumerState<InitiateSusuSheet> createState() => _InitiateSusuSheetState();
}

class _InitiateSusuSheetState extends ConsumerState<InitiateSusuSheet> {
  final _amount = TextEditingController();
  SusuFrequency _frequency = SusuFrequency.weekly;
  int _windowHours = 72;
  bool _busy = false;

  static const _windows = <int, String>{
    24: '24 hours',
    48: '2 days',
    72: '3 days',
    96: '4 days',
    120: '5 days',
    168: '7 days',
  };

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double get _contribution => double.tryParse(_amount.text.trim()) ?? 0;
  double get _pool => _contribution * widget.memberCount;

  Future<void> _submit() async {
    final amt = _contribution;
    if (amt <= 0 || amt > 1000000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Contribution must be between \$0.01 and \$1,000,000.')),
      );
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      await ref.read(groupActionsProvider).initiateSusu(
            widget.groupId,
            contributionUsdc: amt,
            frequency: _frequency.wire,
            windowHours: _windowHours,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Susu initiated — members must verify before the deadline.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final rate = ref.watch(susuSuppliedRateProvider).valueOrNull;
    final ghsRate = rate?.usdcToGhs ?? 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
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
              Text('Initiate Susu',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(
                'Based on ${widget.memberCount} current members. The pool '
                'recalculates if members join or leave before the deadline.',
                style: TextStyle(
                    color: colors.textTertiary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 18),

              _label('Contribution per cycle (USDC)', colors),
              Container(
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.divider),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: '20.00',
                    hintStyle:
                        TextStyle(color: colors.textTertiary, fontSize: 14),
                    prefixText: '\$ ',
                    prefixStyle: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Dynamic pool math
              _PoolPreview(
                contribution: _contribution,
                pool: _pool,
                memberCount: widget.memberCount,
                ghsRate: ghsRate,
                colors: colors,
              ),
              const SizedBox(height: 16),

              _label('Frequency', colors),
              Wrap(
                spacing: 8,
                children: [
                  SusuFrequency.daily,
                  SusuFrequency.weekly,
                  SusuFrequency.biweekly,
                  SusuFrequency.monthly,
                ].map((f) {
                  final sel = _frequency == f;
                  return ChoiceChip(
                    selected: sel,
                    label: Text(f.label),
                    onSelected: (_) => setState(() => _frequency = f),
                    selectedColor: colors.warning.withOpacity(0.20),
                    labelStyle: TextStyle(
                      color: sel ? colors.warning : colors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              _label('Verification countdown', colors),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _windows.entries.map((e) {
                  final sel = _windowHours == e.key;
                  return ChoiceChip(
                    selected: sel,
                    label: Text(e.value),
                    onSelected: (_) => setState(() => _windowHours = e.key),
                    selectedColor: colors.accent.withOpacity(0.20),
                    labelStyle: TextStyle(
                      color: sel ? colors.accent : colors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Text(
                'Every member must verify ID (KYC) + proof of residency and '
                'accept the liability contract before the countdown ends. '
                'Members who don\'t are removed from the group.',
                style: TextStyle(
                    color: colors.textTertiary, fontSize: 11, height: 1.4),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.rocket_launch_rounded, size: 16),
                  label: Text(
                    _busy ? 'Initiating…' : 'Initiate Susu',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, letterSpacing: 0.3),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.warning,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t, AzamanColors colors) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          t.toUpperCase(),
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      );
}

class _PoolPreview extends StatelessWidget {
  final double contribution;
  final double pool;
  final int memberCount;
  final double ghsRate;
  final AzamanColors colors;
  const _PoolPreview({
    required this.contribution,
    required this.pool,
    required this.memberCount,
    required this.ghsRate,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.accent.withOpacity(0.18), width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ghsRate > 0)
            Text(
              'Azaman rate · 1 USDC = GH₵ ${ghsRate.toStringAsFixed(2)}',
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 6),
          _line(
            'Each member pays / cycle',
            '\$${contribution.toStringAsFixed(2)}',
            ghsRate > 0 ? 'GH₵ ${(contribution * ghsRate).toStringAsFixed(2)}' : null,
          ),
          const SizedBox(height: 4),
          _line(
            'Total payout / cycle ($memberCount members)',
            '\$${pool.toStringAsFixed(2)}',
            ghsRate > 0 ? 'GH₵ ${(pool * ghsRate).toStringAsFixed(2)}' : null,
            emphasize: true,
          ),
        ],
      ),
    );
  }

  Widget _line(String k, String usd, String? ghs, {bool emphasize = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(k,
              style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 11.5,
                  height: 1.3)),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              usd,
              style: TextStyle(
                color: emphasize ? colors.accent : colors.textPrimary,
                fontSize: emphasize ? 15 : 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (ghs != null)
              Text(
                '≈ $ghs',
                style: TextStyle(color: colors.textTertiary, fontSize: 10.5),
              ),
          ],
        ),
      ],
    );
  }
}
