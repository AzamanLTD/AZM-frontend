// lib/widgets/marketplace/store_order_pay.dart
// =============================================================================
// Paying a store order from the wallet.
//
// Checkout creates the order with a held payment (an escrow) for the
// server's own price plus the Azaman fee. This sheet shows exactly those
// numbers, then asks for the second factor and funds the escrow
// (POST /escrow/fund). The money is held, not paid to the store: the store
// is paid when the buyer taps "Got it", or 3 days after the store hands the
// order over if no problem is reported. An order not paid now can be paid
// from My orders until its payment hold lapses (24 hours).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/storefront/providers/storefront_provider.dart';
import 'package:azaman/widgets/home/money_lock_surface.dart';
import 'package:azaman/widgets/security/second_factor.dart';

/// What the buyer approves: the order's escrow as the server created it.
class StoreOrderPayment {
  const StoreOrderPayment({
    required this.escrowId,
    required this.amountUsdc,
    required this.feeUsdc,
    required this.storeName,
    this.orderRef,
    this.itemCount,
  });

  final String escrowId;
  final double amountUsdc;
  final double feeUsdc;
  final String storeName;
  final String? orderRef;
  final int? itemCount;

  double get totalUsdc =>
      double.parse((amountUsdc + feeUsdc).toStringAsFixed(6));

  static double _num(Object? v) =>
      v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

  /// The payment for an order that is still waiting for it (escrow DRAFT),
  /// or null: paid already, a direct order, or the hold lapsed.
  static StoreOrderPayment? fromOrder(
    Map<String, dynamic> order, {
    String? storeName,
  }) {
    final escrow = order['escrow'];
    if (escrow is! Map) return null;
    if ('${order['status'] ?? ''}'.toUpperCase() != 'AWAITING_PAYMENT') {
      return null;
    }
    if ('${escrow['status'] ?? ''}'.toUpperCase() != 'DRAFT') return null;
    final expires = DateTime.tryParse('${escrow['expiresAt'] ?? ''}');
    if (expires != null && expires.isBefore(DateTime.now())) return null;
    final id = escrow['id']?.toString();
    if (id == null || id.isEmpty) return null;
    final business = order['businessProfile'];
    final items = order['items'];
    return StoreOrderPayment(
      escrowId: id,
      amountUsdc: _num(escrow['amountUsdc'] ?? order['amountUsdc']),
      feeUsdc: _num(escrow['feeUsdc']),
      storeName:
          storeName ??
          (business is Map ? business['businessName']?.toString() : null) ??
          'the store',
      orderRef: order['orderRef']?.toString(),
      itemCount: items is List ? items.length : null,
    );
  }
}

enum StorePayResult { paid, notPaid, shortBalance }

/// A USDC amount exactly as charged: two to six decimals, never rounded.
String storeUsdcLabel(double v) {
  var s = v.toStringAsFixed(6);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  final dot = s.indexOf('.');
  if (dot < 0) {
    s = '$s.00';
  } else if (s.length - dot - 1 == 1) {
    s = '${s}0';
  }
  return '\$$s';
}

bool _isShortBalance(Object e) =>
    e is ApiException &&
    (e.code == 'INSUFFICIENT_BALANCE' ||
        RegExp('insufficient', caseSensitive: false).hasMatch(e.message));

/// Shows the summary, then the second factor, then funds the escrow.
/// [ask] replaces the second-factor sheet (tests).
Future<StorePayResult> payStoreOrder(
  BuildContext context,
  WidgetRef ref,
  StoreOrderPayment payment, {
  Future<SecondFactor?> Function({
    required SecondFactorKind kind,
    String? errorText,
  })?
  ask,
}) async {
  final total = storeUsdcLabel(payment.totalUsdc);
  final approved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: ref.read(themeProvider).colors.surface,
    builder: (_) => StoreOrderPaySummary(payment: payment),
  );
  if (approved != true || !context.mounted) return StorePayResult.notPaid;

  var short = false;
  final paid = await withSecondFactor<bool>(
    context,
    initial: secondFactorKindFor(ref.read(authProvider).user),
    title: 'Pay $total',
    actionLabel: 'Pay $total',
    detail: 'Held until you get your order.',
    ask: ask,
    attempt: (factor) async {
      final wire = factor.toWire();
      try {
        await ref
            .read(storefrontServiceProvider)
            .fundEscrow(
              escrowId: payment.escrowId,
              totpToken: wire['totpToken'],
              password: wire['password'],
            );
        return true;
      } catch (e) {
        if (_isShortBalance(e)) {
          short = true;
          return false;
        }
        rethrow;
      }
    },
  );
  if (short) return StorePayResult.shortBalance;
  return paid == true ? StorePayResult.paid : StorePayResult.notPaid;
}

/// The order's numbers as the server set them, and the Pay button.
class StoreOrderPaySummary extends ConsumerWidget {
  const StoreOrderPaySummary({super.key, required this.payment});
  final StoreOrderPayment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final total = storeUsdcLabel(payment.totalUsdc);
    TextStyle row({bool strong = false}) => TextStyle(
      color: strong ? colors.textPrimary : colors.textSecondary,
      fontSize: strong ? 16 : 14,
      fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
    );
    Widget line(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: row(strong: strong)),
          ),
          Text(value, style: row(strong: strong)),
        ],
      ),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pay ${payment.storeName}',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (payment.orderRef != null) ...[
              const SizedBox(height: 2),
              Text(
                payment.orderRef!,
                style: TextStyle(color: colors.textTertiary, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 14),
            line(
              payment.itemCount == null
                  ? 'Order'
                  : 'Order · ${payment.itemCount} ${payment.itemCount == 1 ? 'item' : 'items'}',
              storeUsdcLabel(payment.amountUsdc),
            ),
            line('Azaman fee', storeUsdcLabel(payment.feeUsdc)),
            Divider(color: colors.divider, height: 18),
            line('Total', '$total USDC', strong: true),
            const SizedBox(height: 10),
            Text(
              'Paid from your Azaman wallet and held for you. ${payment.storeName} is paid when you tap Got it, '
              'or 3 days after handing the order over if you report no problem.',
              key: const ValueKey('store-pay-held-note'),
              style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            MoneyLockGate(
              compact: true,
              message: 'Unlock to pay',
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  key: const ValueKey('store-pay-confirm'),
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('Pay $total'),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
