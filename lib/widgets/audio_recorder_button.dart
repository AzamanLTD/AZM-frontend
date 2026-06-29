// =============================================================================
// AUDIO RECORDER BUTTON — Phase UI-POLISH (2026-05-26)
//
// WhatsApp-style hold-to-record voice note button.
//
// Behaviour:
//   • Idle           : circular mic button.
//   • Long-press     : haptic, recording starts, the input bar's content
//                      morphs into a recording strip (red dot + elapsed
//                      time + slide-to-cancel hint).
//   • Slide left     : visual indicator turns red; releasing past the
//                      threshold cancels the recording.
//   • Release short  : recordings under ~700ms count as accidental taps
//                      and are discarded.
//   • Release long   : stops recording, calls `onRecorded(file, duration,
//                      waveformPeaks)`. Caller is responsible for the
//                      upload + sendMessage roundtrip.
//
// Sampling:
//   The `record` package's onAmplitudeChanged stream gives normalised
//   amplitude every 200ms; we sample down to 50 buckets max so the
//   payload matches the BE waveformPeaks contract from Phase UI-3.
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:hugeicons_pro/hugeicons.dart';

/// Callback fired when a successful recording finishes. The file is on
/// the local filesystem; the caller uploads it via
/// `ChatMediaService.uploadAudio()` and includes the resulting URL +
/// duration + waveform peaks in their `sendMessage` body.
typedef OnAudioRecorded = void Function(
  File file,
  int durationSeconds,
  List<int> waveformPeaks,
);

class AudioRecorderButton extends ConsumerStatefulWidget {
  final OnAudioRecorded onRecorded;

  /// When true the button is disabled (e.g. while another upload is in
  /// progress). Held state is also released.
  final bool disabled;

  /// Used as the visual size of the mic button. The recording strip
  /// width is independent.
  final double size;

  const AudioRecorderButton({
    super.key,
    required this.onRecorded,
    this.disabled = false,
    this.size = 36,
  });

  @override
  ConsumerState<AudioRecorderButton> createState() =>
      _AudioRecorderButtonState();
}

class _AudioRecorderButtonState extends ConsumerState<AudioRecorderButton> {
  final AudioRecorder _recorder = AudioRecorder();

  // State machine
  bool _recording = false;
  bool _cancelling = false;
  Duration _elapsed = Duration.zero;
  DateTime? _startedAt;
  String? _filePath;

  // Sampling
  final List<int> _peaks = <int>[];
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _tickTimer;

  // Drag tracking
  Offset _dragOrigin = Offset.zero;
  double _dragDx = 0;
  static const double _cancelThresholdDx = -80;

  @override
  void dispose() {
    _ampSub?.cancel();
    _tickTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<bool> _ensurePermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  Future<void> _startRecording() async {
    if (widget.disabled) return;
    if (!await _ensurePermission()) {
      if (!mounted) return;
      AzamanHaptics.warn();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission required')),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final filename =
        'voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
    final path = p.join(dir.path, filename);

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
        ),
        path: path,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start recording: $e')),
      );
      return;
    }

    AzamanHaptics.confirm();
    if (!mounted) return;
    setState(() {
      _recording = true;
      _cancelling = false;
      _peaks.clear();
      _filePath = path;
      _startedAt = DateTime.now();
      _elapsed = Duration.zero;
      _dragDx = 0;
    });

    _tickTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || !_recording) return;
      setState(() {
        _elapsed = DateTime.now().difference(_startedAt!);
      });
    });

    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 200))
        .listen((amp) {
      // amp.current is in dBFS, typically -160..0. Normalise to 0..100.
      final db = amp.current.isFinite ? amp.current : -60.0;
      final pct = ((db + 60) / 60 * 100).clamp(0, 100).round();
      if (_peaks.length >= 50) {
        // Keep the most recent 50 buckets so longer notes still produce
        // a meaningful waveform without exploding the JSON payload.
        _peaks.removeAt(0);
      }
      _peaks.add(pct);
    });
  }

  Future<void> _stopAndCommit() async {
    if (!_recording) return;
    _ampSub?.cancel();
    _tickTimer?.cancel();
    String? finalPath;
    try {
      finalPath = await _recorder.stop();
    } catch (_) {
      finalPath = _filePath;
    }
    final duration = _elapsed;
    final cancelled = _cancelling;
    final peaksSnapshot = List<int>.from(_peaks);

    if (mounted) {
      setState(() {
        _recording = false;
        _cancelling = false;
        _elapsed = Duration.zero;
        _peaks.clear();
        _filePath = null;
        _startedAt = null;
        _dragDx = 0;
      });
    }

    if (cancelled || finalPath == null) {
      _safeDelete(finalPath);
      AzamanHaptics.warn();
      return;
    }
    if (duration.inMilliseconds < 700) {
      // Treat sub-700ms recordings as accidental taps.
      _safeDelete(finalPath);
      return;
    }

    final file = File(finalPath);
    if (!await file.exists()) return;

    AzamanHaptics.commit();
    widget.onRecorded(
      file,
      duration.inSeconds.clamp(1, 1 << 30),
      peaksSnapshot.isEmpty ? List<int>.filled(20, 30) : peaksSnapshot,
    );
  }

  Future<void> _safeDelete(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {/* swallow */}
  }

  void _onDragStart(DragStartDetails d) {
    if (!_recording) return;
    _dragOrigin = d.globalPosition;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_recording) return;
    final dx = d.globalPosition.dx - _dragOrigin.dx;
    setState(() {
      _dragDx = dx;
      _cancelling = dx <= _cancelThresholdDx;
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (!_recording) return;
    _stopAndCommit();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    if (_recording) {
      return _RecordingStrip(
        elapsed: _elapsed,
        cancelling: _cancelling,
        dragDx: _dragDx,
        cancelThresholdDx: _cancelThresholdDx,
        colors: colors,
        onDragStart: _onDragStart,
        onDragUpdate: _onDragUpdate,
        onDragEnd: _onDragEnd,
        size: widget.size,
        peaks: _peaks,
      );
    }
    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopAndCommit(),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: colors.accent.withOpacity(widget.disabled ? 0.05 : 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(
          HugeIconsSolid.mic01,
          color: colors.accent.withOpacity(widget.disabled ? 0.4 : 1.0),
          size: 18,
        ),
      ),
    );
  }
}

class _RecordingStrip extends StatefulWidget {
  final Duration elapsed;
  final bool cancelling;
  final double dragDx;
  final double cancelThresholdDx;
  final AzamanColors colors;
  final void Function(DragStartDetails) onDragStart;
  final void Function(DragUpdateDetails) onDragUpdate;
  final void Function(DragEndDetails) onDragEnd;
  final double size;
  final List<int> peaks;

  const _RecordingStrip({
    required this.elapsed,
    required this.cancelling,
    required this.dragDx,
    required this.cancelThresholdDx,
    required this.colors,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.size,
    required this.peaks,
  });

  @override
  State<_RecordingStrip> createState() => _RecordingStripState();
}

class _RecordingStripState extends State<_RecordingStrip>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _chevronCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _chevronCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _chevronCtrl.dispose();
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final visualWarning = widget.dragDx < -40;
    final isCancelling = widget.cancelling;
    final baseColor = isCancelling ? widget.colors.danger : widget.colors.accent;

    return GestureDetector(
      onHorizontalDragStart: widget.onDragStart,
      onHorizontalDragUpdate: widget.onDragUpdate,
      onHorizontalDragEnd: widget.onDragEnd,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.size / 2),
        child: Container(
          height: widget.size,
          constraints: const BoxConstraints(minWidth: 220),
          decoration: BoxDecoration(
            color: visualWarning
                ? widget.colors.danger.withOpacity(0.3)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(widget.size / 2),
          ),
          child: Stack(
            children: [
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.colors.surface.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(widget.size / 2),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      width: _pulseCtrl.value * 4 + 10,
                      height: _pulseCtrl.value * 4 + 10,
                      decoration: BoxDecoration(
                        color: baseColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatElapsed(widget.elapsed),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 28,
                      width: widget.peaks.length * 4 + 4,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(
                          widget.peaks.length.clamp(0, 30),
                          (i) {
                            final peak = widget.peaks[i];
                            final barHeight = peak / 100 * 28;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 80),
                              width: 2,
                              height: barHeight.clamp(2, 28),
                              margin: const EdgeInsets.only(right: 2),
                              decoration: BoxDecoration(
                                color: isCancelling
                                    ? widget.colors.danger
                                    : widget.colors.accent,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Opacity(
                      opacity: isCancelling
                          ? 1.0
                          : (1.0 - (widget.dragDx / -40).clamp(0, 1)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _chevronCtrl,
                            builder: (_, __) {
                              return Transform.translate(
                                offset: Offset(
                                  -_chevronCtrl.value * 4,
                                  0,
                                ),
                                child: Icon(
                                  HugeIconsSolid.arrowLeft01,
                                  color: widget.colors.textTertiary,
                                  size: 14,
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isCancelling
                                ? 'Release to cancel'
                                : 'Slide to cancel',
                            style: TextStyle(
                              color: widget.colors.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
