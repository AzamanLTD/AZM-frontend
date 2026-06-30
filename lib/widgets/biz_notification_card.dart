// =============================================================================
// BIZ NOTIFICATION CARD — Flutter V3 Marketplace Sprint (2026-06-21)
//
// A single owner-facing business notification row: a type-coloured icon, the
// title + one-line body, a relative timestamp, and an unread dot.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';

class BizNotificationCard extends ConsumerWidget {
  final BizNotification notification;
  final VoidCallback onTap;

  const BizNotificationCard({
    super.key,
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final (icon, tint) = _iconFor(notification.type, colors);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notification.isRead
              ? colors.card
              : colors.accentSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: tint, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    notification.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notification.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _timeAgo(notification.createdAt),
                  style: TextStyle(color: colors.textTertiary, fontSize: 10.5),
                ),
                const SizedBox(height: 6),
                if (!notification.isRead)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color) _iconFor(String type, AzamanColors colors) {
    switch (type.toUpperCase()) {
      case 'NEW_ORDER':
        return (Icons.shopping_bag_outlined, colors.accent);
      case 'ORDER_FUNDED':
        return (Icons.account_balance_wallet_outlined, colors.success);
      case 'ORDER_SATISFIED':
      case 'ORDER_SETTLED':
        return (Icons.check_circle_outline, colors.success);
      case 'ORDER_DISPUTED':
        return (Icons.error_outline, colors.danger);
      case 'ORDER_CANCELLED':
      case 'ORDER_REFUNDED':
        return (Icons.cancel_outlined, colors.textTertiary);
      case 'KYB_STATUS_CHANGED':
        return (Icons.shield_outlined, colors.warning);
      case 'INVOICE_PAID':
        return (Icons.receipt_outlined, colors.success);
      default:
        return (Icons.notifications_outlined, colors.accent);
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo';
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'now';
  }
}
