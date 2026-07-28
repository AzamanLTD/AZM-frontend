import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/worker_provider.dart';
import 'dart:convert';
import 'package:azaman/services/api_client.dart';

class WorkerEwaScreen extends ConsumerStatefulWidget {
  const WorkerEwaScreen({super.key});

  @override
  ConsumerState<WorkerEwaScreen> createState() => _WorkerEwaScreenState();
}

class _WorkerEwaScreenState extends ConsumerState<WorkerEwaScreen> {
  final _amountController = TextEditingController();
  bool _submitting = false;

  Future<void> _requestEwa() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) return;
    setState(() => _submitting = true);
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.post('/api/business-os/employees/my-ewa-request', {'amount': amount});
      if (res.statusCode == 200) {
        ref.refresh(myEwaProvider);
        ref.refresh(workerDashboardProvider);
        _amountController.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('EWA withdrawal successful!'), backgroundColor: Colors.green));
        }
      } else {
        final body = jsonDecode(res.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(body['message'] ?? 'Request failed'), backgroundColor: Colors.red));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request failed'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final ewaAsync = ref.watch(myEwaProvider);

    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        title: Text('Earned Wage Access', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: ewaAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
        error: (_, __) => Center(child: Text('Unable to load', style: TextStyle(color: colors.textSecondary))),
        data: (ewa) {
          final available = (ewa['ewaAvailable'] as num?)?.toDouble() ?? 0;
          final accrued = (ewa['accruedWages'] as num?)?.toDouble() ?? 0;
          final withdrawn = (ewa['withdrawnEarly'] as num?)?.toDouble() ?? 0;
          final history = ewa['ewaHistory'] as List<dynamic>? ?? [];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colors.accentSecondary.withValues(alpha: 0.15), colors.accentSecondary.withValues(alpha: 0.03)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.accentSecondary.withValues(alpha: 0.2), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Available to Withdraw', style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text('\$${available.toStringAsFixed(2)}', style: TextStyle(color: colors.textPrimary, fontSize: 36, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Accrued', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                          Text('\$${accrued.toStringAsFixed(2)}', style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                        ])),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Withdrawn', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                          Text('\$${withdrawn.toStringAsFixed(2)}', style: TextStyle(color: colors.warning, fontSize: 14, fontWeight: FontWeight.w600)),
                        ])),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (available > 0) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surface, borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.border, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Withdraw', style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text('1% fee deducted from your withdrawal. Max 30% of accrued wages.',
                          style: TextStyle(color: colors.textTertiary, fontSize: 12)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          prefixText: '\$ ',
                          hintText: '0.00',
                          hintStyle: TextStyle(color: colors.textTertiary),
                          filled: true, fillColor: colors.scaffoldBackground,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colors.border)),
                        ),
                        style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _requestEwa,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.accent, foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _submitting
                              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : Text('Withdraw Now', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              if (history.isNotEmpty) ...[
                Text('History', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                ...history.map((h) {
                  final entry = h as Map<String, dynamic>;
                  final amount = (entry['amount'] as num?)?.toDouble() ?? 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.surface, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.border, width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.bolt, color: colors.accentSecondary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text('EWA Withdrawal', style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500))),
                        Text('\$${amount.abs().toStringAsFixed(2)}', style: TextStyle(color: colors.accentSecondary, fontSize: 14, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }
}
