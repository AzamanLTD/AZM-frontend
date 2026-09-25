import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';

/// Compact indicator for the age/refresh window of the current FX rate.
class RateRefreshIndicator extends ConsumerStatefulWidget {
  const RateRefreshIndicator({super.key});

  @override
  ConsumerState<RateRefreshIndicator> createState() =>
      _RateRefreshIndicatorState();
}

class _RateRefreshIndicatorState extends ConsumerState<RateRefreshIndicator> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final metadata = ref.watch(oracleRateMetadataProvider);
    final remaining = metadata.timeUntilRefresh;
    final seconds = remaining.inSeconds.clamp(0, 9999);
    final stale = metadata.stale;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            value: stale ? null : metadata.progress,
            strokeWidth: 1.5,
            backgroundColor: colors.textTertiary.withValues(alpha: 0.18),
            valueColor: AlwaysStoppedAnimation<Color>(
              stale ? colors.warning : colors.accent,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          stale
              ? 'Rate updating'
              : seconds > 0
                  ? 'Refresh ${seconds}s'
                  : 'Refreshing…',
          style: TextStyle(
            color: stale ? colors.warning : colors.textTertiary,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
