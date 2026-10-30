// AZAMAN — BILLS (Hub)
//
// The Home Bills bubble lands here. What this screen can offer is decided by
// the SERVER, not by this file: a biller catalogue that the backend reports it
// can actually reach, and nothing invented when it reports none.
//
// The Hub is a real page, not a placeholder: saved accounts, find a biller,
// recently paid, requests received and sent. Each section is driven by
// [billsHubProvider], so when the HTTP gateway lands nothing here changes — a
// section simply stops being empty. A failed read is shown as a failed read,
// never as "you have no bills".
//
// Deliberately NOT done here: no hardcoded billers from a provider's published
// guide, no sample accounts, no sample amounts, no placeholder "recent
// payments", no outstanding claim the server did not make.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/services/bills/bills_gateway.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/bills/bills_ui.dart';
import 'package:azaman/widgets/home/money_lock_surface.dart';

class BillsHomeScreen extends ConsumerStatefulWidget {
  const BillsHomeScreen({super.key});

  @override
  ConsumerState<BillsHomeScreen> createState() => _BillsHomeScreenState();
}

class _BillsHomeScreenState extends ConsumerState<BillsHomeScreen> {
  late Future<BillsAvailability> _availability;

  @override
  void initState() {
    super.initState();
    _availability = ref.read(billsGatewayProvider).availability();
  }

  Future<void> _refresh() async {
    setState(() {
      _availability = ref.read(billsGatewayProvider).availability();
    });
    ref.invalidate(billsHubProvider);
    ref.invalidate(savedBillAccountsProvider);
    await _availability;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final gateway = ref.watch(billsGatewayProvider);
    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: colors.scaffoldBackground,
        elevation: 0,
        title: Text(
          'Bills',
          style: AzText.title.copyWith(color: colors.textPrimary),
        ),
      ),
      body: FutureBuilder<BillsAvailability>(
        future: _availability,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: colors.mutedAccent,
              ),
            );
          }
          if (snapshot.hasError ||
              snapshot.data == null ||
              !snapshot.data!.isAvailable) {
            return _UnavailableState(colors: colors);
          }
          return _AvailableState(
            availability: snapshot.data!,
            colors: colors,
            isDemo: gateway.isDemo,
            onRefresh: _refresh,
          );
        },
      ),
    );
  }
}

/// The honest state. It says what is true, offers no dead ends, and invents
/// nothing.
class _UnavailableState extends StatelessWidget {
  const _UnavailableState({required this.colors});

  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.textTertiary, width: 1),
            ),
            child: Icon(
              HugeIconsSolid.invoice01,
              size: 30,
              color: colors.mutedAccent,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Bill payments are not available yet',
            textAlign: TextAlign.center,
            style: AzText.title.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 10),
          Text(
            'Electricity, water, television and internet billers appear here '
            'once we can pay them. Nothing is charged, and nothing can be '
            'paid, until then.',
            textAlign: TextAlign.center,
            style: AzText.body.copyWith(
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reachable billers and the member's own bills, exactly as the server reports
/// them.
class _AvailableState extends ConsumerStatefulWidget {
  const _AvailableState({
    required this.availability,
    required this.colors,
    required this.isDemo,
    required this.onRefresh,
  });

  final BillsAvailability availability;
  final AzamanColors colors;
  final bool isDemo;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_AvailableState> createState() => _AvailableStateState();
}

class _AvailableStateState extends ConsumerState<_AvailableState> {
  /// True only when some saved bill could actually be PAID, since that is what
  /// asking a contact leads to. No published service carries the payment
  /// capability yet, so in production this is false and the section is a plan
  /// rather than an entry point to a flow that cannot finish.
  bool get _canAskAContact {
    final accounts =
        ref.watch(billsHubProvider).valueOrNull?.savedAccounts ??
        const <SavedBillAccount>[];
    return accounts.any((a) => a.canPay);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final hub = ref.watch(billsHubProvider);

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        children: [
          if (widget.isDemo) const BillsDemoBanner(),

          // ── The member's own bills ────────────────────────────────────
          MoneyLockGate(
            message: 'Your saved bills are locked',
            hint: 'Tap the Azaman button on Home to unlock.',
            child: BillsSection(
              title: 'YOUR BILLS',
              child: hub.when(
                loading: () => _Loading(colors: colors),
                error: (_, _) => BillsEmptyNote(
                  icon: HugeIconsSolid.wifiError01,
                  text:
                      "We couldn't load your bills just now. That is not the "
                      'same as having none — pull down to try again.',
                ),
                data: (snapshot) {
                  if (snapshot.savedAccounts.isEmpty) {
                    return BillsEmptyNote(
                      icon: HugeIconsSolid.note01,
                      text:
                          'No saved bills yet. Find a biller below, we look up '
                          'the account with them, then it lives here.',
                    );
                  }
                  return Column(
                    children: [
                      for (final account in snapshot.savedAccounts) ...[
                        BillsAccountTile(
                          title: account.displayName,
                          subtitle: account.billerName,
                          maskedIdentifier: account.identifierMasked,
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: colors.textTertiary,
                          ),
                          onTap: () => context.push(
                            '${AzRoutes.bills}/pay/${account.id}',
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),

          // ── Find a biller ─────────────────────────────────────────────
          BillsSection(
            title: 'FIND A BILLER',
            child: Column(
              children: [
                for (final category in widget.availability.categories) ...[
                  _CategoryRow(
                    category: category,
                    colors: colors,
                    onTap: category.billerCount == 0
                        ? null
                        : () => context.push(
                            '${AzRoutes.bills}/add?category=${category.id}',
                          ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),

          // ── Outstanding, only when the server claims it ───────────────
          if (hub.valueOrNull != null &&
              hub.valueOrNull!.outstanding.isNotEmpty)
            BillsSection(
              title: 'DUE NOW',
              child: Column(
                children: [
                  for (final account in hub.valueOrNull!.outstanding) ...[
                    BillsAccountTile(
                      title: account.displayName,
                      subtitle: 'Payment due',
                      maskedIdentifier: account.identifierMasked,
                      onTap: () =>
                          context.push('${AzRoutes.bills}/pay/${account.id}'),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),

          // ── Requests from contacts ────────────────────────────────────
          BillsSection(
            title: 'REQUESTS',
            subtitle: 'A contact can ask you to pay a bill they saved.',
            child: hub.when(
              loading: () => _Loading(colors: colors),
              error: (_, _) =>
                  BillsEmptyNote(text: "We couldn't load requests just now."),
              data: (snapshot) {
                if (snapshot.requests.isEmpty) {
                  return BillsEmptyNote(
                    icon: HugeIconsSolid.userCheck01,
                    text: 'Nothing waiting on you.',
                  );
                }
                return Column(
                  children: [
                    for (final request in snapshot.requests) ...[
                      _RequestRow(
                        request: request,
                        colors: colors,
                        onTap: () => context.push(
                          '${AzRoutes.bills}/request/${request.id}',
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
          ),

          // ── Recently paid ─────────────────────────────────────────────
          BillsSection(
            title: 'RECENTLY PAID',
            child: hub.when(
              loading: () => _Loading(colors: colors),
              error: (_, _) => BillsEmptyNote(
                text: "We couldn't load your receipts just now.",
              ),
              data: (snapshot) {
                if (snapshot.recentPayments.isEmpty) {
                  return BillsEmptyNote(
                    icon: HugeIconsSolid.invoice01,
                    text:
                        'Payments you make will show here with the '
                        "provider's own reference.",
                  );
                }
                return Column(
                  children: [
                    for (final receipt in snapshot.recentPayments) ...[
                      _ReceiptRow(receipt: receipt, colors: colors),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
          ),

          // ── Ask someone to pay ────────────────────────────────────────
          BillsSection(
            title: 'ASK A CONTACT TO PAY',
            child: BillsCard(
              onTap: _canAskAContact
                  ? () => context.push('${AzRoutes.bills}/request')
                  : null,
              semanticLabel: 'Ask a contact to pay a saved bill',
              child: Row(
                children: [
                  Icon(
                    HugeIconsSolid.share08,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _canAskAContact
                          ? 'Pick a saved bill, choose who to ask, and they '
                                'pay it from their own balance.'
                          : 'Coming later. Asking a contact to pay needs the '
                                'payment routes, which are not connected yet.',
                      style: AzText.bodyS.copyWith(
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.colors,
    required this.onTap,
  });

  final BillsCategory category;
  final AzamanColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final reachable = category.billerCount > 0;
    return BillsCard(
      onTap: onTap,
      semanticLabel: reachable
          ? '${category.label}, ${category.billerCount} billers'
          : '${category.label}, not available yet',
      child: Row(
        children: [
          Expanded(
            child: Text(
              category.label,
              style: AzText.body.copyWith(
                color: reachable ? colors.textPrimary : colors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            reachable ? '${category.billerCount}' : 'Soon',
            style: AzText.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.colors,
    required this.onTap,
  });

  final BillPaymentRequest request;
  final AzamanColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final who = request.isIncoming
        ? '${request.counterpartyName} asked you'
        : 'You asked ${request.counterpartyName}';
    return BillsCard(
      onTap: onTap,
      semanticLabel:
          '$who to pay ${request.displayName}, '
          '${_requestStateLabel(request.state)}',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.displayName,
                  style: AzText.body.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$who · ${request.identifierMasked}',
                  style: AzText.caption.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
          Text(
            _requestStateLabel(request.state),
            style: AzText.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

String _requestStateLabel(BillRequestState state) {
  switch (state) {
    case BillRequestState.pending:
      return 'Waiting';
    case BillRequestState.acceptedAwaitingPayment:
      return 'Sent to pay';
    case BillRequestState.paid:
      return 'Paid';
    case BillRequestState.failed:
      return 'Failed';
    case BillRequestState.declined:
      return 'Declined';
    case BillRequestState.cancelled:
      return 'Cancelled';
    case BillRequestState.expired:
      return 'Expired';
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.receipt, required this.colors});

  final BillPaymentReceipt receipt;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    // Only a provider-completed payment is called paid; anything else states
    // what it is, in its own words.
    final label = switch (receipt.state) {
      BillPaymentState.paid => 'Paid',
      BillPaymentState.pending => 'Pending',
      BillPaymentState.processing => 'Processing',
      BillPaymentState.failed => 'Failed',
      BillPaymentState.unknown => 'Unconfirmed',
    };
    return BillsCard(
      semanticLabel:
          '${receipt.billerName}, $label, '
          '${receipt.totalAmount.toStringAsFixed(2)} ${receipt.currency}',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  receipt.billerName,
                  style: AzText.body.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  receipt.reference ?? receipt.identifierMasked,
                  style: AzText.caption.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${receipt.totalAmount.toStringAsFixed(2)} ${receipt.currency}',
                style: AzText.bodyS.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AzText.caption.copyWith(
                  color: receipt.state == BillPaymentState.failed
                      ? colors.danger
                      : colors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.colors});

  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.mutedAccent,
          ),
        ),
      ),
    );
  }
}
