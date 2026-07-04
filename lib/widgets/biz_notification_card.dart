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
import 'package:azaman/widgets/premium_glass_container.dart';

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
      child: PremiumGlassContainer(
        blur: 8,
        opacity: notification.isRead ? 0.03 : 0.06,
        borderRadius: 14,
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 8),
        enableShadow: false,
        border: Border.all(
          color: notification.isRead ? colors.divider : tint.withOpacity(0.2),
          width: notification.isRead ? 0.5 : 1,
        ),
        child: Row(
          children: [
            // Icon with glow
            Container(
              width: 40, height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withOpacity(0.12),
                borderRadius: BorderRadius.circular(11),
                boxShadow: notification.isRead ? null : [
                  BoxShadow(color: tint.withOpacity(0.1), blurRadius: 8),
                ],
              ),
              child: Icon(icon, color: tint, size: 18),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          notification.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                            fontWeight: notification.isRead ? FontWeight.w600 : FontWeight.w800,
                          ),
                        ),
                      ),
                      if (!notification.isRead) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 7, height: 7,
                          decoration: BoxDecoration(
                            color: colors.accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: colors.accent.withOpacity(0.4), blurRadius: 4),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notification.body,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textTertiary, fontSize: 12, height: 1.3),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _timeAgo(notification.createdAt),
                    style: TextStyle(fontSize: 10.5, color: colors.textTertiary, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
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
