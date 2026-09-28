// =============================================================================
// AZAMAN — Susu Position Picker
//
// Visual circular position picker for Susu groups. Users select their desired
// payout position in the rotation. Shows who's in each position.
//
// Reference: Susu rotation visualization, Tanda position selection
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/susu/susu_wheel.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class SusuPositionPicker extends ConsumerStatefulWidget {
  final int totalPositions;
  final int? selectedPosition;
  final List<Map<String, dynamic>> members; // [{position, username, avatarUrl, paid}]
  final ValueChanged<int> onPositionSelected;

  const SusuPositionPicker({
    super.key,
    required this.totalPositions,
    this.selectedPosition,
    required this.members,
    required this.onPositionSelected,
  });

  @override
  ConsumerState<SusuPositionPicker> createState() => _SusuPositionPickerState();
}

class _SusuPositionPickerState extends ConsumerState<SusuPositionPicker> {
  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text('Choose Your Position', style: TextStyle(color: colors.textPrimary)),
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Center(
              child: SusuPositionWheel(
                totalPositions: widget.totalPositions,
                selectedPosition: widget.selectedPosition,
                members: widget.members,
                onPositionSelected: widget.onPositionSelected,
              ),
            ),
            const SizedBox(height: 16),
            // Legend
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legendDot(colors.accent, 'Selected'),
                  const SizedBox(width: 16),
                  _legendDot(colors.success, 'Taken'),
                  const SizedBox(width: 16),
                  _legendDot(colors.textTertiary, 'Available'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Members list
            if (widget.members.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Current Members',
                      style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
              ...widget.members.map((m) => _MemberRow(
                position: m['position'] as int,
                username: m['username']?.toString() ?? 'Unknown',
                avatarUrl: m['avatarUrl']?.toString(),
                paid: m['paid'] == true,
                colors: colors,
              ).animate().fadeIn().slideX(begin: -0.05)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: ref.read(themeProvider).colors.textTertiary, fontSize: 12)),
      ],
    );
  }
}

// ── Member Row ──────────────────────────────────────────────────────────────────

class _MemberRow extends StatelessWidget {
  final int position;
  final String username;
  final String? avatarUrl;
  final bool paid;
  final AzamanColors colors;

  const _MemberRow({
    required this.position, required this.username, this.avatarUrl,
    required this.paid, required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: colors.softSurface,
        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
        child: avatarUrl == null
            ? Text(username[0].toUpperCase(), style: TextStyle(color: colors.accent))
            : null,
      ),
      title: Text(username, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500)),
      subtitle: Text('Position #$position', style: TextStyle(color: colors.textTertiary, fontSize: 12)),
      trailing: paid
          ? Icon(HugeIconsSolid.checkmarkBadge02, color: colors.success, size: 24)
          : Icon(HugeIconsSolid.time02, color: colors.textTertiary, size: 22),
    );
  }
}
