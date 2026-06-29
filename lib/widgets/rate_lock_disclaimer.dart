import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class RateLockDisclaimer extends ConsumerStatefulWidget {
  final bool compact;
  final double? lockedRate;
  final DateTime? lockExpiresAt;

  const RateLockDisclaimer({
    super.key, this.compact = false,
    this.lockedRate, this.lockExpiresAt});

  @override
  ConsumerState<RateLockDisclaimer> createState() => _RateLockDisclaimerState();
}

class _RateLockDisclaimerState extends ConsumerState<RateLockDisclaimer> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateRemaining();
    });
  }

  void _updateRemaining() {
    if (widget.lockExpiresAt == null) return;
    final r = widget.lockExpiresAt!.difference(DateTime.now());
    setState(() => _remaining = r > Duration.zero ? r : Duration.zero);
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  String get _timeStr {
    if (widget.lockExpiresAt == null) return "";
    if (_remaining == Duration.zero) return "Expired";
    final m = _remaining.inMinutes.remainder(60).toString().padLeft(2, "0");
    final s = _remaining.inSeconds.remainder(60).toString().padLeft(2, "0");
    return "${_remaining.inHours > 0 ? "${_remaining.inHours}h " : ""}$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Container(
      margin: widget.compact ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.accent.withOpacity(0.25))),
      child: Row(children: [
        Icon(HugeIconsSolid.lock, color: colors.accent, size: widget.compact ? 14 : 16),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.lockedRate != null)
            Text(
              "Rate locked at GH₵${widget.lockedRate!.toStringAsFixed(2)}",
              style: TextStyle(color: colors.accent,
                fontSize: widget.compact ? 10 : 12,
                fontWeight: FontWeight.w800)),
          Text("Rate frozen for this trade.",
            style: TextStyle(color: colors.accent.withOpacity(0.75),
              fontSize: 10, height: 1.4)),
        ])),
        if (widget.lockExpiresAt != null && _timeStr.isNotEmpty) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8)),
            child: Text(_timeStr, style: TextStyle(
              color: colors.accent, fontSize: 12,
              fontWeight: FontWeight.w800,
              fontFamily: "monospace")),
          ),
        ],
      ]),
    );
  }
}
