import 'package:flutter/material.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';

/// Extracted from business_profile_screen.dart to reduce its size.
/// Displays business reviews with rating distribution and individual review cards.
class BusinessReviewsSection extends StatelessWidget {
  final BusinessProfile business;
  final AzamanColors colors;

  const BusinessReviewsSection({
    super.key,
    required this.business,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return _buildReviewsSection(business, colors);
  }

  Widget _buildReviewsSection(BusinessProfile business, AzamanColors colors) {
    final reviews = business.reviews;
    final avg = business.averageRating;
    final count = business.reviewCount;

    if (reviews.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.reviews_outlined, size: 40, color: colors.textTertiary),
            const SizedBox(height: 8),
            Text('No reviews yet', style: TextStyle(color: colors.textSecondary, fontSize: 14)),
            const SizedBox(height: 4),
            Text('Be the first to leave a review!', style: TextStyle(color: colors.textTertiary, fontSize: 12)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Text(avg.toStringAsFixed(1),
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: colors.textPrimary)),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: List.generate(5, (i) => Icon(i < avg.round() ? Icons.star : Icons.star_border, size: 14, color: Colors.amber))),
                  Text('$count reviews', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                ],
              ),
              const Spacer(),
              Icon(Icons.reviews, color: colors.accent, size: 20),
            ],
          ),
        ),
        _buildDistribution(reviews, colors),
        const Divider(height: 1),
        ...reviews.map((r) => _buildReviewCard(r, colors)),
      ],
    );
  }

  Widget _buildDistribution(List<BusinessReview> reviews, AzamanColors colors) {
    final dist = List.filled(5, 0);
    for (final r in reviews) {
      final idx = (r.rating - 1).clamp(0, 4);
      dist[idx]++;
    }
    final total = reviews.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: List.generate(5, (i) {
          final star = 5 - i;
          final count = dist[star - 1];
          final pct = total > 0 ? count / total : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Text('$star', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                const SizedBox(width: 4),
                Icon(Icons.star, size: 12, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: colors.divider,
                      valueColor: AlwaysStoppedAnimation(colors.accent),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('$count', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildReviewCard(BusinessReview r, AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: colors.accent.withOpacity(0.1),
                child: Text(r.reviewerUsername.isNotEmpty ? r.reviewerUsername[0].toUpperCase() : '?',
                    style: TextStyle(fontSize: 11, color: colors.accent, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.reviewerUsername, style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    Row(children: List.generate(5, (i) => Icon(i < r.rating ? Icons.star : Icons.star_border, size: 12, color: Colors.amber))),
                  ],
                ),
              ),
              Text(_formatDate(r.createdAt), style: TextStyle(color: colors.textTertiary, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 6),
          Text(r.comment ?? '', style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}
