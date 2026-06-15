// =============================================================================
// FIAT DEPOSIT FLOW — Mobile Money & Local Payment Deposit
//
// Supports: MTN MoMo, Vodafone Cash, AirtelTigo, TelecelCash, Bank Transfer
// Flow:
//   1. User selects provider + enters amount
//   2. POST /api/deposit/fiat/initiate → gets reference + instructions
//   3. User completes payment externally
//   4. Backend webhook confirms → balance credited automatically
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class FiatDepositFlowScreen extends ConsumerStatefulWidget {
  const FiatDepositFlowScreen({super.key});

  @override
  ConsumerState<FiatDepositFlowScreen> createState() => _FiatDepositFlowScreenState();
}

class _FiatDepositFlowScreenState extends ConsumerState<FiatDepositFlowScreen> {
  final _amountController = TextEditingController();
  String _selectedProvider = 'MTN_MOMO';
  bool _isSubmitting = false;
  Map<String, dynamic>? _depositResult;

  final _providers = [
    {'id': 'MTN_MOMO', 'name': 'MTN MoMo', 'icon': HugeIconsSolid.smartPhone01, 'color': const Color(0xFFFFCC00)},
    {'id': 'VODAFONE_CASH', 'name': 'Vodafone Cash', 'icon': HugeIconsSolid.smartPhone01, 'color': const Color(0xFFE60000)},
    {'id': 'AIRTELTIGO', 'name': 'AirtelTigo/Telecel', 'icon': HugeIconsSolid.smartPhone01, 'color': const Color(0xFF0066CC)},
    {'id': 'BANK_TRANSFER', 'name': 'Bank Transfer', 'icon': HugeIconsSolid.bank, 'color': const Color(0xFF2E7D32)},
  ];

  Future<void> _initiateDeposit() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final response = await apiClient.post('/deposit/fiat/initiate', {
        'amountGhs': amount,
        'provider': _selectedProvider,
      });

      final body = jsonDecode(response.body);

      if (response.statusCode == 201) {
        HapticFeedback.heavyImpact();
        setState(() {
          _depositResult = body['data'];
          _isSubmitting = false;
        });
      } else {
        setState(() => _isSubmitting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(body['message'] ?? 'Failed to initiate deposit')),
          );
        }
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text('Deposit Funds', style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: colors.textPrimary),
        elevation: 0,
      ),
      body: _depositResult != null ? _buildConfirmation(colors) : _buildForm(colors),
    );
  }

  Widget _buildForm(AzamanColors colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Amount input
          Text('Amount (GHS)', style: TextStyle(color: colors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: colors.textPrimary, fontSize: 24, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: TextStyle(color: colors.textTertiary),
              prefixText: 'GH\u20B5 ',
              prefixStyle: TextStyle(color: colors.accent, fontSize: 24, fontWeight: FontWeight.w800),
              filled: true,
              fillColor: colors.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            ),
          ),

          const SizedBox(height: 28),

          // Provider selection
          Text('Payment Method', style: TextStyle(color: colors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),

          ...(_providers.map((p) => _providerTile(colors, p))),

          const SizedBox(height: 32),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _initiateDeposit,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.isDark ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSubmitting
                  ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: colors.isDark ? Colors.black : Colors.white))
                  : const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _providerTile(AzamanColors colors, Map<String, dynamic> provider) {
    final isSelected = _selectedProvider == provider['id'];
    final providerColor = provider['color'] as Color;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedProvider = provider['id'] as String);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? providerColor.withOpacity(0.08) : colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? providerColor.withOpacity(0.5) : colors.divider,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: providerColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(provider['icon'] as IconData, color: providerColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                provider['name'] as String,
                style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            if (isSelected)
              Icon(HugeIconsSolid.checkmarkCircle01, color: providerColor, size: 22)
            else
              Icon(HugeIconsSolid.circle, color: colors.textTertiary, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmation(AzamanColors colors) {
    final reference = _depositResult!['reference'] ?? '';
    final amountGhs = (_depositResult!['amountGhs'] as num?)?.toDouble() ?? 0;
    final usdcEquiv = (_depositResult!['usdcEquivalent'] as num?)?.toDouble() ?? 0;
    final instructions = (_depositResult!['instructions'] as List?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Success indicator
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.success.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(HugeIconsSolid.checkmarkCircle01, color: colors.success, size: 48),
          ),
          const SizedBox(height: 20),
          Text('Deposit Initiated', style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Complete the payment to receive your funds', style: TextStyle(color: colors.textSecondary, fontSize: 13)),

          const SizedBox(height: 28),

          // Amount summary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
            ),
            child: Column(
              children: [
                _summaryRow(colors, 'Amount', 'GH\u20B5 ${amountGhs.toStringAsFixed(2)}'),
                _summaryRow(colors, 'You Receive', '~${usdcEquiv.toStringAsFixed(4)} USDC'),
                _summaryRow(colors, 'Provider', _selectedProvider.replaceAll('_', ' ')),
                const SizedBox(height: 12),
                Divider(color: colors.divider),
                const SizedBox(height: 12),
                // Reference
                Row(
                  children: [
                    Text('Reference:', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: reference));
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Reference copied')),
                        );
                      },
                      child: Row(
                        children: [
                          Text(
                            reference.length > 20 ? '${reference.substring(0, 20)}...' : reference,
                            style: TextStyle(color: colors.accent, fontSize: 11, fontFamily: 'monospace'),
                          ),
                          const SizedBox(width: 4),
                          Icon(HugeIconsSolid.copy01, color: colors.accent, size: 14),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Instructions
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.accent.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.accent.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payment Instructions', style: TextStyle(color: colors.accent, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                ...instructions.asMap().entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          color: colors.accent.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text('${entry.key + 1}', style: TextStyle(color: colors.accent, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(entry.value.toString(), style: TextStyle(color: colors.textSecondary, fontSize: 13))),
                    ],
                  ),
                )),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Done button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.isDark ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Done', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(AzamanColors colors, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: colors.textTertiary, fontSize: 13)),
          Text(value, style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }
}
