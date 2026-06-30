// lib/screens/p2p/p2p_filter_sheet.dart
// =============================================================================
// P2P ADVANCED FILTER SHEET — P2P Premium Sprint (2026-06-21)
//
// Modal bottom sheet opened from the P2PMarketListScreen's filter button.
// State: read current P2PFilters from p2pFiltersProvider, edit locally,
// apply on [Apply] or reset on [Reset]. Live count badge on the filter button.
//
// Payment methods shown: the 10 most common methods in the loaded ads
// (computed dynamically) so the list is always relevant.
//
// Usage:
//   P2PFilterSheet.show(context);
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import 'package:azaman/providers/marketplace_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class P2PFilterSheet extends ConsumerStatefulWidget {
  const P2PFilterSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const P2PFilterSheet(),
    );
  }

  @override
  ConsumerState<P2PFilterSheet> createState() => _P2PFilterSheetState();
}

class _P2PFilterSheetState extends ConsumerState<P2PFilterSheet> {
  late Set<String> _selectedMethods;
  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;
  late double _minCompletion; // 0, 0.8, 0.9, 0.95
  late bool _onlineOnly;

  // The 10 most common payment methods in the currently loaded ads
  List<String> _availableMethods = const [];

  @override
  void initState() {
    super.initState();
    final current = ref.read(p2pFiltersProvider);
    _selectedMethods = Set.from(current.paymentMethods);
    _minCtrl = TextEditingController(
        text: current.minAmount?.toStringAsFixed(0) ?? '');
    _maxCtrl = TextEditingController(
        text: current.maxAmount?.toStringAsFixed(0) ?? '');
    _minCompletion = current.minCompletionRate;
    _onlineOnly = current.onlineOnly;
    _buildMethodList();
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  void _buildMethodList() {
    final adsAsync = ref.read(adsProvider);
    adsAsync.whenData((ads) {
      final freq = <String, int>{};
      for (final a in ads) {
        final m = a.paymentMethod.toUpperCase();
        freq[m] = (freq[m] ?? 0) + 1;
      }
      final sorted = freq.keys.toList()
        ..sort((a, b) => (freq[b] ?? 0).compareTo(freq[a] ?? 0));
      setState(() => _availableMethods = sorted.take(10).toList());
    });
  }

  void _apply() {
    AzamanHaptics.commit();
    ref.read(p2pFiltersProvider.notifier).state = P2PFilters(
      paymentMethods: _selectedMethods,
      minAmount: double.tryParse(_minCtrl.text.trim()),
      maxAmount: double.tryParse(_maxCtrl.text.trim()),
      minCompletionRate: _minCompletion,
      onlineOnly: _onlineOnly,
    );
    Navigator.pop(context);
  }

  void _reset() {
    AzamanHaptics.toggle();
    setState(() {
      _selectedMethods = {};
      _minCtrl.clear();
      _maxCtrl.clear();
      _minCompletion = 0;
      _onlineOnly = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final onAccent = colors.isDark ? Colors.black : Colors.white;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 16),
            // Header
            Row(
              children: [
                Icon(HugeIconsSolid.filterHorizontal,
                    color: colors.accent, size: 20),
                const SizedBox(width: 8),
                Text('Filter Ads',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton(
                  onPressed: _reset,
                  child: Text('Reset all',
                      style:
                          TextStyle(color: colors.textTertiary, fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Payment methods
            _sectionLabel(colors, 'Payment Method'),
            const SizedBox(height: 10),
            if (_availableMethods.isEmpty)
              Text('Loading…',
                  style: TextStyle(color: colors.textTertiary, fontSize: 12))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableMethods.map((m) {
                  final sel = _selectedMethods.contains(m);
                  return GestureDetector(
                    onTap: () {
                      AzamanHaptics.toggle();
                      setState(() {
                        if (sel) {
                          _selectedMethods.remove(m);
                        } else {
                          _selectedMethods = {..._selectedMethods, m};
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? colors.accent : colors.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: sel ? colors.accent : colors.divider),
                      ),
                      child: Text(
                        m,
                        style: TextStyle(
                          color: sel ? onAccent : colors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 20),
            // Amount range
            _sectionLabel(colors, 'Amount Range (USD)'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _amountField(colors, _minCtrl, 'Min')),
                const SizedBox(width: 12),
                Expanded(child: _amountField(colors, _maxCtrl, 'Max')),
              ],
            ),
            const SizedBox(height: 20),
            // Completion rate
            _sectionLabel(colors, 'Min Completion Rate'),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final rate in [0.0, 0.8, 0.9, 0.95])
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        AzamanHaptics.toggle();
                        setState(() => _minCompletion = rate);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: _minCompletion == rate
                              ? colors.accent
                              : colors.card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _minCompletion == rate
                                  ? colors.accent
                                  : colors.divider),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          rate == 0
                              ? 'Any'
                              : '≥${(rate * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            color: _minCompletion == rate
                                ? onAccent
                                : colors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Online-only toggle
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Online vendors only',
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      Text('Only show vendors who are currently active',
                          style: TextStyle(
                              color: colors.textTertiary, fontSize: 12)),
                    ],
                  ),
                ),
                Switch(
                  value: _onlineOnly,
                  onChanged: (v) {
                    AzamanHaptics.toggle();
                    setState(() => _onlineOnly = v);
                  },
                  activeColor: colors.accent,
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Apply button
            SizedBox(
              height: 52,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _apply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: onAccent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Apply Filters',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(AzamanColors colors, String label) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: colors.textTertiary,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _amountField(
      AzamanColors colors, TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
      ],
      style: TextStyle(color: colors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        prefixText: '\$',
        hintStyle: TextStyle(color: colors.textTertiary),
        prefixStyle: TextStyle(color: colors.textTertiary),
        filled: true,
        fillColor: colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
