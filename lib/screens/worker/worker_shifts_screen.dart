import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/worker_provider.dart';
import 'package:azaman/models/employee_models.dart';

class WorkerShiftsScreen extends ConsumerWidget {
  const WorkerShiftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final shiftsAsync = ref.watch(myShiftsProvider);

    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        title: Text('My Shifts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: shiftsAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
        error: (_, __) => Center(child: Text('Unable to load shifts', style: TextStyle(color: colors.textSecondary))),
        data: (shifts) {
          if (shifts.isEmpty) {
            return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_busy, size: 48, color: colors.textTertiary),
                const SizedBox(height: 12),
                Text('No shifts scheduled', style: TextStyle(color: colors.textSecondary, fontSize: 15)),
              ],
            ));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: shifts.length,
            itemBuilder: (context, i) {
              final shift = shifts[i];
              return _ShiftTile(shift: shift, colors: colors);
            },
          );
        },
      ),
    );
  }
}

class _ShiftTile extends StatelessWidget {
  final Shift shift;
  final dynamic colors;
  const _ShiftTile({required this.shift, required this.colors});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (shift.status) {
      ShiftStatus.clockedIn => colors.success,
      ShiftStatus.clockedOut => colors.textSecondary,
      ShiftStatus.late => colors.warning,
      ShiftStatus.noShow => colors.danger,
      ShiftStatus.scheduled => colors.accent,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.schedule, color: statusColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_fmtDate(shift.shiftDate)} · ${_fmtTime(shift.startTime)} - ${_fmtTime(shift.endTime)}',
                    style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                if (shift.shiftLabel != null)
                  Text(shift.shiftLabel!, style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                Text('${shift.durationHours.toStringAsFixed(1)}h${shift.breakMinutes != null ? ' · ${shift.breakMinutes}min break' : ''}',
                    style: TextStyle(color: colors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(shift.status.name.toUpperCase(),
                style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  String _fmtDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}
