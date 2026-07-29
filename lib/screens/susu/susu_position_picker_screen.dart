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
import 'package:azaman/utils/azaman_haptics.dart';

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

class _SusuPositionPickerState extends ConsumerState<SusuPositionPicker>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  int? _hoveredPosition;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final size = MediaQuery.of(context).size.width * 0.82;
    final center = size / 2;
    final radius = size / 2 - 30;

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
            // Circular picker
            Center(
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  children: [
                    // Center circle
                    Positioned(
                      left: center - 40,
                      top: center - 40,
                      child: Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.surface,
                          border: Border.all(color: colors.accent, width: 2),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(HugeIconsSolid.touchInteraction01, color: colors.accent, size: 24),
                              const SizedBox(height: 2),
                              Text('Pick', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ).animate().fadeIn().scale(),
                    // Position dots
                    ...List.generate(widget.totalPositions, (i) {
                      final angle = (2 * 3.14159 * i / widget.totalPositions) - 3.14159 / 2;
                      final x = center + radius * _cos(angle);
                      final y = center + radius * _sin(angle);
                      final isTaken = widget.members.any((m) => (m['position'] as int?) == i + 1);
                      final isSelected = widget.selectedPosition == i + 1;
                      final isHovered = _hoveredPosition == i + 1;
                      final member = widget.members.cast<Map<String, dynamic>?>().firstWhere(
                        (m) => (m?['position'] as int?) == i + 1,
                        orElse: () => null,
                      );

                      return Positioned(
                        left: x - 28,
                        top: y - 28,
                        child: GestureDetector(
                          onTap: isTaken ? null : () {
                            AzamanHaptics.confirm();
                            widget.onPositionSelected(i + 1);
                          },
                          onTapDown: isTaken ? null : (_) {
                            setState(() => _hoveredPosition = i + 1);
                          },
                          onTapCancel: () => setState(() => _hoveredPosition = null),
                          onTapUp: (_) => setState(() => _hoveredPosition = null),
                          child: _PositionDot(
                            position: i + 1,
                            isTaken: isTaken,
                            isSelected: isSelected,
                            isHovered: isHovered,
                            member: member,
                            colors: colors,
                            pulseAnimation: _pulseController,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
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

  double _cos(double angle) => _mathCos(angle);
  double _sin(double angle) => _mathSin(angle);
}

// ── Position Dot ──────────────────────────────────────────────────────────────

class _PositionDot extends StatelessWidget {
  final int position;
  final bool isTaken;
  final bool isSelected;
  final bool isHovered;
  final Map<String, dynamic>? member;
  final AzamanColors colors;
  final Animation<double> pulseAnimation;

  const _PositionDot({
    required this.position,
    required this.isTaken,
    required this.isSelected,
    required this.isHovered,
    this.member,
    required this.colors,
    required this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final Color dotColor;
    if (isSelected) {
      dotColor = colors.accent;
    } else if (isTaken) {
      dotColor = colors.success;
    } else {
      dotColor = colors.textTertiary.withValues(alpha: 0.4);
    }

    final dotSize = isSelected || isHovered ? 56.0 : 48.0;

    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        final scale = isSelected ? 1.0 + 0.05 * (0.5 - (pulseAnimation.value - 0.5).abs()) : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        width: dotSize, height: dotSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dotColor,
          border: Border.all(
            color: isSelected ? colors.accent : colors.border,
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(color: colors.accent.withValues(alpha: 0.4), blurRadius: 12, spreadRadius: 2),
          ] : null,
        ),
        child: Stack(
          children: [
            // Position number
            Center(
              child: Text(
                '$position',
                style: TextStyle(
                  color: isTaken || isSelected ? Colors.white : colors.textTertiary,
                  fontSize: 18, fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // Member avatar (if taken)
            if (isTaken && member != null)
              Positioned(
                right: 0, bottom: 0,
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.surface,
                    border: Border.all(color: colors.border, width: 1.5),
                  ),
                  child: member!['avatarUrl'] != null
                      ? ClipOval(child: Image.network(member!['avatarUrl'], fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _initials()))
                      : _initials(),
                ),
              ),
            // Crown for position 1
            if (position == 1)
              const Positioned(
                top: -8, left: 0, right: 0,
                child: Icon(HugeIconsSolid.crown02, size: 16, color: Color(0xFFFFD700)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _initials() {
    final name = member?['username']?.toString() ?? '?';
    return Center(child: Text(name[0].toUpperCase(),
        style: TextStyle(color: colors.textTertiary, fontSize: 10, fontWeight: FontWeight.w600)));
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

// ── Math helpers ────────────────────────────────────────────────────────────────
double _mathCos(double angle) {
  double x = 1.0;
  for (int i = 0; i < 6; i++) {
    x -= (angle * angle) / (2 * i + 2) / (2 * i + 1) * (i % 2 == 0 ? 1 : -1);
  }
  // Simpler: use dart:math
  return _dartCos(angle);
}

double _mathSin(double angle) {
  return _dartSin(angle);
}

double _dartCos(double angle) {
  // Normalize angle to 0..2PI
  double a = angle;
  while (a < 0) {
    a += 2 * 3.141592653589793;
  }
  while (a >= 2 * 3.141592653589793) {
    a -= 2 * 3.141592653589793;
  }
  // Use Taylor series
  double result = 1.0;
  double term = 1.0;
  for (int i = 1; i <= 10; i++) {
    term *= -angle * angle / ((2 * i) * (2 * i - 1));
    result += term;
  }
  return result;
}

double _dartSin(double angle) {
  // sin(x) = cos(x - PI/2)
  return _dartCos(angle - 3.141592653589793 / 2);
}
