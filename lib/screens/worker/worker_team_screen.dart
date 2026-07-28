import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/worker_provider.dart';
import 'package:azaman/models/employee_models.dart';

class WorkerTeamScreen extends ConsumerWidget {
  const WorkerTeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final dashAsync = ref.watch(workerDashboardProvider);

    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        title: Text('Team', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: dashAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
        error: (_, __) => Center(child: Text('Unable to load team', style: TextStyle(color: colors.textSecondary))),
        data: (dash) {
          if (dash == null) return const SizedBox.shrink();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (dash.teamOnDuty.isNotEmpty) ...[
                Text('On Duty Now', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                ...dash.teamOnDuty.map((m) => _TeamTile(member: m, isOnDuty: true, colors: colors)),
              ],
              if (dash.upcomingTeam != null) ...[
                const SizedBox(height: 24),
                Text('Next Up', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                _TeamTile(member: dash.upcomingTeam!, isOnDuty: false, colors: colors),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TeamTile extends StatelessWidget {
  final TeamMember member;
  final bool isOnDuty;
  final dynamic colors;
  const _TeamTile({required this.member, required this.isOnDuty, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: (isOnDuty ? colors.success : colors.accent).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Text(member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                style: TextStyle(color: isOnDuty ? colors.success : colors.accent, fontSize: 14, fontWeight: FontWeight.w700))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name, style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                Text(member.role.name, style: TextStyle(color: colors.textTertiary, fontSize: 12)),
              ],
            ),
          ),
          if (isOnDuty)
            Container(width: 8, height: 8, decoration: BoxDecoration(color: colors.success, shape: BoxShape.circle)),
        ],
      ),
    );
  }
}
