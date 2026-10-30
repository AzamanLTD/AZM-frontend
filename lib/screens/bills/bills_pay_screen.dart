// AZAMAN — BILLS: PAY A BILL
//
// saved account → amount (only when the provider does not state one) → FRESH
// QUOTE → review the account identity, the amount, the fee, the total and the
// expiry → explicit confirm → the provider's own terminal state.
//
// The honesty rules this screen is built around:
//   • the total is the quote's total; this file never adds a fee itself;
//   • the quote is fetched AGAIN at confirm, so an expired price is never paid;
//   • "pending"/"processing"/"unconfirmed" are never dressed up as paid, and a
//     lost answer is reported as "we do not know" rather than as success;
//   • a receipt shows only the reference or token that really came back.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/bills/bills_gateway.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/bills/bills_ui.dart';

class BillsPayScreen extends ConsumerStatefulWidget {
  const BillsPayScreen({super.key, required this.accountId});

  final String accountId;

  @override
  ConsumerState<BillsPayScreen> createState() => _BillsPayScreenState();
}

class _BillsPayScreenState extends ConsumerState<BillsPayScreen> {
  final TextEditingController _amount = TextEditingController();

  SavedBillAccount? _account;
  BillQuote? _quote;
  BillPaymentReceipt? _receipt;
  bool _loading = true;
  bool _quoting = false;
  bool _paying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final accounts = await ref.read(billsGatewayProvider).savedAccounts();
      final match = accounts.where((a) => a.id == widget.accountId);
      if (!mounted) return;
      if (match.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'That saved bill is no longer on your account.';
        });
        return;
      }
      setState(() {
        _account = match.first;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "We couldn't open that bill just now.";
      });
    }
  }

  Future<void> _requestQuote({double? amount}) async {
    final account = _account;
    if (account == null || _quoting) return;
    setState(() {
      _quoting = true;
      _error = null;
    });
    try {
      final quote = await ref
          .read(billsGatewayProvider)
          .quote(accountId: account.id, amount: amount);
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _quoting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _quoting = false;
        _error = "We couldn't get a price from ${account.billerName} just now.";
      });
    }
  }

  Future<void> _confirm() async {
    final quote = _quote;
    if (quote == null || _paying) return;
    setState(() {
      _paying = true;
      _error = null;
    });

    // A quote has a life. Re-quote at the moment of payment so a member is
    // never charged a price they did not see, and never pays a stale one.
    if (quote.isExpiredAt(DateTime.now())) {
      setState(() => _paying = false);
      await _requestQuote(
        amount: quote.amountDueIsAuthoritative ? null : quote.amount,
      );
      if (!mounted) return;
      setState(() {
        _error =
            'That price expired, so we fetched a fresh one. Check the '
            'total and confirm again.';
      });
      return;
    }

    try {
      final receipt = await ref
          .read(billsGatewayProvider)
          .pay(quoteId: quote.quoteId);
      ref.invalidate(billsHubProvider);
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _paying = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _paying = false;
        // No answer is not a success and not a failure: say which.
        _error =
            "We didn't get an answer from ${quote.billerName}. The "
            'payment may still be processing — check Recently paid before '
            'trying again, so you do not pay twice.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final account = _account;
    final receipt = _receipt;

    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: colors.scaffoldBackground,
        elevation: 0,
        title: Text(
          receipt != null ? 'Result' : 'Pay a bill',
          style: AzText.title.copyWith(color: colors.textPrimary),
        ),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: colors.mutedAccent,
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                if (_error != null) ...[
                  BillsEmptyNote(icon: HugeIconsSolid.alert01, text: _error!),
                  const SizedBox(height: 16),
                ],
                if (receipt != null)
                  _Receipt(receipt: receipt, colors: colors)
                else if (account != null) ...[
                  BillsSection(
                    title: 'PAYING',
                    child: BillsCard(
                      child: Column(
                        children: [
                          BillsKeyValue(
                            label: 'Bill',
                            value: account.displayName,
                          ),
                          BillsKeyValue(
                            label: 'Biller',
                            value: account.billerName,
                          ),
                          BillsKeyValue(
                            label: 'Account holder',
                            value:
                                account.holderName ??
                                'Not returned by the provider yet',
                          ),
                          BillsKeyValue(
                            label: 'Account',
                            value: account.identifierMasked,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_quote == null)
                    BillsSection(
                      title: 'AMOUNT',
                      subtitle:
                          'We ask the biller what is owed, then show you '
                          'the exact total before anything moves.',
                      child: Column(
                        children: [
                          BillsCard(
                            child: TextField(
                              controller: _amount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: AzText.body.copyWith(
                                color: colors.textPrimary,
                              ),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                hintText: 'Leave blank to use the amount due',
                                hintStyle: AzText.bodyS.copyWith(
                                  color: colors.textTertiary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          BillsPrimaryButton(
                            label: 'Get the price',
                            busy: _quoting,
                            onPressed: () {
                              final parsed = double.tryParse(
                                _amount.text.trim(),
                              );
                              _requestQuote(amount: parsed);
                            },
                          ),
                        ],
                      ),
                    )
                  else
                    _QuoteReview(
                      quote: _quote!,
                      colors: colors,
                      busy: _paying,
                      onConfirm: _confirm,
                      onRefresh: () => _requestQuote(
                        amount: _quote!.amountDueIsAuthoritative
                            ? null
                            : _quote!.amount,
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class _QuoteReview extends StatelessWidget {
  const _QuoteReview({
    required this.quote,
    required this.colors,
    required this.busy,
    required this.onConfirm,
    required this.onRefresh,
  });

  final BillQuote quote;
  final AzamanColors colors;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return BillsSection(
      title: 'REVIEW',
      subtitle: 'Confirm the account and the exact total.',
      child: Column(
        children: [
          BillsCard(
            child: Column(
              children: [
                BillsKeyValue(label: 'Account holder', value: quote.holderName),
                BillsKeyValue(label: 'Account', value: quote.identifierMasked),
                BillsKeyValue(
                  label: quote.amountDueIsAuthoritative
                      ? 'Amount due'
                      : 'Amount',
                  value: '${quote.amount.toStringAsFixed(2)} ${quote.currency}',
                ),
                BillsKeyValue(
                  label: 'Fee',
                  value:
                      '${quote.feeAmount.toStringAsFixed(2)} '
                      '${quote.currency}',
                ),
                const Divider(height: 20),
                BillsKeyValue(
                  label: 'Total',
                  value:
                      '${quote.totalAmount.toStringAsFixed(2)} '
                      '${quote.currency}',
                  emphasised: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 14,
                color: colors.textTertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'This price holds until '
                  '${_clock(quote.expiresAt)}. We check again when you '
                  'confirm.',
                  style: AzText.caption.copyWith(color: colors.textTertiary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          BillsPrimaryButton(
            label:
                'Pay ${quote.totalAmount.toStringAsFixed(2)} '
                '${quote.currency}',
            busy: busy,
            onPressed: onConfirm,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: busy ? null : onRefresh,
            child: Text(
              'Get a fresh price',
              style: AzText.bodyS.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Receipt extends StatelessWidget {
  const _Receipt({required this.receipt, required this.colors});

  final BillPaymentReceipt receipt;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    // The four non-paid states say what they are. Only `paid` gets the word.
    final (headline, body, tint) = switch (receipt.state) {
      BillPaymentState.paid => (
        'Paid',
        '${receipt.billerName} confirmed the payment.',
        colors.success,
      ),
      BillPaymentState.pending => (
        'Pending',
        '${receipt.billerName} has your payment but has not confirmed it yet. '
            'This is not a completed payment.',
        colors.warning,
      ),
      BillPaymentState.processing => (
        'Processing',
        'Your payment is on its way to ${receipt.billerName}. Nothing is '
            'confirmed yet.',
        colors.warning,
      ),
      BillPaymentState.failed => (
        'Not paid',
        receipt.failureReason ??
            '${receipt.billerName} rejected the payment. Nothing was charged '
                'by us.',
        colors.danger,
      ),
      BillPaymentState.unknown => (
        'We could not confirm',
        'The answer never reached us. The payment may still complete — check '
            'Recently paid before paying again.',
        colors.warning,
      ),
    };

    return BillsSection(
      title: 'PAYMENT',
      child: Column(
        children: [
          BillsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      receipt.isPaid
                          ? HugeIconsSolid.checkmarkCircle02
                          : HugeIconsSolid.clock01,
                      size: 18,
                      color: tint,
                    ),
                    const SizedBox(width: 8),
                    // A long honest verdict ("We could not confirm") must wrap,
                    // not overflow: this row is the payment's entire answer.
                    Expanded(
                      child: Text(
                        headline,
                        style: AzText.title.copyWith(color: tint),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  body,
                  style: AzText.bodyS.copyWith(
                    color: colors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const Divider(height: 22),
                BillsKeyValue(label: 'Biller', value: receipt.billerName),
                BillsKeyValue(
                  label: 'Account',
                  value: receipt.identifierMasked,
                ),
                BillsKeyValue(
                  label: 'Total',
                  value:
                      '${receipt.totalAmount.toStringAsFixed(2)} '
                      '${receipt.currency}',
                ),
                if (receipt.reference != null)
                  BillsKeyValue(label: 'Reference', value: receipt.reference!),
                if (receipt.token != null)
                  BillsKeyValue(label: 'Token', value: receipt.token!),
                if (receipt.receiptUrl != null)
                  BillsKeyValue(label: 'Receipt', value: receipt.receiptUrl!),
                if (receipt.settledAt != null)
                  BillsKeyValue(
                    label: 'Confirmed',
                    value: _clock(receipt.settledAt!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          BillsPrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }
}

String _clock(DateTime time) {
  final local = time.toLocal();
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final m = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour < 12 ? 'am' : 'pm';
  return '$h:$m $suffix';
}
