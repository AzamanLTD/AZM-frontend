// =============================================================================
// TRUST BREAKDOWN SHEET — Phase UI-7 (2026-05-27)
//
// Reusable bottom sheet that drills into a friend's trust metric. Shown when
// the user taps the persistent trust line under the contact's name in the
// chat AppBar, or the "Completed Transactions" stat pill on the Chat
// Profile vault screen.
//
// Anatomy:
//   • Avatar + username header
//   • Big total + ⭐ rating (or "No reviews yet" when null)
//   • Three category rows with icons + counts:
//       — P2P Trades        (User.tradesCompleted)
//       — Peer Transfers    (PeerTransfer status=COMPLETED)
//       — Tickets           (Ticket status=CLOSED)
//   • Verified Vendor caption — only shown when role=VENDOR && kyc=VERIFIED
//
// Pure presentational — accepts pre-computed values and renders. The caller
// is responsible for sourcing the breakdown (typically from
// `ChatTrustMetrics.breakdown` returned by `chatTrustMetricsProvider`).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/chat_profile_service.dart';
import 'package:hugeicons_pro/hugeicons.dart';

/// Public entry point — opens the breakdown as a modal bottom sheet.
Future<void> showTrustBreakdownSheet(
  BuildContext context, {
  required String username,
  required TrustBreakdown breakdown,
  double? rating,
  int positiveReviews = 0,
  int negativeReviews = 0,
  bool isVerifiedVendor = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _TrustBreakdownSheet(
      username: username,
      breakdown: breakdown,
      rating: rating,
      positiveReviews: positiveReviews,
      negativeReviews: negativeReviews,
      isVerifiedVendor: isVerifiedVendor,
    ),
  );
}

class _TrustBreakdownSheet extends ConsumerWidget {
  final String username;
  final TrustBreakdown breakdown;
  final double? rating;
  final int positiveReviews;
  final int negativeReviews;
  final bool isVerifiedVendor;

  const _TrustBreakdownSheet({
    required this.username,
    required this.breakdown,
    required this.positiveReviews,
    required this.negativeReviews,
    required this.isVerifiedVendor,
    this.rating,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final total = breakdown.total;
    final reviewTotal = positiveReviews + negativeReviews;

    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border.all(color: colors.divider, width: 0.5),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Header row
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: colors.accent.withOpacity(0.15),
                child: Text(
                  username.isNotEmpty ? username[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: colors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (isVerifiedVendor) ...[
                          const SizedBox(width: 5),
                          Icon(
                            HugeIconsSolid.checkmarkCircle01,
                            color: colors.accent,
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      'Reputation breakdown',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Hero — total + rating
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.divider),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COMPLETED TRANSACTIONS',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$total',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: colors.divider,
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'RATING',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (rating != null)
                      Row(
                        children: [
                          Icon(HugeIconsSolid.star,
                              color: colors.warning, size: 18),
                          const SizedBox(width: 2),
                          Text(
                            rating!.toStringAsFixed(1),
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        '—',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    if (reviewTotal > 0)
                      Text(
                        '$reviewTotal review${reviewTotal == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 10,
                        ),
                      )
                    else
                      Text(
                        'No reviews yet',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Per-category rows
          _CategoryRow(
            colors: colors,
            icon: HugeIconsSolid.exchange01,
            iconTint: colors.success,
            label: 'P2P Trades',
            description: 'Escrow-backed buy/sell trades on the marketplace',
            count: breakdown.tradesCompleted,
          ),
          const SizedBox(height: 8),
          _CategoryRow(
            colors: colors,
            icon: HugeIconsSolid.wallet01,
            iconTint: colors.accent,
            label: 'Peer Transfers',
            description: 'Direct money transfers between friends',
            count: breakdown.completedTransfers,
          ),
          const SizedBox(height: 8),
          _CategoryRow(
            colors: colors,
            icon: HugeIconsSolid.ticket01,
            iconTint: colors.warning,
            label: 'Tickets Closed',
            description: 'Deal-tracking workspaces marked complete',
            count: breakdown.closedTickets,
          ),
          if (isVerifiedVendor) ...[
            const SizedBox(height: 14),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: colors.accent.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Icon(HugeIconsSolid.checkmarkCircle01,
                      color: colors.accent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Verified Vendor — KYC complete and approved by Azaman.',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Counts include every committed transaction across the platform.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textTertiary, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final AzamanColors colors;
  final IconData icon;
  final Color iconTint;
  final String label;
  final String description;
  final int count;

  const _CategoryRow({
    required this.colors,
    required this.icon,
    required this.iconTint,
    required this.label,
    required this.description,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconTint.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconTint, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$count',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
