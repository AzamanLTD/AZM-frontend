// =============================================================================
// SUSU WARNING SCREEN  (Master Sprint, 2026-05-27)
//
// Severe legally-binding warning. Two checkboxes (severity warning +
// seizure clause) gate the "I Accept" button. Scrolling through the
// full text is also required.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class SusuWarningScreen extends ConsumerStatefulWidget {
  final String susuGroupId;
  final double contributionUsdc;
  final String frequency;
  final int totalCycles;

  const SusuWarningScreen({
    super.key,
    required this.susuGroupId,
    required this.contributionUsdc,
    required this.frequency,
    required this.totalCycles,
  });

  @override
  ConsumerState<SusuWarningScreen> createState() => _SusuWarningScreenState();
}

class _SusuWarningScreenState extends ConsumerState<SusuWarningScreen> {
  final _scroll = ScrollController();
  bool _scrolledToBottom = false;
  bool _accSeverity = false;
  bool _accSeizure = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.offset >= _scroll.position.maxScrollExtent - 8 &&
          !_scrolledToBottom) {
        setState(() => _scrolledToBottom = true);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await ref.read(susuActionsProvider).acceptContract(widget.susuGroupId);
      if (mounted) {
        HapticFeedback.heavyImpact();
        Navigator.pop(context);
      }
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
    final canAccept = _scrolledToBottom && _accSeverity && _accSeizure && !_busy;
    final pool = widget.contributionUsdc * widget.totalCycles;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Susu Contract',
            style: TextStyle(
                color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.danger.withOpacity(0.30)),
              ),
              child: Row(
                children: [
                  Icon(HugeIconsSolid.alertCircle, color: colors.danger, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Read every clause. Defaulting on a Susu is treated as theft.',
                      style: TextStyle(
                        color: colors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Susu Cycle Summary',
                      style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 6),
                    _summary(colors,
                        '• Contribution: \$${widget.contributionUsdc.toStringAsFixed(2)} USDC per cycle'),
                    _summary(colors, '• Frequency: ${widget.frequency.toLowerCase()}'),
                    _summary(colors, '• Cycles: ${widget.totalCycles}'),
                    _summary(colors, '• Pool size: \$${pool.toStringAsFixed(2)} USDC'),
                    const SizedBox(height: 16),
                    _clause(colors, '1. Binding Obligation',
                        'Once you accept this contract, you owe the contribution every cycle until completion. There is no opt-out, no pause, no skip.'),
                    _clause(colors, '2. Auto-Seizure',
                        'On collection day the platform atomically deducts your contribution from your available balance. If your balance is short, we seize whatever is available.'),
                    _clause(colors, '3. Default = Theft',
                        'Failing to pay constitutes theft of the pool. Your account is frozen, all balances are locked pending admin review, and local authorities may be notified.'),
                    _clause(colors, '4. Voucher Penalty',
                        'The two members who vouched for you suffer immediate trust-score penalties on every Susu they belong to. Your default damages their credibility on the platform.'),
                    _clause(colors, '5. Smart Rotation',
                        'Cycle order is determined by your trust score at start time. Newly vouched-in members are placed at the back of the rotation. Admins go first.'),
                    _clause(colors, '6. Payout',
                        'On your scheduled cycle the entire pool is routed to your available balance instantly.'),
                    _clause(colors, '7. Disputes',
                        'Admin decisions on Susu defaults are final. There is no chargeback or refund window once contributions are routed.'),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  CheckboxListTile.adaptive(
                    value: _accSeverity,
                    onChanged: _scrolledToBottom
                        ? (v) => setState(() => _accSeverity = v ?? false)
                        : null,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: colors.danger,
                    title: Text(
                      'I understand defaulting is treated as theft.',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  CheckboxListTile.adaptive(
                    value: _accSeizure,
                    onChanged: _scrolledToBottom
                        ? (v) => setState(() => _accSeizure = v ?? false)
                        : null,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: colors.danger,
                    title: Text(
                      'I authorise auto-seizure of my available balance on collection day.',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canAccept ? _accept : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.danger,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: colors.danger.withOpacity(0.3),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape:
                            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        _busy ? 'Signing…' : 'I Accept — Sign Contract',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(AzamanColors colors, String s) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          s,
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
      );

  Widget _clause(AzamanColors colors, String head, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              head,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
}
