import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/account_activity_screen.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/services/home_summary_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/skeleton_loader.dart';

class RecentActivitySection extends ConsumerWidget {
  const RecentActivitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final summary = ref.watch(homeSummaryProvider);
    final txns = summary.recentTransactions;

    final isColdLoad = summary.loading &&
        txns.isEmpty &&
        summary.transactionsError == null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Transactions',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              if (txns.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    AzamanHaptics.nav();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AccountActivityScreen(),
                      ),
                    );
                  },
                  child: Text(
                    'See all',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor: colors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (isColdLoad)
            const _ActivitySkeleton()
          else if (txns.isEmpty)
            _EmptyActivity(colors: colors)
          else
            Column(
              children: [
                for (final t in txns)
                  _ActivityRow(colors: colors, txn: t),
              ],
            ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final AzamanColors colors;
  final TransactionSummary txn;

  const _ActivityRow({required this.colors, required this.txn});

  @override
  Widget build(BuildContext context) {
    final isPending = txn.status == 'PENDING';
    final isFailed =
        txn.status == 'FAILED' || txn.status == 'CANCELLED';
    final amountColor = isFailed
        ? colors.textTertiary
        : txn.isCredit
            ? colors.success
            : colors.textPrimary;
    final sign = txn.isCredit ? '+' : '-';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.softSurface,
            ),
            child: Icon(
              txn.isCredit
                  ? HugeIconsSolid.arrowDownLeft01
                  : HugeIconsSolid.arrowUpRight01,
              size: 18,
              color: txn.isCredit ? colors.success : colors.textSecondary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txn.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _subtitle(txn),
                  style: TextStyle(
                    color: isPending ? colors.warning : colors.textTertiary,
                    fontSize: 12.5,
                    fontWeight:
                        isPending ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$sign\$${_fmt(txn.amount)}',
            style: TextStyle(
              color: amountColor,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              decoration:
                  isFailed ? TextDecoration.lineThrough : TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle(TransactionSummary t) {
    if (t.status == 'PENDING') return 'Pending';
    if (t.status == 'FAILED') return 'Failed';
    if (t.status == 'CANCELLED') return 'Cancelled';
    return _relative(t.createdAt);
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return '$buf.${parts[1]}';
  }

  String _relative(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}

class _EmptyActivity extends StatelessWidget {
  final AzamanColors colors;
  const _EmptyActivity({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.softSurface,
          ),
          child: Icon(
            HugeIconsSolid.transactionHistory,
            size: 19,
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No transactions yet',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'They\u2019ll appear here after your first payment',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w400,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            AzamanHaptics.nav();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DepositScreen()),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Add',
              style: TextStyle(
                color: Colors.black,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (_) => const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              SkeletonBlock(
                width: 42,
                height: 42,
                borderRadius: BorderRadius.all(Radius.circular(21)),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBlock(width: 140, height: 13),
                    SizedBox(height: 7),
                    SkeletonBlock(width: 80, height: 11),
                  ],
                ),
              ),
              SizedBox(width: 10),
              SkeletonBlock(width: 54, height: 14),
            ],
          ),
        ),
      ),
    );
  }
}
