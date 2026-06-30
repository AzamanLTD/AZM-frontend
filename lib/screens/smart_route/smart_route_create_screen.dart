// =============================================================================
// SMART ROUTE CREATE SCREEN  (Master Sprint, 2026-05-27)
//
// Step-form: action → amount → schedule → destination.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/smart_route_provider.dart';
import 'package:azaman/providers/theme_provider.dart';


class SmartRouteCreateScreen extends ConsumerStatefulWidget {
  const SmartRouteCreateScreen({super.key});

  @override
  ConsumerState<SmartRouteCreateScreen> createState() =>
      _SmartRouteCreateScreenState();
}

class _SmartRouteCreateScreenState extends ConsumerState<SmartRouteCreateScreen> {
  final _name = TextEditingController(text: 'My Auto Payment');
  final _amount = TextEditingController();
  final _momoNumber = TextEditingController();
  String _action = 'WITHDRAW_MOMO';
  String _frequency = 'MONTHLY';
  int _dayOfMonth = 28;
  String _momoProvider = 'MTN';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _momoNumber.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amt = double.tryParse(_amount.text.trim());
    if (amt == null || amt <= 0 || _name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a name and a positive amount.')),
      );
      return;
    }
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'action': _action,
      'amountUsdc': amt,
      'frequency': _frequency,
      'startDate': DateTime.now().toIso8601String(),
    };
    if (_frequency == 'ON_DAY_OF_MONTH') body['dayOfMonth'] = _dayOfMonth;
    final dest = <String, dynamic>{};
    if (_action == 'WITHDRAW_MOMO') {
      if (_momoNumber.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a MoMo number.')),
        );
        return;
      }
      dest['momoNumber'] = _momoNumber.text.trim();
      dest['momoProvider'] = _momoProvider;
    }
    body['destination'] = dest;

    setState(() => _busy = true);
    try {
      await ref.read(smartRoutesProvider.notifier).create(body);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
        title: Text('New Smart Route',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            )),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Explainer card
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.accent.withOpacity(0.2)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.bolt_outlined, size: 18, color: colors.accent),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("What is a Smart Route?", style: TextStyle(
                    color: colors.accent, fontSize: 13, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    "Smart Routes run automatically on a schedule. "
                    "Set up a monthly MoMo withdrawal, recurring vault deposit, "
                    "or scheduled transfer — once. It runs on its own after that.",
                    style: TextStyle(color: colors.textSecondary, fontSize: 12, height: 1.4),
                  ),
                ])),
              ]),
            ),
            _label(colors, 'Action'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ('WITHDRAW_MOMO', 'MoMo Withdraw'),
                ('INTERNAL_TRANSFER', 'Internal Transfer'),
                ('SAVINGS_DEPOSIT', 'Savings Deposit'),
                ('VAULT_DEPOSIT', 'Vault Deposit'),
              ]
                  .map((p) => ChoiceChip(
                        selected: _action == p.$1,
                        label: Text(p.$2),
                        selectedColor: colors.accent.withOpacity(0.20),
                        onSelected: (_) => setState(() => _action = p.$1),
                        labelStyle: TextStyle(
                          color: _action == p.$1 ? colors.accent : colors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 14),
            _label(colors, 'Name'),
            _input(colors, _name),
            const SizedBox(height: 14),
            _label(colors, 'Amount (USDC)'),
            _input(
              colors,
              _amount,
              hint: '100.00',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 14),
            _label(colors, 'Frequency'),
            Wrap(
              spacing: 6,
              children: ['DAILY', 'WEEKLY', 'MONTHLY', 'ON_DAY_OF_MONTH']
                  .map((f) => ChoiceChip(
                        selected: _frequency == f,
                        label: Text(f),
                        selectedColor: colors.accent.withOpacity(0.20),
                        onSelected: (_) => setState(() => _frequency = f),
                        labelStyle: TextStyle(
                          color: _frequency == f ? colors.accent : colors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ))
                  .toList(),
            ),
            if (_frequency == 'ON_DAY_OF_MONTH') ...[
              const SizedBox(height: 10),
              _label(colors, 'Day of Month'),
              Slider(
                value: _dayOfMonth.toDouble(),
                min: 1,
                max: 28,
                divisions: 27,
                label: '$_dayOfMonth',
                activeColor: colors.accent,
                onChanged: (v) => setState(() => _dayOfMonth = v.toInt()),
              ),
            ],
            if (_action == 'WITHDRAW_MOMO') ...[
              const SizedBox(height: 14),
              _label(colors, 'MoMo Provider'),
              Wrap(
                spacing: 6,
                children: ['MTN', 'VODAFONE', 'TELECEL']
                    .map((p) => ChoiceChip(
                          selected: _momoProvider == p,
                          label: Text(p),
                          selectedColor: colors.accent.withOpacity(0.20),
                          onSelected: (_) => setState(() => _momoProvider = p),
                          labelStyle: TextStyle(
                            color: _momoProvider == p ? colors.accent : colors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 10),
              _label(colors, 'MoMo Number'),
              _input(colors, _momoNumber, hint: '054XXXXXXX'),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.isDark ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _busy ? 'Creating…' : 'Create Route',
                  style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4),
                ),
              ),
            ),
          ],
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

  Widget _input(AzamanColors colors, TextEditingController c,
      {String? hint, TextInputType? keyboard}) {
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
        ),
      ),
    );
  }
}
