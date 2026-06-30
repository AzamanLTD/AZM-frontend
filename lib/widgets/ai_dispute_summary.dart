import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';


class AiDisputeSummary extends ConsumerStatefulWidget {
  final String similarType;
  final int count;
  final String timeframe;
  final List<Map<String, String>>? historicalResolutions;
  final String? recommendedAction;
  final double confidence;

  const AiDisputeSummary({
    super.key,
    this.similarType = 'overpayment disputes',
    this.count = 4,
    this.timeframe = 'this month',
    this.historicalResolutions,
    this.recommendedAction,
    this.confidence = 94,
  });

  @override
  ConsumerState<AiDisputeSummary> createState() => _AiDisputeSummaryState();
}

class _AiDisputeSummaryState extends ConsumerState<AiDisputeSummary>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.9).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final resolutions = widget.historicalResolutions ?? [];

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colors.accent.withOpacity(_glowAnimation.value),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.accent.withOpacity(_glowAnimation.value * 0.15),
                blurRadius: 18 * _glowAnimation.value,
                spreadRadius: 0,
              ),
              BoxShadow(
                color: colors.accent.withOpacity(_glowAnimation.value * 0.08),
                blurRadius: 40 * _glowAnimation.value,
                spreadRadius: -2,
              ),
              BoxShadow(
                color: colors.accent.withOpacity(_glowAnimation.value * 0.04),
                blurRadius: 60 * _glowAnimation.value,
                spreadRadius: -6,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeaderRow(colors),
            const SizedBox(height: 10),
            _buildSummaryText(colors),
            const SizedBox(height: 8),
            _buildRecommendedAction(colors),
            if (resolutions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(color: colors.divider, height: 1),
              const SizedBox(height: 12),
              _buildHistoricalSection(colors),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow(AzamanColors colors) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.accent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.auto_awesome,
            color: colors.accent,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'AI SUMMARY',
          style: TextStyle(
            color: colors.accent,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: colors.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'BETA',
            style: TextStyle(
              color: colors.accent,
              fontSize: 7,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'AI confidence: ${widget.confidence.toStringAsFixed(0)}% '
                  'based on historical resolution data',
                ),
                backgroundColor: colors.surface,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.info_outline,
              size: 14,
              color: colors.accent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryText(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.background.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.analytics_outlined, size: 14, color: colors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You have handled ${widget.count} similar '
              '${widget.similarType} ${widget.timeframe}.',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendedAction(AzamanColors colors) {
    final action = widget.recommendedAction ?? 'Standard refund process';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 12, color: colors.success),
          const SizedBox(width: 6),
          Text(
            'Recommended: $action',
            style: TextStyle(
              color: colors.success,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoricalSection(AzamanColors colors) {
    final resolutions = widget.historicalResolutions!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history, size: 12, color: colors.textTertiary),
            const SizedBox(width: 6),
            Text(
              'HISTORICAL RESOLUTIONS',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...resolutions.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _resolutionRow(r, colors),
            )),
      ],
    );
  }

  Widget _resolutionRow(Map<String, String> resolution, AzamanColors colors) {
    final outcome = resolution['outcome']?.toLowerCase() ?? '';
    final isFavorable = outcome == 'resolved' || outcome == 'buyer win';
    final label = resolution['label'] ?? 'Unknown';
    final detail = resolution['detail'] ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.background.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isFavorable ? colors.success : colors.warning,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          if (detail.isNotEmpty)
            Text(
              detail,
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }
}


