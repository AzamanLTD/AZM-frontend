// =============================================================================
// VOICE MESSAGE BUBBLE — Phase 11.1
//
// WhatsApp-style voice note playback: static waveform bars with moving playhead,
// tap-to-seek, playback speed toggle (1x / 1.5x / 2x), duration display.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:azaman/config.dart';

class VoiceMessageBubble extends StatefulWidget {
  final String audioUrl;
  final List<double>? waveform; // 0.0–1.0, ~40 samples (null = render flat bars)
  final Duration duration;
  final bool isOutgoing;

  const VoiceMessageBubble({
    super.key,
    required this.audioUrl,
    this.waveform,
    required this.duration,
    required this.isOutgoing,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble>
    with WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  double _progress = 0; // 0..1
  double _speed = 1.0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _player.onPositionChanged.listen((p) {
      if (_disposed) return;
      final total = widget.duration.inMilliseconds;
      if (total > 0) {
        setState(() => _progress = (p.inMilliseconds / total).clamp(0, 1));
      }
    });

    _player.onPlayerComplete.listen((_) {
      if (_disposed) return;
      setState(() {
        _playing = false;
        _progress = 0;
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause playback when app goes to background
    if (state != AppLifecycleState.resumed && _playing) {
      _player.pause();
      setState(() => _playing = false);
    }
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http')) return url;
    return '${AppConfig.baseUrl}$url';
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      await _player.play(UrlSource(_resolveUrl(widget.audioUrl)));
      await _player.setPlaybackRate(_speed);
      setState(() => _playing = true);
    }
  }

  void _cycleSpeed() {
    HapticFeedback.selectionClick();
    const speeds = [1.0, 1.5, 2.0];
    final next = speeds[(speeds.indexOf(_speed) + 1) % speeds.length];
    setState(() => _speed = next);
    if (_playing) _player.setPlaybackRate(next);
  }

  Future<void> _seekTo(double dx, double width) async {
    final ratio = (dx / width).clamp(0.0, 1.0);
    final pos = widget.duration * ratio;
    await _player.seek(pos);
    if (!_playing) {
      setState(() => _progress = ratio);
    }
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isOutgoing ? Colors.white : Theme.of(context).colorScheme.primary;
    final dimAccent = accent.withValues(alpha: 0.3);
    final samples = widget.waveform ?? _fallbackWaveform();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Play / Pause button ──────────────────────────────────────────
        InkWell(
          customBorder: const CircleBorder(),
          onTap: _toggle,
          child: CircleAvatar(
            radius: 18,
            backgroundColor: accent.withValues(alpha: 0.15),
            child: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: accent,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 10),

        // ── Waveform with scrubbing ─────────────────────────────────────
        GestureDetector(
          onTapDown: (d) => _seekTo(d.localPosition.dx, 140),
          child: SizedBox(
            width: 140,
            height: 30,
            child: CustomPaint(
              painter: _WaveformPainter(
                samples: samples,
                progress: _progress,
                playedColor: accent,
                unplayedColor: dimAccent,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // ── Duration / Progress time ────────────────────────────────────
        SizedBox(
          width: 36,
          child: Text(
            _playing
                ? _fmtDuration(widget.duration * (1 - _progress))
                : _fmtDuration(widget.duration),
            style: TextStyle(
              fontSize: 11,
              color: accent.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 4),

        // ── Speed toggle ────────────────────────────────────────────────
        GestureDetector(
          onTap: _cycleSpeed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: accent.withValues(alpha: 0.12),
            ),
            child: Text(
              '${_speed}x',
              style: TextStyle(
                fontSize: 11,
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Fallback flat waveform when no amplitude data is available.
  List<double> _fallbackWaveform() {
    // Deterministic pseudo-waveform based on URL hash (no randomness on rebuild)
    final hash = widget.audioUrl.hashCode;
    return List.generate(40, (i) {
      final v = ((hash + i * 7919) % 100) / 100.0;
      return 0.15 + v * 0.75;
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WAVEFORM PAINTER
// ─────────────────────────────────────────────────────────────────────────────
class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;

  _WaveformPainter({
    required this.samples,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final barWidth = size.width / samples.length;
    final playedCount = (samples.length * progress).round();
    final centerY = size.height / 2;

    for (var i = 0; i < samples.length; i++) {
      final h = (samples[i].clamp(0.08, 1.0)) * size.height;
      final isPlayed = i < playedCount;
      final paint = Paint()
        ..color = isPlayed ? playedColor : unplayedColor
        ..strokeWidth = barWidth * 0.6
        ..strokeCap = StrokeCap.round;
      final x = i * barWidth + barWidth / 2;
      canvas.drawLine(Offset(x, centerY - h / 2), Offset(x, centerY + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress || old.samples != samples;
}
