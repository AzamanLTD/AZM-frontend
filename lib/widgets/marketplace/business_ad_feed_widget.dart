import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// §38 — BusinessAdFeedWidget: Displays ad posts from followed businesses.
/// Shown as a horizontal scrollable strip on the marketplace home screen,
/// similar to Instagram stories but for business promotions.
class BusinessAdFeedWidget extends ConsumerWidget {
  const BusinessAdFeedWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: Wire to marketplace_extensions_provider for real data
    // For now, shows a placeholder when no ads are available
    return const _AdFeedContent();
  }
}

class _AdFeedContent extends StatelessWidget {
  const _AdFeedContent();

  @override
  Widget build(BuildContext context) {
    // Placeholder — will be populated from followed business ads
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 0, // Will be populated from provider
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return _AdPostCard(
            businessName: '',
            logoUrl: null,
            title: '',
            templateType: 'PROMO',
            onTap: () {},
          );
        },
      ),
    );
  }
}

class _AdPostCard extends StatelessWidget {
  final String businessName;
  final String? logoUrl;
  final String title;
  final String templateType;
  final VoidCallback onTap;

  const _AdPostCard({
    required this.businessName,
    required this.logoUrl,
    required this.title,
    required this.templateType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final typeColor = switch (templateType) {
      'PROMO' => const Color(0xFF10B981),
      'NEW_ITEM' => const Color(0xFF3B82F6),
      'EVENT' => const Color(0xFFF59E0B),
      _ => const Color(0xFF8B5CF6),
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: typeColor.withValues(alpha: 0.1),
                  backgroundImage: logoUrl != null ? NetworkImage(logoUrl!) : null,
                  child: logoUrl == null
                      ? Icon(Icons.store, size: 14, color: typeColor)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    businessName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    templateType,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: typeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
