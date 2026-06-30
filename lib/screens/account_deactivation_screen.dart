import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:record/record.dart';


class AccountDeactivationScreen extends ConsumerStatefulWidget {
  const AccountDeactivationScreen({super.key});

  @override
  ConsumerState<AccountDeactivationScreen> createState() => _AccountDeactivationScreenState();
}

class _AccountDeactivationScreenState extends ConsumerState<AccountDeactivationScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _reasonController = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  late AnimationController _waveformCtrl;
  bool _isRecording = false;
  bool _hasRecording = false;
  String? _recordPath;

  @override
  void initState() {
    super.initState();
    _waveformCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _waveformCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _onHoldStart() async {
    HapticFeedback.mediumImpact();
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Microphone permission denied.'),
              backgroundColor: ref.read(themeProvider).colors.danger,
            ),
          );
        }
        return;
      }

      final path = '/tmp/azaman_deletion_audio.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      _recordPath = path;
      setState(() => _isRecording = true);
      _waveformCtrl.repeat(reverse: true);
    } catch (e) {
      debugPrint('Record start error: $e');
    }
  }

  Future<void> _onHoldEnd() async {
    HapticFeedback.heavyImpact();
    try {
      await _recorder.stop();
    } catch (_) {}
    _waveformCtrl.stop();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _hasRecording = true;
      });
    }
  }

  void _clearRecording() {
    setState(() {
      _hasRecording = false;
      _recordPath = null;
    });
  }

  Future<void> _confirmDeletion() async {
    final colors = ref.read(themeProvider).colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: colors.danger, size: 22),
            const SizedBox(width: 10),
            Text(
              'Delete Account?',
              style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'This action is irreversible. All your data will be permanently removed.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: colors.textTertiary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.danger,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      HapticFeedback.heavyImpact();
      final reason = _reasonController.text.trim();
      debugPrint('Deletion requested — reason: $reason, audio: $_recordPath');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Account deletion request submitted.'),
          backgroundColor: colors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text(
          'DELETE ACCOUNT',
          style: TextStyle(
            color: colors.danger,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.danger.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.danger.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: colors.danger, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Permanent Removal',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Deleting your account removes all data permanently.',
                        style: TextStyle(color: colors.textTertiary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'REASON FOR LEAVING',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reasonController,
            maxLines: 4,
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Tell us why you\'re leaving...',
              hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
              filled: true,
              fillColor: colors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'VOICE NOTE (OPTIONAL)',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          _buildVoiceRecorder(colors),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.danger,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.delete_outline, size: 20),
              label: const Text(
                'CONFIRM DELETION',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              onPressed: _confirmDeletion,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceRecorder(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isRecording ? colors.danger.withOpacity(0.5) : colors.divider,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTapDown: (_) => _onHoldStart(),
                onTapUp: (_) => _onHoldEnd(),
                onTapCancel: _onHoldEnd,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording ? colors.danger : (_hasRecording ? colors.success : colors.surface),
                    boxShadow: _isRecording
                        ? [
                            BoxShadow(
                              color: colors.danger.withOpacity(0.4),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ]
                        : _hasRecording
                            ? [
                                BoxShadow(
                                  color: colors.success.withOpacity(0.3),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ]
                            : [],
                  ),
                  child: Icon(
                    _hasRecording ? Icons.check_circle_outline : Icons.mic_none_outlined,
                    color: _isRecording
                        ? Colors.white
                        : _hasRecording
                            ? Colors.white
                            : colors.textTertiary,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _isRecording
                    ? _WaveformAnimation(
                        controller: _waveformCtrl,
                        color: colors.danger,
                      )
                    : _hasRecording
                        ? Row(
                            children: [
                              Icon(Icons.music_note_outlined, color: colors.success, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Recording captured',
                                style: TextStyle(
                                  color: colors.success,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: _clearRecording,
                                child: Icon(Icons.cancel_outlined, color: colors.textTertiary, size: 18),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hold to Record',
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tap & hold the mic button',
                                style: TextStyle(color: colors.textTertiary, fontSize: 10),
                              ),
                            ],
                          ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WaveformAnimation extends StatelessWidget {
  final AnimationController controller;
  final Color color;

  const _WaveformAnimation({
    required this.controller,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(double.infinity, 40),
          painter: _WaveformPainter(
            progress: controller.value,
            color: color,
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;

  _WaveformPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.7)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final barCount = 32;
    final barSpacing = size.width / barCount;
    final barWidth = barSpacing * 0.55;

    for (int i = 0; i < barCount; i++) {
      final phase = (i / barCount) * 2 * pi;
      final sinVal = sin(phase - progress * 2 * pi);
      final envelope = 0.4 + 0.6 * sin((i / barCount) * pi);
      final height = (12 + sinVal.abs() * 16) * envelope;
      final x = i * barSpacing + (barSpacing - barWidth) / 2;
      final yCenter = size.height / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + barWidth / 2, yCenter),
            width: barWidth,
            height: height.clamp(4.0, size.height * 0.85),
          ),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
