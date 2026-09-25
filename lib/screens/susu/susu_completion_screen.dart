// =============================================================================
// AZAMAN — Susu Completion Celebration
//
// Full-screen confetti celebration when a Susu group completes successfully.
// Shows each member's payout, total contributions, and a completion badge.
//
// Reference: Duolingo celebration, Cash App confetti, Susu completion rituals
// =============================================================================

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';

// ── Confetti Particle ──────────────────────────────────────────────────────────

class _ConfettiParticle {
  double x, y, vx, vy;
  final Color color;
  final double size;
  final double rotation;
  double rotationSpeed;

  _ConfettiParticle(this.x, this.y, this.vx, this.vy, this.color, this.size, this.rotation, this.rotationSpeed);
}

// ── Screen ────────────────────────────────────────────────────────────────────

class SusuCompletionScreen extends ConsumerStatefulWidget {
  final String groupName;
  final double totalContributed;
  final double totalPayout;
  final List<Map<String, dynamic>> members; // [{username, avatarUrl, position, receivedAmount}]
  final String currency;

  const SusuCompletionScreen({
    super.key,
    required this.groupName,
    required this.totalContributed,
    required this.totalPayout,
    required this.members,
    this.currency = 'GHS',
  });

  @override
  ConsumerState<SusuCompletionScreen> createState() => _SusuCompletionScreenState();
}

class _SusuCompletionScreenState extends ConsumerState<SusuCompletionScreen>
    with TickerProviderStateMixin {
  late AnimationController _confettiController;
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  final List<_ConfettiParticle> _particles = [];
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _confettiController = AnimationController(
      vsync: this, duration: const Duration(seconds: 4),
    )..repeat();
    _scaleController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800),
    )..forward();

    // Generate confetti particles
    final colors = [const Color(0xFFFFD700), const Color(0xFF10B981), const Color(0xFF3B97F7),
                    const Color(0xFF9C59FF), const Color(0xFFEF4444), const Color(0xFFF59E0B)];
    for (int i = 0; i < 80; i++) {
      _particles.add(_ConfettiParticle(
        _random.nextDouble() * 400,
        -_random.nextDouble() * 100,
        (_random.nextDouble() - 0.5) * 2,
        _random.nextDouble() * 3 + 1,
        colors[_random.nextInt(colors.length)],
        _random.nextDouble() * 8 + 4,
        _random.nextDouble() * 3.14,
        (_random.nextDouble() - 0.5) * 0.1,
      ));
    }

    // Heavy haptics for celebration
    AzamanHaptics.commit();
    Future.delayed(const Duration(milliseconds: 500), () => AzamanHaptics.commit());
    Future.delayed(const Duration(milliseconds: 1000), () => AzamanHaptics.confirm());
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _scaleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          // Confetti layer
          AnimatedBuilder(
            animation: _confettiController,
            builder: (context, _) {
              return CustomPaint(
                size: size,
                painter: _ConfettiPainter(_particles, _confettiController.value),
              );
            },
          ),

          // Content
          SafeArea(
            child: FadeTransition(
              opacity: _fadeController,
              child: Column(
                children: [
                  const Spacer(),
                  // Trophy badge
                  ScaleTransition(
                    scale: CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
                    child: Container(
                      width: 100, height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD700), Color(0xFFF59E0B)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                              blurRadius: 24, spreadRadius: 4),
                        ],
                      ),
                      child: const Icon(HugeIconsSolid.award01,
                          color: Colors.white, size: 48),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Title
                  Text('Susu Complete!',
                    style: TextStyle(color: colors.textPrimary, fontSize: 28, fontWeight: FontWeight.w800),
                  ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
                  const SizedBox(height: 4),
                  Text(widget.groupName,
                    style: TextStyle(color: colors.textSecondary, fontSize: 16),
                  ).animate().fadeIn(delay: 400.ms),
                  const SizedBox(height: 24),

                  // Summary card
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.border),
                    ),
                    child: Column(
                      children: [
                        _summaryRow('Total Contributed', '${widget.currency} ${widget.totalContributed.toStringAsFixed(2)}',
                            HugeIconsSolid.wallet01, colors.accent, colors),
                        const SizedBox(height: 12),
                        _summaryRow('Total Payout', '${widget.currency} ${widget.totalPayout.toStringAsFixed(2)}',
                            HugeIconsSolid.moneyReceiveFlow01, const Color(0xFF10B981), colors),
                        const SizedBox(height: 12),
                        _summaryRow('Members', '${widget.members.length}',
                            HugeIconsSolid.userGroup, const Color(0xFF9C59FF), colors),
                      ],
                    ),
                  ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.05),

                  const SizedBox(height: 24),

                  // Member payout list
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: colors.border),
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: widget.members.length,
                        separatorBuilder: (_, __) => Divider(color: colors.border, height: 1),
                        itemBuilder: (_, i) {
                          final m = widget.members[i];
                          return _MemberPayoutRow(
                            username: m['username']?.toString() ?? 'Unknown',
                            avatarUrl: m['avatarUrl']?.toString(),
                            position: m['position'] as int? ?? (i + 1),
                            amount: (m['receivedAmount'] as num?)?.toDouble() ?? 0,
                            currency: widget.currency,
                            colors: colors,
                          ).animate().fadeIn(delay: 600.ms + 100.ms * i);
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Done button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          AzamanHaptics.nav();
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.accent,
                          foregroundColor: colors.surface,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Done', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ).animate().fadeIn(delay: 700.ms),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, IconData icon, Color iconColor, AzamanColors colors) {
    return Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 14))),
        Text(value, style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ── Member Payout Row ──────────────────────────────────────────────────────────

class _MemberPayoutRow extends StatelessWidget {
  final String username;
  final String? avatarUrl;
  final int position;
  final double amount;
  final String currency;
  final AzamanColors colors;

  const _MemberPayoutRow({
    required this.username, this.avatarUrl, required this.position,
    required this.amount, required this.currency, required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: colors.softSurface,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
            child: avatarUrl == null
                ? Text(username[0].toUpperCase(), style: TextStyle(color: colors.accent))
                : null,
          ),
          Positioned(
            bottom: -2, right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: position == 1 ? const Color(0xFFFFD700) : colors.accent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.surface, width: 2),
              ),
              child: Text('#$position', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      title: Text(username, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)),
      trailing: Text('$currency ${amount.toStringAsFixed(2)}',
          style: TextStyle(color: colors.success, fontWeight: FontWeight.w700, fontSize: 14)),
    );
  }
}

// ── Confetti Painter ──────────────────────────────────────────────────────────

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter(this.particles, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final x = (p.x + p.vx * progress * 200) % size.width;
      final y = (p.y + p.vy * progress * 400) % size.height;
      final rotation = p.rotation + p.rotationSpeed * progress * 200;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      final paint = Paint()..color = p.color;
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_) => true;
}
