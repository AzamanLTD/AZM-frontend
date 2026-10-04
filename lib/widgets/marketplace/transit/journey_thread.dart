/// Journey thread (Overhaul 03 §5.1).
///
/// A thin route line that persists across trip list → seat selection →
/// booking → boarding pass, changing *state* only. UI-only: each screen
/// derives the model from the authoritative objects it already holds (trip,
/// hold, pass); the thread is never read back to make a decision.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';

enum JourneyStage { search, trip, seat, booking, boarded }

class JourneyThreadModel {
  final String? fromLabel;
  final String? toLabel;
  final DateTime? departAt;
  final String? seatLabel;
  final JourneyStage stage;

  const JourneyThreadModel({
    this.fromLabel,
    this.toLabel,
    this.departAt,
    this.seatLabel,
    required this.stage,
  });

  /// 0 at `search`, 1 at `boarded`.
  double get progress =>
      JourneyStage.values.indexOf(stage) / (JourneyStage.values.length - 1);

  factory JourneyThreadModel.searching({String? operatorName}) =>
      JourneyThreadModel(fromLabel: operatorName, toLabel: 'Where to?', stage: JourneyStage.search);

  factory JourneyThreadModel.fromTrip(
    TransitTrip trip, {
    JourneyStage stage = JourneyStage.trip,
    String? seatLabel,
  }) =>
      JourneyThreadModel(
        fromLabel: trip.origin,
        toLabel: trip.destination,
        departAt: trip.departureAt,
        seatLabel: seatLabel,
        stage: stage,
      );

  JourneyThreadModel copyWith({JourneyStage? stage, String? seatLabel}) =>
      JourneyThreadModel(
        fromLabel: fromLabel,
        toLabel: toLabel,
        departAt: departAt,
        seatLabel: seatLabel ?? this.seatLabel,
        stage: stage ?? this.stage,
      );

  @override
  bool operator ==(Object other) =>
      other is JourneyThreadModel &&
      other.fromLabel == fromLabel &&
      other.toLabel == toLabel &&
      other.departAt == departAt &&
      other.seatLabel == seatLabel &&
      other.stage == stage;

  @override
  int get hashCode => Object.hash(fromLabel, toLabel, departAt, seatLabel, stage);
}

/// Joins seat ids into the label shown on the thread ("12A · 12B").
String? journeySeatLabel(Iterable<String> seatIds) {
  final list = seatIds.toList();
  if (list.isEmpty) return null;
  return list.join(' · ');
}

/// Shared across the transit screens so the thread keeps its state while the
/// user moves between them. Never persisted.
final journeyThreadProvider =
    StateProvider.autoDispose<JourneyThreadModel?>((_) => null);

class JourneyThread extends ConsumerWidget {
  final JourneyThreadModel model;

  const JourneyThread({super.key, required this.model});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final travel = AzMotion.of(context).travel;
    return RepaintBoundary(
      child: SizedBox(
        key: ValueKey('journey_thread_${model.stage.name}'),
        height: 44,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: model.progress),
          duration: travel ? MotionTokens.standard : Duration.zero,
          curve: MotionTokens.enter,
          builder: (context, progress, child) => CustomPaint(
            painter: _ThreadPainter(
              progress: progress,
              color: colors.accent,
              track: colors.softSurface,
            ),
            child: child,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AzSpace.xl),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    model.fromLabel ?? '—',
                    style: AzText.label.copyWith(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, size: 14, color: colors.textTertiary),
                Expanded(
                  child: Text(
                    model.toLabel ?? '—',
                    textAlign: TextAlign.end,
                    style: AzText.label.copyWith(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (model.seatLabel != null) ...[
                  const SizedBox(width: AzSpace.sm),
                  Text(
                    'Seat ${model.seatLabel}',
                    style: AzText.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThreadPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;

  const _ThreadPainter({required this.progress, required this.color, required this.track});

  @override
  void paint(Canvas c, Size s) {
    final y = s.height - 4;
    final p = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    c.drawLine(Offset(AzSpace.xl, y), Offset(s.width - AzSpace.xl, y), p..color = track);
    final span = s.width - 2 * AzSpace.xl;
    if (progress > 0) {
      c.drawLine(Offset(AzSpace.xl, y), Offset(AzSpace.xl + span * progress, y), p..color = color);
    }
  }

  @override
  bool shouldRepaint(_ThreadPainter o) =>
      o.progress != progress || o.color != color || o.track != track;
}