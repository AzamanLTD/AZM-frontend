import 'package:flutter/material.dart';
import 'dart:math';

class SuccessCelebration extends StatefulWidget {
  final VoidCallback? onComplete;
  final Widget child;

  const SuccessCelebration({
    super.key,
    this.onComplete,
    required this.child,
  });

  @override
  State<SuccessCelebration> createState() => _SuccessCelebrationState();
}

class _SuccessCelebrationState extends State<SuccessCelebration>
    with TickerProviderStateMixin {
  late AnimationController _confettiController;
  late AnimationController _scaleController;
  final List<_Particle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Generate particles
    for (int i = 0; i < 40; i++) {
      _particles.add(_Particle(
        x: _random.nextDouble(),
        y: _random.nextDouble() * 0.3,
        color: [
          const Color(0xFFD4AF37),
          const Color(0xFF02C076),
          const Color(0xFF00E5FF),
          const Color(0xFFBB86FC),
          const Color(0xFFF0B90B),
        ][_random.nextInt(5)],
        size: _random.nextDouble() * 8 + 4,
        velocity: _random.nextDouble() * 2 + 1,
        angle: _random.nextDouble() * pi * 2,
      ));
    }

    _scaleController.forward();
    _confettiController.forward().then((_) {
      widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Child content with scale animation
        Center(
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: _scaleController,
              curve: Curves.elasticOut,
            ),
            child: widget.child,
          ),
        ),
        // Confetti overlay
        AnimatedBuilder(
          animation: _confettiController,
          builder: (context, _) {
            return CustomPaint(
              size: MediaQuery.of(context).size,
              painter: _ConfettiPainter(
                particles: _particles,
                progress: _confettiController.value,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Particle {
  double x;
  double y;
  Color color;
  double size;
  double velocity;
  double angle;

  _Particle({
    required this.x,
    required this.y,
    required this.color,
    required this.size,
    required this.velocity,
    required this.angle,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = p.color.withValues(alpha: (1 - progress).clamp(0, 1))
        ..style = PaintingStyle.fill;

      final x = p.x * size.width + cos(p.angle) * progress * p.velocity * 100;
      final y = p.y * size.height + progress * p.velocity * size.height * 0.7;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(progress * p.angle * 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
          Radius.circular(p.size * 0.2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
