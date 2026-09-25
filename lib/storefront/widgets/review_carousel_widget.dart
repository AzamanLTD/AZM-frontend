import 'package:flutter/material.dart';
import '../models/storefront_models.dart';

class ReviewCarouselWidget extends StatelessWidget {
  final Map<String, dynamic> props;
  final StorefrontBusinessInfo business;

  const ReviewCarouselWidget({super.key, required this.props, required this.business});

  @override
  Widget build(BuildContext context) {
    final title = props['title'] as String? ?? 'Reviews';
    final maxReviews = _asPositiveInt(props['maxReviews'], fallback: 5, max: 20);
    final minRating = _asInt(props['minRating'], fallback: 4).clamp(1, 5);
    final reviews = _parseReviews(props['reviews'], minRating: minRating, maxReviews: maxReviews);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (reviews.isEmpty)
          _EmptyReviews(business: business)
        else
          SizedBox(
            height: 136,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: reviews.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) => _ReviewCard(review: reviews[i]),
            ),
          ),
      ],
    );
  }

  static List<_ReviewData> _parseReviews(
    dynamic raw, {
    required int minRating,
    required int maxReviews,
  }) {
    if (raw is! List) return const [];

    final reviews = <_ReviewData>[];
    for (final value in raw) {
      if (value is! Map) continue;
      final rating = _asInt(value['rating'], fallback: 0).clamp(0, 5);
      if (rating < minRating) continue;
      final comment = value['comment']?.toString().trim() ?? '';
      final author = value['reviewerUsername']?.toString().trim() ??
          value['author']?.toString().trim() ??
          'Customer';
      if (comment.isEmpty) continue;
      reviews.add(_ReviewData(rating: rating, comment: comment, author: author));
      if (reviews.length >= maxReviews) break;
    }
    return reviews;
  }

  static int _asInt(dynamic value, {required int fallback}) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int _asPositiveInt(dynamic value, {required int fallback, required int max}) {
    return _asInt(value, fallback: fallback).clamp(1, max);
  }
}

class _ReviewData {
  final int rating;
  final String comment;
  final String author;

  const _ReviewData({required this.rating, required this.comment, required this.author});
}

class _ReviewCard extends StatelessWidget {
  final _ReviewData review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ...List.generate(
                5,
                (index) => Icon(
                  index < review.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 15,
                  color: scheme.primary,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  review.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              review.comment,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyReviews extends StatelessWidget {
  final StorefrontBusinessInfo business;

  const _EmptyReviews({required this.business});

  @override
  Widget build(BuildContext context) {
    final rating = business.averageRating;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Icon(Icons.rate_review_outlined, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rating != null
                  ? 'Rated ${rating.toStringAsFixed(1)} out of 5'
                  : 'No reviews yet',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
