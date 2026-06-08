import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../providers/theme_provider.dart';
import '../services/api_client.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class FiatDepositScreen extends ConsumerStatefulWidget {
  const FiatDepositScreen({super.key});
  @override
  ConsumerState<FiatDepositScreen> createState() => _FiatDepositScreenState();
}

class _FiatDepositScreenState extends ConsumerState<FiatDepositScreen> {
  final _amount = TextEditingController();
  String _method = 'MOBILE_MONEY';
  bool _loading = false;
  Map<String, dynamic>? _instructions;
  String? _reference;
  String? _error;

  @override
  void dispose() {
    // Phase H10 BUGFIX (2026-05-27): the previous version never disposed
    // the amount controller — every navigation to this screen leaked one
    // TextEditingController.
    _amount.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'auth_token');
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Session expired. Please log in again.');
      return;
    }
    
    final amt = double.tryParse(_amount.text.trim());
    if (amt == null || amt <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    
    setState(() { _loading = true; _error = null; });
    
    try {
      // Map frontend method to backend provider enum
      final String provider = _method == 'MOBILE_MONEY' ? 'MTN_MOMO' : 'BANK_TRANSFER';
      
      final res = await apiClient.post('/deposit/fiat/initiate', {
        'amountGhs': amt,
        'provider': provider,
      });
      
      if (res.statusCode == 201 || res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final data = body['data'] ?? body;
        setState(() {
          _reference = data['reference']?.toString();
          _instructions = {
            'Reference': data['reference'] ?? '',
            'Amount': 'GHS ${amt.toStringAsFixed(2)}',
            'Provider': provider.replaceAll('_', ' '),
            'USDC Equivalent': '${data['usdcEquivalent']?.toStringAsFixed(2) ?? '0.00'} USDC',
            'Rate': '1 USD = ${data['quotedRate']?.toString() ?? '12.50'} GHS',
            'Valid Until': data['quoteValidUntil'] ?? 'N/A',
          };
          // Phase H10 BUGFIX (2026-05-27): the previous version iterated
          // the BE instructions list and assigned every entry to the
          // same `'Note'` key, so only the LAST instruction was rendered.
          // Now each instruction gets its own key (`Note 1`, `Note 2`,
          // …) and the user sees the full list.
          if (data['instructions'] is List) {
            final list = data['instructions'] as List;
            for (var i = 0; i < list.length; i++) {
              final key = list.length == 1 ? 'Note' : 'Note ${i + 1}';
              _instructions![key] = list[i].toString();
            }
          }
        });
      } else {
        final errBody = jsonDecode(res.body);
        setState(() => _error = errBody['message'] ?? 'Deposit initiation failed (${res.statusCode})');
      }
    } catch (e) {
      setState(() => _error = 'Network error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('Deposit Fiat', style: TextStyle(color: colors.textPrimary)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                color: colors.danger.withOpacity(0.1),
                child: Text(_error!, style: TextStyle(color: colors.danger)),
              ),
            Text('Amount (GHS)', style: TextStyle(color: colors.textSecondary)),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              style: TextStyle(color: colors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                filled: true,
                fillColor: colors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                prefixIcon: Icon(HugeIconsSolid.money01, color: colors.accent),
              ),
            ),
            const SizedBox(height: 20),
            Text('Payment Method', style: TextStyle(color: colors.textSecondary)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _method,
              dropdownColor: colors.surface,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: colors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              items: const [
                DropdownMenuItem(value: 'MOBILE_MONEY', child: Text('Mobile Money (MTN/Telecel)')),
                DropdownMenuItem(value: 'BANK_TRANSFER', child: Text('Bank Transfer')),
              ],
              onChanged: (val) => setState(() => _method = val!),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _loading ? null : _initialize,
                child: _loading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Proceed', style: TextStyle(fontSize: 18, color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
            if (_instructions != null) ...[
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.accent.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Transfer Instructions', style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    ..._instructions!.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key.toUpperCase(), style: TextStyle(color: colors.textSecondary)),
                          Row(
                            children: [
                              Text(e.value.toString(), style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: Icon(HugeIconsSolid.copy01, size: 16, color: colors.accent),
                                onPressed: () => _copyToClipboard(e.value.toString(), e.key),
                              )
                            ],
                          )
                        ],
                      ),
                    )),
                  ],
                ),
              )
            ]
          ],
        ),
      ),
    );
  }
}
