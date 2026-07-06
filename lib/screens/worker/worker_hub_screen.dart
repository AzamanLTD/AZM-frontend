// =============================================================================
// WORKER HUB SCREEN — Entry point for the Employee Sub-Portal
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/worker_provider.dart';
import 'package:azaman/models/employee_models.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class WorkerHubScreen extends ConsumerWidget {
  const WorkerHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final dashAsync = ref.watch(workerDashboardProvider);

    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        title: Text(
          dashAsync.valueOrNull?.employee?.businessName ?? 'Workplace',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: dashAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
        error: (_, __) => Center(
          child: Text('Unable to load dashboard',
              style: TextStyle(color: colors.textSecondary)),
        ),
        data: (dash) {
          if (dash == null || dash.employee == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.work_off, size: 48, color: colors.textTertiary),
                  const SizedBox(height: 12),
                  Text('You are not an active employee',
                      style: TextStyle(color: colors.textSecondary, fontSize: 15)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(workerDashboardProvider),
            color: colors.accent,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SalaryCountdownCard(dash: dash, colors: colors),
                const SizedBox(height: 16),
                if (dash.currentShift != null)
                  _ActiveShiftCard(shift: dash.currentShift!, colors: colors)
                else if (dash.nextShift != null)
                  _NextShiftCard(shift: dash.nextShift!, colors: colors),
                const SizedBox(height: 16),
                _EwaCard(dash: dash, colors: colors),
                const SizedBox(height: 16),
                _QuickActionsGrid(colors: colors),
                const SizedBox(height: 16),
                if (dash.teamOnDuty.isNotEmpty)
                  _TeamOnDutyCard(dash: dash, colors: colors),
                if (dash.recentFeedback.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _FeedbackCard(dash: dash, colors: colors),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SalaryCountdownCard extends StatelessWidget {
  final WorkerDashboard dash;
  final dynamic colors;
  const _SalaryCountdownCard({required this.dash, required this.colors});

  @override
  Widget build(BuildContext context) {
    final salary = dash.salaryInfo;
    if (salary == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.accent.withOpacity(0.15), colors.accent.withOpacity(0.03)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.accent.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Salary Countdown', style: TextStyle(
            color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${salary.netAccrued.toStringAsFixed(2)}',
                style: TextStyle(
                  color: colors.textPrimary, fontSize: 32, fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 6),
                child: Text('accrued', style: TextStyle(color: colors.textTertiary, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (salary.monthlySalary != null)
            Text('of \$${salary.monthlySalary!.toStringAsFixed(0)}/mo',
                style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 14, color: colors.accent),
              const SizedBox(width: 6),
              Text('${salary.daysUntilPayday} days until payday',
                  style: TextStyle(color: colors.accent, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _NextShiftCard extends StatelessWidget {
  final Shift shift;
  final dynamic colors;
  const _NextShiftCard({required this.shift, required this.colors});

  @override
  Widget build(BuildContext context) {
    final timeStr = '${_fmtTime(shift.startTime)} - ${_fmtTime(shift.endTime)}';
    final dateStr = _fmtDate(shift.shiftDate);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: colors.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.schedule, color: colors.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Next Shift', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                Text(dateStr, style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                Text(timeStr, style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                if (shift.shiftLabel != null)
                  Text(shift.shiftLabel!, style: TextStyle(color: colors.accent, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveShiftCard extends StatelessWidget {
  final Shift shift;
  final dynamic colors;
  const _ActiveShiftCard({required this.shift, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.success.withOpacity(0.08), borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.success.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: colors.success.withOpacity(0.15), borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.play_arrow, color: colors.success, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CLOCKED IN', style: TextStyle(color: colors.success, fontSize: 11, fontWeight: FontWeight.w700)),
                Text('Since ${_fmtTime(shift.startTime)}',
                    style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => AzamanHaptics.toggle(),
            child: Text('Clock Out', style: TextStyle(color: colors.success, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _EwaCard extends StatelessWidget {
  final WorkerDashboard dash;
  final dynamic colors;
  const _EwaCard({required this.dash, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: colors.accentSecondary.withOpacity(0.1), borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.bolt, color: colors.accentSecondary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('EWA Available', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                Text('\$${dash.ewaAvailable.toStringAsFixed(2)}',
                    style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (dash.ewaAvailable > 0)
            TextButton(
              onPressed: () {
                AzamanHaptics.toggle();
                context.push('/worker/ewa');
              },
              child: Text('Withdraw', style: TextStyle(color: colors.accent, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  final dynamic colors;
  const _QuickActionsGrid({required this.colors});

  @override
  Widget build(BuildContext context) {
    final actions = [
      ('My Shifts', Icons.calendar_month, '/worker/shifts'),
      ('Payroll', Icons.payments, '/worker/payroll'),
      ('Team', Icons.groups, '/worker/team'),
      ('Time Off', Icons.beach_access, '/worker/time-off'),
      ('Feedback', Icons.rate_review, '/worker/feedback'),
      ('Open Swaps', Icons.swap_horiz, '/worker/swaps'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 1.0, crossAxisSpacing: 10, mainAxisSpacing: 10,
      ),
      itemCount: actions.length,
      itemBuilder: (context, i) {
        final (label, icon, route) = actions[i];
        return GestureDetector(
          onTap: () {
            AzamanHaptics.toggle();
            context.push(route);
          },
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border, width: 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: colors.accent, size: 24),
                const SizedBox(height: 6),
                Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TeamOnDutyCard extends StatelessWidget {
  final WorkerDashboard dash;
  final dynamic colors;
  const _TeamOnDutyCard({required this.dash, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: colors.success, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('On Duty Now', style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          ...dash.teamOnDuty.map((m) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: colors.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Center(child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                      style: TextStyle(color: colors.accent, fontSize: 12, fontWeight: FontWeight.w700))),
                ),
                const SizedBox(width: 10),
                Text(m.name, style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
                const Spacer(),
                if (m.shiftLabel != null)
                  Text(m.shiftLabel!, style: TextStyle(color: colors.textTertiary, fontSize: 11)),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final WorkerDashboard dash;
  final dynamic colors;
  const _FeedbackCard({required this.dash, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent Feedback', style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...dash.recentFeedback.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Row(children: List.generate(5, (i) => Icon(
                  i < f.rating ? Icons.star : Icons.star_border,
                  size: 14, color: Colors.amber))),
                const SizedBox(width: 8),
                Expanded(child: Text(f.giverName ?? 'Anonymous',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12))),
                if (f.comment != null)
                  Text(f.comment!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textTertiary, fontSize: 11)),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

String _fmtTime(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
String _fmtDate(DateTime dt) {
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${months[dt.month - 1]} ${dt.day}';
}
