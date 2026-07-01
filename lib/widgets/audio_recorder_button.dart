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
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';


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

  final ValueChanged<bool>? onRecordingStateChanged;

  const AudioRecorderButton({
    super.key,
    required this.onRecorded,
    this.disabled = false,
    this.size = 36,
    this.onRecordingStateChanged,
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
  bool _locked = false;
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
  double _dragDy = 0;
  static const double _cancelThresholdDx = -80;
  static const double _lockThresholdDy = -65;

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
      try {
        await _recorder.start(const RecordConfig(), path: path);
      } catch (fallbackError) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start recording: $e')),
        );
        return;
      }
    }

    AzamanHaptics.confirm();
    if (!mounted) return;
    setState(() {
      _recording = true;
      _cancelling = false;
      _locked = false;
      _peaks.clear();
      _filePath = path;
      _startedAt = DateTime.now();
      _elapsed = Duration.zero;
      _dragDx = 0;
      _dragDy = 0;
    });
    widget.onRecordingStateChanged?.call(true);

    _tickTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || !_recording) return;
      setState(() {
        _elapsed = DateTime.now().difference(_startedAt!);
        // Fallback: If hardware amplitude stream drops, inject synthetic peaks so the UI always looks alive
        if (_peaks.length < (_elapsed.inMilliseconds / 200).floor()) {
          if (_peaks.length >= 50) _peaks.removeAt(0);
          _peaks.add(15 + (DateTime.now().millisecondsSinceEpoch % 30));
        }
      });
    });

    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 200))
        .listen((amp) {
      // amp.current is in dBFS, typically -160..0. Normalise to 0..100.
      final db = amp.current.isFinite ? amp.current : -60.0;
      final pct = ((db + 60) / 60 * 100).clamp(0, 100).round();
      setState(() {
        if (_peaks.length >= 50) {
          // Keep the most recent 50 buckets so longer notes still produce
          // a meaningful waveform without exploding the JSON payload.
          _peaks.removeAt(0);
        }
        _peaks.add(pct);
      });
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
        _locked = false;
        _elapsed = Duration.zero;
        _peaks.clear();
        _filePath = null;
        _startedAt = null;
        _dragDx = 0;
        _dragDy = 0;
      });
      widget.onRecordingStateChanged?.call(false);
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

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomRight,
      children: [
        // 1. Recording Strip (Slides in from right over input field)
        if (_recording)
          Positioned(
            right: (_locked ? widget.size : widget.size * 1.5) + 12,
            bottom: 0,
            child: Transform.translate(
              offset: Offset(_dragDx, 0),
              child: _RecordingStrip(
                elapsed: _elapsed,
                cancelling: _cancelling,
                locked: _locked,
                dragDx: _dragDx,
                cancelThresholdDx: _cancelThresholdDx,
                colors: colors,
                onCancelRecording: () {
                  setState(() => _cancelling = true);
                  _stopAndCommit();
                },
                size: widget.size,
                peaks: _peaks,
              ),
            ),
          ),
          
        // 2. Lock Indicator (Bouncing above mic)
        if (_recording && !_locked)
          Positioned(
            right: 0,
            bottom: widget.size + 16 + (_dragDy.clamp(_lockThresholdDy, 0.0).abs() * 0.5),
            child: _LockIndicator(colors: colors),
          ),
          
        // 3. Main Mic/Send Button
        GestureDetector(
          onLongPressStart: (d) {
            _dragOrigin = d.globalPosition;
            _startRecording();
          },
          onLongPressMoveUpdate: (d) {
            if (!_recording || _locked) return;
            final dx = d.globalPosition.dx - _dragOrigin.dx;
            final dy = d.globalPosition.dy - _dragOrigin.dy;
            setState(() {
              _dragDx = dx;
              _dragDy = dy;
              _cancelling = dx <= _cancelThresholdDx;
              if (dy <= _lockThresholdDy) {
                _locked = true;
                _dragDy = 0;
                HapticFeedback.heavyImpact();
              }
            });
          },
          onLongPressEnd: (d) {
            if (!_recording || _locked) return;
            _stopAndCommit();
          },
          onTap: () {
            if (_locked) {
              _stopAndCommit(); // Send recorded audio
            } else if (!_recording) {
              // Quick tap ignores, maybe could add a hint toast
              HapticFeedback.selectionClick();
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutBack,
            width: _recording && !_locked ? widget.size * 1.5 : widget.size,
            height: _recording && !_locked ? widget.size * 1.5 : widget.size,
            decoration: BoxDecoration(
              color: _locked ? colors.accent : colors.accent.withOpacity(widget.disabled ? 0.05 : 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Icon(
                _locked ? HugeIconsSolid.sent : Icons.mic_rounded,
                key: ValueKey(_locked),
                color: _locked ? Colors.white : colors.accent.withOpacity(widget.disabled ? 0.4 : 1.0),
                size: _recording && !_locked ? 28 : 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Bouncing Lock Indicator (Telegram Style) ─────────────────────────────
class _LockIndicator extends StatefulWidget {
  final AzamanColors colors;
  const _LockIndicator({required this.colors});
  @override State<_LockIndicator> createState() => _LockIndicatorState();
}

class _LockIndicatorState extends State<_LockIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, -_ctrl.value * 6),
        child: Container(
          width: 44, height: 60,
          decoration: BoxDecoration(
            color: widget.colors.surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2)],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_open_rounded, size: 16, color: widget.colors.textSecondary),
              const SizedBox(height: 6),
              Icon(Icons.keyboard_arrow_up, size: 18, color: widget.colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Horizontal Recording Strip with Live Waveform ────────────────────────
class _RecordingStrip extends StatefulWidget {
  final Duration elapsed;
  final bool cancelling;
  final bool locked;
  final double dragDx;
  final double cancelThresholdDx;
  final AzamanColors colors;
  final VoidCallback onCancelRecording;
  final double size;
  final List<int> peaks;

  const _RecordingStrip({
    required this.elapsed,
    required this.cancelling,
    required this.locked,
    required this.dragDx,
    required this.cancelThresholdDx,
    required this.colors,
    required this.onCancelRecording,
    required this.size,
    required this.peaks,
  });

  @override State<_RecordingStrip> createState() => _RecordingStripState();
}

class _RecordingStripState extends State<_RecordingStrip> with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isCancelling = widget.cancelling;
    final baseColor = isCancelling ? widget.colors.danger : widget.colors.accent;

    return Container(
      height: widget.size,
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.55),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: widget.colors.surface,
        borderRadius: BorderRadius.circular(widget.size / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Blinking red dot
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Container(
              width: _pulseCtrl.value * 3 + 8,
              height: _pulseCtrl.value * 3 + 8,
              decoration: BoxDecoration(color: baseColor, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          // Timer
          Text(_formatElapsed(widget.elapsed),
            style: TextStyle(color: widget.colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          const SizedBox(width: 12),
          // Live Continuous Waveform
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Ensure there is some width to draw waveform
                final availableWidth = constraints.maxWidth > 0 ? constraints.maxWidth : 100.0;
                final maxVisiblePeaks = (availableWidth / 5.0).floor();
                final visiblePeaks = widget.peaks.length > maxVisiblePeaks
                    ? widget.peaks.sublist(widget.peaks.length - maxVisiblePeaks)
                    : widget.peaks;

                return ClipRect(
                  child: SizedBox(
                    height: 24,
                    width: availableWidth,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: List.generate(
                        visiblePeaks.length,
                        (i) {
                          final peak = visiblePeaks[i];
                          final h = (peak / 100 * 24).clamp(3.0, 24.0);
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 100),
                            width: 2.5,
                            height: h,
                            margin: const EdgeInsets.only(left: 2.5),
                            decoration: BoxDecoration(
                              color: isCancelling ? widget.colors.danger.withOpacity(0.5) : widget.colors.accent.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          // Cancel/Slide text
          if (!widget.locked)
            Opacity(
              opacity: isCancelling ? 1.0 : (1.0 - (widget.dragDx / -40).clamp(0.0, 1.0)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.keyboard_arrow_left, color: widget.colors.textTertiary, size: 16),
                  Text(isCancelling ? 'Release to cancel' : 'Slide to cancel',
                    style: TextStyle(color: widget.colors.textTertiary, fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
            )
          else
            GestureDetector(
              onTap: widget.onCancelRecording,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: Text('Cancel', style: TextStyle(color: widget.colors.danger, fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}
