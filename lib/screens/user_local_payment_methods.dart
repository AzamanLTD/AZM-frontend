// lib/screens/user_local_payment_methods.dart
//
// Purpose-built screen for regular users to manage their local Ghana
// payout destinations: MTN MoMo, Telecel Cash, AirtelTigo Money and
// Bank Transfer. Reuses the existing /api/wallet/saved backend by
// sending `type` as the network label — the server treats anything
// non-"Crypto Wallet" as FIAT_ACCOUNT.
//
// Invoked from:
//   • settings_screen.dart → "Payment Methods" tile
//   • withdrawal_screen.dart → "Add Wallet" button (when no wallets saved)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/providers/theme_provider.dart';


class UserLocalPaymentMethodsScreen extends ConsumerStatefulWidget {
  const UserLocalPaymentMethodsScreen({super.key});

  @override
  ConsumerState<UserLocalPaymentMethodsScreen> createState() =>
      _UserLocalPaymentMethodsScreenState();
}

class _UserLocalPaymentMethodsScreenState
    extends ConsumerState<UserLocalPaymentMethodsScreen> {
  static const List<String> _localTypes = [
    'MTN MoMo',
    'Telecel Cash',
    'AirtelTigo Money',
    'Bank Transfer',
  ];

  bool _isLoading = true;
  bool _isSaving = false;
  List<dynamic> _methods = [];

  @override
  void initState() {
    super.initState();
    _fetchMethods();
  }

  Future<void> _fetchMethods() async {
    setState(() => _isLoading = true);
    try {
      final res = await apiClient.get('/wallet/saved');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final all = List<dynamic>.from(data['wallets'] ?? []);
        // Keep only fiat-style local methods.
        _methods = all.where((w) {
          final type = (w['provider'] ?? '').toString();
          return _localTypes.contains(type);
        }).toList();
      }
    } catch (e) {
      debugPrint('Local methods fetch error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveMethod({
    required String type,
    required String label,
    required String accountNumber,
    required String accountName,
    String? bankName,
  }) async {
    setState(() => _isSaving = true);
    try {
      final res = await apiClient.post('/wallet/saved', {
        'type': type,
        'label': label,
        'address': accountNumber,
        'accountName': accountName,
        'secondaryDetail': bankName,
      });
      final ok = res.statusCode == 200 || res.statusCode == 201;
      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? 'Payment method saved'
                : 'Could not save — check details'),
            backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
          ),
        );
      }
      if (ok) _fetchMethods();
    } catch (e) {
      debugPrint('Save method error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteMethod(int id) async {
    try {
      await apiClient.delete('/wallet/saved/$id');
      HapticFeedback.lightImpact();
      _fetchMethods();
    } catch (_) {}
  }

  // ------ UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Payment Methods',
          style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        color: colors.accent,
        onRefresh: _fetchMethods,
        child: _isLoading
            ? _buildSkeleton(colors)
            : _methods.isEmpty
                ? _buildEmpty(colors)
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _methods.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _buildTile(_methods[i], colors),
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Add Method',
            style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () {
          HapticFeedback.selectionClick();
          _showAddSheet(colors);
        },
      ),
    );
  }

  Widget _buildSkeleton(AzamanColors colors) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        height: 76,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider),
        ),
      ),
    );
  }

  Widget _buildEmpty(AzamanColors colors) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.account_balance_wallet_outlined,
            size: 56, color: colors.textTertiary),
        const SizedBox(height: 16),
        Center(
          child: Text('No payment methods yet',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Add your Mobile Money or Bank details for\nfaster withdrawals.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildTile(Map<String, dynamic> m, AzamanColors colors) {
    final String type = m['provider'] ?? 'UNKNOWN';
    final String label = m['label'] ?? '';
    final String number = m['address'] ?? '';
    final String? owner = m['accountName'];
    final String? bank = m['secondaryDetail'];
    final int id = int.tryParse(m['id']?.toString() ?? '0') ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: _typeColor(type, colors).withValues(alpha: 0.15),
            child: Icon(_typeIcon(type),
                color: _typeColor(type, colors), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.isEmpty ? type : label,
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(number,
                    style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontFamily: 'monospace')),
                if ((owner ?? '').isNotEmpty)
                  Text(owner!,
                      style: TextStyle(
                          color: colors.textTertiary, fontSize: 11)),
                if ((bank ?? '').isNotEmpty && type == 'Bank Transfer')
                  Text(bank!,
                      style: TextStyle(
                          color: colors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: colors.danger),
            onPressed: () => _confirmDelete(id, colors),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(int id, AzamanColors colors) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: colors.card,
        title: Text('Remove method?',
            style: TextStyle(color: colors.textPrimary)),
        content: Text('This payment method will no longer appear in withdrawals.',
            style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL', style: TextStyle(color: colors.textTertiary))),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteMethod(id);
              },
              child: Text('REMOVE', style: TextStyle(color: colors.danger))),
        ],
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'MTN MoMo':
        return Icons.smartphone_outlined;
      case 'Telecel Cash':
        return Icons.sim_card_outlined;
      case 'AirtelTigo Money':
        return Icons.smartphone_outlined;
      case 'Bank Transfer':
        return Icons.account_balance_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  Color _typeColor(String type, AzamanColors colors) {
    switch (type) {
      case 'MTN MoMo':
        return colors.warning;
      case 'Telecel Cash':
        return colors.danger;
      case 'AirtelTigo Money':
        return colors.success;
      case 'Bank Transfer':
        return colors.accent;
      default:
        return colors.textTertiary;
    }
  }

  // ------ ADD SHEET ----------------------------------------------------------

  void _showAddSheet(AzamanColors colors) {
    String selectedType = _localTypes.first;
    final labelCtrl = TextEditingController();
    final numberCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final bankCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final bool isBank = selectedType == 'Bank Transfer';
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 18,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.divider,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Add Payment Method',
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  // Type selector
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _localTypes.map((t) {
                      final sel = t == selectedType;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setSheet(() => selectedType = t);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: sel
                                ? _typeColor(t, colors).withValues(alpha: 0.15)
                                : colors.surface,
                            border: Border.all(
                                color: sel
                                    ? _typeColor(t, colors)
                                    : colors.divider),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_typeIcon(t),
                                  size: 14, color: _typeColor(t, colors)),
                              const SizedBox(width: 6),
                              Text(t,
                                  style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  _field(
                    controller: labelCtrl,
                    label: 'Nickname (e.g. "My MTN")',
                    colors: colors,
                    required: true,
                  ),
                  const SizedBox(height: 10),
                  _field(
                    controller: nameCtrl,
                    label: 'Account / Holder Name',
                    colors: colors,
                    required: true,
                  ),
                  const SizedBox(height: 10),
                  _field(
                    controller: numberCtrl,
                    label: isBank ? 'Account Number' : 'Phone Number',
                    colors: colors,
                    keyboardType: TextInputType.number,
                    required: true,
                  ),
                  if (isBank) ...[
                    const SizedBox(height: 10),
                    _field(
                      controller: bankCtrl,
                      label: 'Bank Name (e.g. GCB, Ecobank)',
                      colors: colors,
                      required: true,
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isSaving
                        ? null
                        : () {
                            if (!formKey.currentState!.validate()) return;
                            Navigator.pop(ctx);
                            _saveMethod(
                              type: selectedType,
                              label: labelCtrl.text.trim(),
                              accountNumber: numberCtrl.text.trim(),
                              accountName: nameCtrl.text.trim(),
                              bankName: isBank ? bankCtrl.text.trim() : null,
                            );
                          },
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black),
                          )
                        : const Text('SAVE METHOD',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required AzamanColors colors,
    TextInputType? keyboardType,
    bool required = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(color: colors.textPrimary),
      validator: required
          ? (v) =>
              (v == null || v.trim().isEmpty) ? 'This field is required' : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: colors.textTertiary),
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.accent),
        ),
      ),
    );
  }
}
