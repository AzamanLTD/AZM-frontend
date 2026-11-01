// =============================================================================
// SUSU CONFIG SCREEN  (Master Sprint, 2026-05-27)
//
// Admin-only screen to configure a susu inside an existing GroupChat.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/money/native_amount_display.dart';

class SusuConfigScreen extends ConsumerStatefulWidget {
  final String groupChatId;

  /// Clock seam: production defaults to the real clock; golden tests
  /// pass a fixed date so the default start-date label is stable
  /// across midnights (the goldens must not silently roll over).
  final DateTime Function()? now;

  const SusuConfigScreen({super.key, required this.groupChatId, this.now});

  @override
  ConsumerState<SusuConfigScreen> createState() => _SusuConfigScreenState();
}

class _SusuConfigScreenState extends ConsumerState<SusuConfigScreen> {
  final _amount = TextEditingController(text: '20');

  /// The amount as typed, USDC-denominated. Read-only input for the honest
  /// GHS estimate line beneath the field — display, never authority.
  double get _parsedAmount => double.tryParse(_amount.text.trim()) ?? 0;
  String _frequency = 'WEEKLY';
  late DateTime _startDate = (widget.now ?? DateTime.now)().add(
    const Duration(days: 1),
  );
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amt = double.tryParse(_amount.text.trim());
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a positive contribution amount.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(susuActionsProvider)
          .createSusu(
            groupChatId: widget.groupChatId,
            contributionUsdc: amt,
            frequency: _frequency,
            startDate: _startDate,
          );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Configure Susu',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        // Scrollable: the warning contract card + CTA push this column past
        // the fold on short viewports (measured 15px over at 600dp in the
        // native-amount surface suite); scrolling never clips the CTA.
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(colors, 'Contribution per Cycle (USDC)'),
              _input(
                colors,
                _amount,
                hint: '20.00',
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              // GHS reading of the typed amount, honestly labelled. The FIELD
              // keeps submitting USDC — the susu rail's principal denomination —
              // so no currency wheel is offered here: a wheel would imply an
              // authoritative GHS principal, and the reviewed GHS-authority
              // backend contract (plan v3) is design-only (Workstream D1).
              AmountEntryEquivalent(
                amountUsdc: _parsedAmount,
                railNote: 'contribution amount denominated in USDC',
              ),
              const SizedBox(height: 14),
              _label(colors, 'Frequency'),
              Wrap(
                spacing: 6,
                children: ['WEEKLY', 'BIWEEKLY', 'MONTHLY']
                    .map(
                      (f) => ChoiceChip(
                        selected: _frequency == f,
                        label: Text(f),
                        selectedColor: colors.warning.withValues(alpha: 0.20),
                        onSelected: (_) => setState(() => _frequency = f),
                        labelStyle: TextStyle(
                          color: _frequency == f
                              ? colors.warning
                              : colors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              _label(colors, 'First Cycle Start'),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _startDate,
                    firstDate: (widget.now ?? DateTime.now)(),
                    lastDate: (widget.now ?? DateTime.now)().add(
                      const Duration(days: 365),
                    ),
                  );
                  if (picked != null) setState(() => _startDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        color: colors.warning,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colors.warning.withValues(alpha: 0.30),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: colors.warning, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cycle count is auto-set to the number of group members. Each member must sign the warning contract before the susu starts.',
                        style: TextStyle(
                          color: colors.warning,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.warning,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _busy ? 'Configuring…' : 'Configure Susu',
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
      ),
    );
  }

  Widget _label(AzamanColors colors, String s) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 2),
    child: Text(
      s.toUpperCase(),
      style: TextStyle(
        color: colors.textTertiary,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    ),
  );

  Widget _input(
    AzamanColors colors,
    TextEditingController c, {
    String? hint,
    TextInputType? keyboard,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: c,
        // Rebuild on every keystroke so the honest GHS estimate line
        // tracks typing (measured: without this the equivalent froze at the
        // field's initial value — native-amount surface suite, Workstream D1).
        onChanged: (_) => setState(() {}),
        keyboardType: keyboard,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
        ),
      ),
    );
  }
}
