// =============================================================================
// AZAMAN — Animated QR Code (Dust Variant)
//
// A QR code that ARRIVES rather than appears. Each dark module is subdivided
// into an 8×8 grid of particles that fly in from the bottom of the stage
// and tighten into a solid module as they land. Per-particle canvas
// rendering — no DOM elements, no SVG filters.
//
// Architecture:
//   • ONE AnimationController running forward (entrance). Reverse = exit.
//   • Each mark's flight is 620ms; first and last start 700ms apart → 1320ms total.
//   • Easing: 1 - (1-t)^5  (numeric twin of cubic-bezier(0.23, 1, 0.32, 1))
//   • Marks ordered by distance from the launch point (bottom centre) so
//     nearest cells land first and the code grows up and out.
//   • Each particle carries its module's offset PLUS its own scatter that
//     goes to zero as it lands — a cloud that tightens into a solid square.
//   • prefers-reduced-motion: drop travel + scatter, keep 200ms opacity fade.
//   • dpr-aware backing store; scale transform set ONCE, never setTransform.
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

class AnimatedQrDust extends StatefulWidget {
  final String data;
  final double size;
  final Color inkColor;
  final Color backgroundColor;
  final int errorCorrectLevel;
  final int dustGrid; // subdivision per module (8 = 8×8 particles per dark module)

  const AnimatedQrDust({
    super.key,
    required this.data,
    this.size = 240,
    this.inkColor = const Color(0xFF141416),
    this.backgroundColor = const Color(0xFFFCFCFC),
    this.errorCorrectLevel = QrErrorCorrectLevel.M,
    this.dustGrid = 3,
  });

  @override
  State<AnimatedQrDust> createState() => _AnimatedQrDustState();
}

class _AnimatedQrDustState extends State<AnimatedQrDust>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;
  late final int _moduleCount;
  late final double _moduleSize;
  late final double _stageSize;
  late final bool _reducedMotion;

  // Timing constants (from the spec)
  static const double _flightMs = 620.0;
  static const double _spreadMs = 700.0; // first to last mark start
  static const double _totalMs = _flightMs + _spreadMs; // 1320ms

  @override
  void initState() {
    super.initState();

    _reducedMotion = WidgetsBinding.instance.platformDispatcher
        .accessibilityFeatures
        .reduceMotion;

    // Generate QR matrix
    final qrCode = QrCode.fromData(
      data: widget.data,
      errorCorrectLevel: widget.errorCorrectLevel,
    );
    final qrImage = QrImage(qrCode);
    _moduleCount = qrImage.moduleCount;

    // Stage is larger than the code so marks have somewhere to come from.
    // Code = moduleCount * modulePx; stage = code + 40% padding.
    _moduleSize = widget.size / _moduleCount;
    _stageSize = widget.size * 1.38; // ~38% larger stage

    // Build particle list
    _particles = _buildParticles(qrImage);

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _reducedMotion ? 200 : _totalMs.round()),
    );

    // Auto-play on init (every open)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward(from: 0);
    });
  }

  List<_Particle> _buildParticles(QrImage qrImage) {
    final particles = <_Particle>[];
    final launchX = _stageSize / 2;
    final launchY = _stageSize + 20; // below the stage

    final codeOffset = (_stageSize - widget.size) / 2;
    final dustTile = _moduleSize / widget.dustGrid;

    for (int row = 0; row < _moduleCount; row++) {
      for (int col = 0; col < _moduleCount; col++) {
        if (!qrImage.isDark(row, col)) continue;

        // Module's target centre in stage coordinates
        final moduleX = codeOffset + col * _moduleSize;
        final moduleY = codeOffset + row * _moduleSize;

        // Distance from launch point — orders the start times
        final dx = moduleX + _moduleSize / 2 - launchX;
        final dy = moduleY + _moduleSize / 2 - launchY;
        final dist = math.sqrt(dx * dx + dy * dy);

        // Per-particle: 8×8 grid within the module
        for (int py = 0; py < widget.dustGrid; py++) {
          for (int px = 0; px < widget.dustGrid; px++) {
            // Target position within the module
            final targetX = moduleX + px * dustTile;
            final targetY = moduleY + py * dustTile;

            // Scatter offset (random, goes to zero on landing)
            final scatterR = dustTile * 0.8;
            final scatterAngle = _hashAngle(row, col, px, py);
            final scatterRadius = scatterR * _hashRadius(row, col, px, py);
            final scatterX = math.cos(scatterAngle) * scatterRadius;
            final scatterY = math.sin(scatterAngle) * scatterRadius;

            // Launch position: bottom of the stage + module offset + scatter
            final startX = launchX + (moduleX + _moduleSize / 2 - launchX) * 0.3 + scatterX;
            final startY = launchY;

            particles.add(_Particle(
              startX: startX,
              startY: startY,
              targetX: targetX,
              targetY: targetY,
              scatterX: scatterX,
              scatterY: scatterY,
              tile: dustTile,
              dist: dist,
            ));
          }
        }
      }
    }

    // Sort by distance so nearest cells land first
    particles.sort((a, b) => a.dist.compareTo(b.dist));

    // Normalize distances to start-time offsets (0 to _spreadMs)
    if (particles.isNotEmpty) {
      final minDist = particles.first.dist;
      final maxDist = particles.last.dist;
      final range = (maxDist - minDist).clamp(1.0, double.infinity);
      for (final p in particles) {
        p.startMs = ((p.dist - minDist) / range) * _spreadMs;
      }
    }

    return particles;
  }

  // Deterministic hash → angle [0, 2π)
  double _hashAngle(int r, int c, int px, int py) {
    final h = (r * 73 + c * 37 + px * 19 + py * 11) & 0xFFFF;
    return (h / 0xFFFF) * 2 * math.pi;
  }

  // Deterministic hash → radius [0, 1)
  double _hashRadius(int r, int c, int px, int py) {
    final h = (r * 41 + c * 29 + px * 67 + py * 53) & 0xFFFF;
    return h / 0xFFFF;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _DustPainter(
              particles: _particles,
              progress: _controller.value,
              inkColor: widget.inkColor,
              backgroundColor: widget.backgroundColor,
              stageSize: _stageSize,
              codeSize: widget.size,
              reducedMotion: _reducedMotion,
              dpr: dpr,
            ),
          );
        },
      ),
    );
  }
}

class _Particle {
  final double startX, startY;
  final double targetX, targetY;
  final double scatterX, scatterY;
  final double tile;
  final double dist;
  double startMs = 0;

  _Particle({
    required this.startX,
    required this.startY,
    required this.targetX,
    required this.targetY,
    required this.scatterX,
    required this.scatterY,
    required this.tile,
    required this.dist,
  });
}

class _DustPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress; // 0..1 over totalMs
  final Color inkColor;
  final Color backgroundColor;
  final double stageSize;
  final double codeSize;
  final bool reducedMotion;
  final double dpr;

  _DustPainter({
    required this.particles,
    required this.progress,
    required this.inkColor,
    required this.backgroundColor,
    required this.stageSize,
    required this.codeSize,
    required this.reducedMotion,
    required this.dpr,
  });

  static const double _flightMs = 620.0;
  static const double _totalMs = 1320.0;

  // Easing: 1 - (1-t)^5
  double _ease(double t) => 1 - math.pow(1 - t.clamp(0.0, 1.0), 5).toDouble();

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    if (reducedMotion) {
      // Reduced motion: 200ms opacity fade, no travel
      final opacity = (progress / 0.15).clamp(0.0, 1.0);
      final inkPaint = Paint()
        ..color = inkColor.withValues(alpha: opacity)
        ..isAntiAlias = true;

      // Map stage coordinates to canvas coordinates
      final scale = size.width / stageSize;
      canvas.save();
      canvas.scale(scale, scale);

      for (final p in particles) {
        canvas.drawRect(
          Rect.fromLTWH(p.targetX, p.targetY, p.tile, p.tile),
          inkPaint,
        );
      }
      canvas.restore();
      return;
    }

    // Normal animation
    final currentMs = progress * _totalMs;
    final inkPaint = Paint()
      ..color = inkColor
      ..isAntiAlias = true;

    // Scale: stage → canvas
    final scale = size.width / stageSize;
    canvas.save();
    canvas.scale(scale, scale);

    for (final p in particles) {
      final localMs = currentMs - p.startMs;
      if (localMs <= 0) continue; // not started yet

      final t = (localMs / _flightMs).clamp(0.0, 1.0);
      final eased = _ease(t);

      if (t >= 1.0) {
        // Landed — solid tile, no scatter
        canvas.drawRect(
          Rect.fromLTWH(p.targetX, p.targetY, p.tile, p.tile),
          inkPaint,
        );
      } else {
        // In flight: interpolate position with scatter fading out
        final scatterFactor = 1 - eased;
        final x = p.startX + (p.targetX - p.startX) * eased + p.scatterX * scatterFactor;
        final y = p.startY + (p.targetY - p.startY) * eased + p.scatterY * scatterFactor;
        canvas.drawRect(
          Rect.fromLTWH(x, y, p.tile, p.tile),
          inkPaint,
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DustPainter old) {
    return old.progress != progress;
  }
}
