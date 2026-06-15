import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hugeicons_pro/hugeicons.dart';

enum BanStatus { active, warned, restricted, banned }

class GhostBanWrapper extends ConsumerStatefulWidget {
  final Widget child;
  final BanStatus banStatus;
  final DateTime? bannedUntil;

  const GhostBanWrapper({
    super.key,
    required this.child,
    this.banStatus = BanStatus.active,
    this.bannedUntil,
  });

  @override
  ConsumerState<GhostBanWrapper> createState() => _GhostBanWrapperState();
}

class _GhostBanWrapperState extends ConsumerState<GhostBanWrapper> {
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;

  bool get _isBanned => widget.banStatus != BanStatus.active;

  @override
  void initState() {
    super.initState();
    _initCountdown();
  }

  @override
  void didUpdateWidget(GhostBanWrapper old) {
    super.didUpdateWidget(old);
    if (old.bannedUntil != widget.bannedUntil) {
      _countdownTimer?.cancel();
      _initCountdown();
    }
  }

  void _initCountdown() {
    if (widget.bannedUntil == null) return;
    _remaining = widget.bannedUntil!.difference(DateTime.now());
    if (_remaining.isNegative) {
      _remaining = Duration.zero;
      return;
    }
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final diff = widget.bannedUntil!.difference(DateTime.now());
      if (diff.isNegative) {
        _countdownTimer?.cancel();
        if (mounted) setState(() => _remaining = Duration.zero);
        return;
      }
      if (mounted) setState(() => _remaining = diff);
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  String get _banStatusLabel {
    switch (widget.banStatus) {
      case BanStatus.warned:
        return 'ACCOUNT WARNED';
      case BanStatus.restricted:
        return 'ACCOUNT RESTRICTED';
      case BanStatus.banned:
        return 'ACCOUNT BANNED';
      case BanStatus.active:
        return 'ACTIVE';
    }
  }

  String get _formattedCountdown {
    if (_remaining == Duration.zero) return '--:--:--';
    final h = _remaining.inHours;
    final m = _remaining.inMinutes.remainder(60);
    final s = _remaining.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _openAppealEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'appeals@azaman.io',
      queryParameters: {
        'subject': 'Ghost Ban Appeal - ${widget.banStatus.name.toUpperCase()}',
        'body': 'I believe my account was incorrectly restricted.\n\n'
            'Current Status: ${widget.banStatus.name.toUpperCase()}\n'
            'Account: [ENTER_USER_ID]\n\n'
            'Please review and lift this restriction.',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Stack(
      children: [
        if (_isBanned)
          IgnorePointer(
            child: widget.child,
          )
        else
          widget.child,
        if (_isBanned)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Material(
                color: colors.danger.withOpacity(0.88),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors.danger.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          HugeIconsSolid.shield01,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _banStatusLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.bannedUntil != null
                                  ? 'Auto-lift in $_formattedCountdown'
                                  : 'Lift time unavailable',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontSize: 10,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _AppealButton(onTap: _openAppealEmail),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AppealButton extends StatefulWidget {
  final VoidCallback onTap;
  const _AppealButton({required this.onTap});

  @override
  State<_AppealButton> createState() => _AppealButtonState();
}

class _AppealButtonState extends State<_AppealButton> with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) => Transform.scale(
        scale: _pulseAnim.value,
        child: child,
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.25)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(HugeIconsSolid.mail01, color: Colors.white, size: 14),
              SizedBox(width: 6),
              Text(
                'Appeal',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
