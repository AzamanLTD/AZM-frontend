import 'package:flutter/material.dart';
import 'package:azaman/services/vendor_badge_service.dart';
import 'package:azaman/providers/theme_provider.dart';

// =============================================================================
// AZAMAN — VENDOR BADGE ROW (Phase Q13-FE)
//
// A small row of colored badge icons rendered below a vendor's name on
// marketplace ad cards. Shows max 3 badges + "+N" overflow indicator.
// Fetches badges lazily on first build and caches via VendorBadgeService.
// =============================================================================

class VendorBadgeRow extends StatefulWidget {
  final int vendorId;
  final AzamanColors colors;

  const VendorBadgeRow({
    super.key,
    required this.vendorId,
    required this.colors,
  });

  @override
  State<VendorBadgeRow> createState() => _VendorBadgeRowState();
}

class _VendorBadgeRowState extends State<VendorBadgeRow> {
  List<VendorBadge>? _badges;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchBadges();
  }

  Future<void> _fetchBadges() async {
    final badges = await vendorBadgeService.fetchBadges(widget.vendorId);
    if (mounted) {
      setState(() {
        _badges = badges;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _badges == null || _badges!.isEmpty) {
      return const SizedBox.shrink();
    }

    final badges = _badges!;
    final displayBadges = badges.take(3).toList();
    final overflow = badges.length - 3;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          ...displayBadges.map((badge) => _BadgeChip(
                badge: badge,
                colors: widget.colors,
              )),
          if (overflow > 0) ...[
            const SizedBox(width: 4),
            Text(
              '+$overflow',
              style: TextStyle(
                color: widget.colors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final VendorBadge badge;
  final AzamanColors colors;

  const _BadgeChip({required this.badge, required this.colors});

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(badge.color);

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: '${badge.name}: ${badge.description}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.3), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getIconData(badge.icon),
                size: 12,
                color: color,
              ),
              const SizedBox(width: 3),
              Text(
                badge.name,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      final cleaned = hex.replaceAll('#', '');
      return Color(int.parse('FF$cleaned', radix: 16));
    } catch (_) {
      return colors.accent;
    }
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'verified':
        return Icons.verified_rounded;
      case 'trending_up':
        return Icons.trending_up_rounded;
      case 'bolt':
        return Icons.bolt_rounded;
      case 'shield':
        return Icons.shield_rounded;
      case 'diamond':
        return Icons.diamond_rounded;
      case 'star':
        return Icons.star_rounded;
      default:
        return Icons.workspace_premium_rounded;
    }
  }
}
