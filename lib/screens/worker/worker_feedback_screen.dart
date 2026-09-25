import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/worker_provider.dart';

class WorkerFeedbackScreen extends ConsumerWidget {
  const WorkerFeedbackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final feedbackAsync = ref.watch(myFeedbackProvider);

    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Feedback', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: feedbackAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
        error: (_, __) => Center(child: Text('Unable to load feedback', style: TextStyle(color: colors.textSecondary))),
        data: (feedback) {
          if (feedback.isEmpty) {
            return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.rate_review_outlined, size: 48, color: colors.textTertiary),
                const SizedBox(height: 12),
                Text('No feedback yet', style: TextStyle(color: colors.textSecondary, fontSize: 15)),
              ],
            ));
          }
          final avgRating = feedback.map((f) => f.rating).reduce((a, b) => a + b) / feedback.length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surface, borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border, width: 1),
                ),
                child: Row(
                  children: [
                    Text(avgRating.toStringAsFixed(1), style: TextStyle(color: colors.textPrimary, fontSize: 36, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: List.generate(5, (i) => Icon(
                          i < avgRating.round() ? Icons.star : Icons.star_border,
                          size: 16, color: Colors.amber))),
                        Text('${feedback.length} reviews', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ...feedback.map((f) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surface, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.border, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Row(children: List.generate(5, (i) => Icon(
                          i < f.rating ? Icons.star : Icons.star_border,
                          size: 14, color: Colors.amber))),
                        const SizedBox(width: 8),
                        Text(f.giverName ?? 'Anonymous', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                      ],
                    ),
                    if (f.comment != null) ...[
                      const SizedBox(height: 8),
                      Text(f.comment!, style: TextStyle(color: colors.textPrimary, fontSize: 13)),
                    ],
                    if (f.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, children: f.tags.map((t) =>
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: colors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                          child: Text(t, style: TextStyle(color: colors.accent, fontSize: 10, fontWeight: FontWeight.w500)),
                        )).toList()),
                    ],
                  ],
                ),
              )),
            ],
          );
        },
      ),
    );
  }
}
