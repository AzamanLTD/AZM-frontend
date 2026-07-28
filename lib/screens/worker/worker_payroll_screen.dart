import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/worker_provider.dart';
import 'package:azaman/models/employee_models.dart';

class WorkerPayrollScreen extends ConsumerWidget {
  const WorkerPayrollScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final payrollAsync = ref.watch(myPayrollProvider);

    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        title: Text('Payroll', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: payrollAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
        error: (_, __) => Center(child: Text('Unable to load payroll', style: TextStyle(color: colors.textSecondary))),
        data: (records) {
          if (records.isEmpty) {
            return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.payments_outlined, size: 48, color: colors.textTertiary),
                const SizedBox(height: 12),
                Text('No payroll records yet', style: TextStyle(color: colors.textSecondary, fontSize: 15)),
              ],
            ));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: records.length,
            itemBuilder: (context, i) {
              final r = records[i];
              return _PayrollTile(record: r, colors: colors);
            },
          );
        },
      ),
    );
  }
}

class _PayrollTile extends StatelessWidget {
  final PayrollRecord record;
  final dynamic colors;
  const _PayrollTile({required this.record, required this.colors});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (record.status) {
      PayrollStatus.processed => colors.success,
      PayrollStatus.pending => colors.warning,
      PayrollStatus.failed => colors.danger,
      PayrollStatus.partial => colors.accentSecondary,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(record.period, style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(record.status.name.toUpperCase(),
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gross', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                    Text('\$${record.grossAmount.toStringAsFixed(2)}',
                        style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (record.ewaDeducted != null && record.ewaDeducted! > 0)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('EWA Deducted', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                      Text('-\$${record.ewaDeducted!.toStringAsFixed(2)}',
                          style: TextStyle(color: colors.warning, fontSize: 13)),
                    ],
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Net', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                    Text('\$${record.netAmount.toStringAsFixed(2)}',
                        style: TextStyle(color: colors.success, fontSize: 15, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
