// =============================================================================
// SEND MONEY SCREEN — Internal transfer by AZM ID or BIZ ID
// =============================================================================
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/scale_tap.dart';

class SendMoneyScreen extends ConsumerStatefulWidget {
  const SendMoneyScreen({super.key});

  @override
  ConsumerState<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends ConsumerState<SendMoneyScreen> {
  final _idController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  bool _isLoading = false;
  bool _isLookingUp = false;
  Map<String, dynamic>? _recipient;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    _idController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _lookupRecipient() async {
    final id = _idController.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _isLookingUp = true;
      _recipient = null;
      _error = null;
    });
    try {
      final api = ApiClient();
      final res = await api.get('/users/lookup?identifier=$id');
      if (res.statusCode == 200) {
        setState(() => _recipient = jsonDecode(res.body) as Map<String, dynamic>?);
      } else {
        setState(() => _error = 'User not found. Check the AZM ID or BIZ ID.');
      }
    } catch (_) {
      setState(() => _error = 'Could not look up recipient. Check your connection.');
    } finally {
      if (mounted) setState(() => _isLookingUp = false);
    }
  }

  Future<void> _send() async {
    if (_recipient == null) return;
    final amountStr = _amountController.text.trim();
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    AzamanHaptics.confirm();
    try {
      final api = ApiClient();
      final res = await api.post('/finance/internal-transfer', {
        'recipientIdentifier': _idController.text.trim(),
        'amountUsdc': amount,
        if (_noteController.text.trim().isNotEmpty)
          'note': _noteController.text.trim(),
      });
      if (res.statusCode == 200 || res.statusCode == 201) {
        AzamanHaptics.commit();
        setState(() => _successMessage = 'Sent $amountStr USDC successfully.');
        _amountController.clear();
        _noteController.clear();
      } else {
        final data = jsonDecode(res.body) as Map<String, dynamic>?;
        final msg = data?.containsKey('message') == true
            ? data!['message'].toString()
            : 'Transfer failed. Please try again.';
        setState(() => _error = msg);
      }
    } catch (_) {
      setState(() => _error = 'Transfer failed. Check your connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final balance = ref.watch(authProvider).user?.availableBalance ?? 0.0;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Send Money',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarIconBrightness:
              colors.isDark ? Brightness.light : Brightness.dark,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Balance chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.accentSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(HugeIconsSolid.wallet01, size: 16, color: colors.accent),
                  const SizedBox(width: 8),
                  Text('Available: ${balance.toStringAsFixed(2)} USDC',
                      style: TextStyle(
                          color: colors.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(height: 24),

              // Recipient lookup
              Text('Recipient',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _idController,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'AZM ID or BIZ ID',
                      hintStyle: TextStyle(color: colors.textTertiary),
                      prefixIcon: Icon(HugeIconsSolid.userSearch01,
                          color: colors.textTertiary, size: 18),
                      filled: true,
                      fillColor: colors.card,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: colors.accent.withValues(alpha: 0.5))),
                    ),
                    onSubmitted: (_) => _lookupRecipient(),
                  ),
                ),
                const SizedBox(width: 10),
                ScaleTap(
                  onTap: _lookupRecipient,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(12)),
                    child: _isLookingUp
                        ? Padding(
                            padding: const EdgeInsets.all(13),
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.isDark
                                    ? Colors.black
                                    : Colors.white))
                        : Icon(HugeIconsSolid.search01,
                            color:
                                colors.isDark ? Colors.black : Colors.white,
                            size: 20),
                  ),
                ),
              ]),

              // Recipient card
              if (_recipient != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: colors.accent.withValues(alpha: 0.3))),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: colors.accentSurface,
                      child: Text(
                        ((_recipient!['username'] as String?) ?? '?')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: TextStyle(
                            color: colors.accent,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_recipient!['username'] ?? '',
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                            if (_recipient!['fullName'] != null)
                              Text(_recipient!['fullName'],
                                  style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 12)),
                          ]),
                    ),
                    Icon(HugeIconsSolid.checkmarkCircle01,
                        color: colors.success, size: 20),
                  ]),
                ),
              ],

              const SizedBox(height: 20),

              // Amount
              Text('Amount (USDC)',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: '0.00',
                  hintStyle: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700),
                  prefixText: 'USDC  ',
                  prefixStyle: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                  filled: true,
                  fillColor: colors.card,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: colors.accent.withValues(alpha: 0.5))),
                ),
              ),
              const SizedBox(height: 14),

              // Note (optional)
              TextField(
                controller: _noteController,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Add a note (optional)',
                  hintStyle: TextStyle(color: colors.textTertiary),
                  prefixIcon: Icon(HugeIconsSolid.note01,
                      color: colors.textTertiary, size: 18),
                  filled: true,
                  fillColor: colors.card,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),

              // Error / success
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: colors.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Icon(HugeIconsSolid.alertCircle,
                        color: colors.danger, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_error!,
                            style: TextStyle(
                                color: colors.danger, fontSize: 13))),
                  ]),
                ),
              ],
              if (_successMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: colors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Icon(HugeIconsSolid.checkmarkCircle01,
                        color: colors.success, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_successMessage!,
                            style: TextStyle(
                                color: colors.success, fontSize: 13))),
                  ]),
                ),
              ],

              const SizedBox(height: 28),

              // Send button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed:
                      (_recipient == null || _isLoading) ? null : _send,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor:
                        colors.isDark ? Colors.black : Colors.white,
                    disabledBackgroundColor: colors.divider,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: colors.isDark
                                  ? Colors.black
                                  : Colors.white))
                      : const Text('Send',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
