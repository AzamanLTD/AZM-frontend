// AZAMAN — BILLS: ASK A CONTACT TO PAY
//
// requester picks a saved bill → names the contact → sees EXACTLY which details
// will be shared → sends.
//
// This is not a request for money: nothing here can debit anyone. The recipient
// gets an invitation to pay that bill from their own balance, using their own
// fresh lookup and their own funds, and can decline. The screen says so plainly
// before sending, because "share my meter number" should never be a surprise.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/bills/bills_gateway.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/bills/bills_ui.dart';

class BillsRequestScreen extends ConsumerStatefulWidget {
  /// When [requestId] is given the screen opens an existing request instead of
  /// composing a new one.
  const BillsRequestScreen({super.key, this.requestId});

  final String? requestId;

  @override
  ConsumerState<BillsRequestScreen> createState() => _BillsRequestScreenState();
}

class _BillsRequestScreenState extends ConsumerState<BillsRequestScreen> {
  final TextEditingController _recipient = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();

  List<SavedBillAccount>? _accounts;
  SavedBillAccount? _account;
  BillPaymentRequest? _existing;
  bool _loading = true;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _recipient.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final gateway = ref.read(billsGatewayProvider);
      if (widget.requestId != null) {
        final all = await gateway.requests();
        final match = all.where((r) => r.id == widget.requestId);
        if (!mounted) return;
        setState(() {
          _existing = match.isEmpty ? null : match.first;
          _loading = false;
          if (match.isEmpty) {
            _error = 'That request is no longer available.';
          }
        });
        return;
      }
      final accounts = await gateway.savedAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "We couldn't load your saved bills just now.";
      });
    }
  }

  Future<void> _send() async {
    final account = _account;
    if (account == null || _sending) return;
    final who = _recipient.text.trim();
    if (who.isEmpty) {
      setState(() => _error = 'Choose who to ask first.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(billsGatewayProvider)
          .sendRequest(
            accountId: account.id,
            recipientName: who,
            amount: double.tryParse(_amount.text.trim()),
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      ref.invalidate(billsHubProvider);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = "We couldn't send that request. Nothing was shared.";
      });
    }
  }

  Future<void> _respond(bool accept) async {
    final existing = _existing;
    if (existing == null) return;
    setState(() => _sending = true);
    try {
      final updated = await ref
          .read(billsGatewayProvider)
          .respondToRequest(requestId: existing.id, accept: accept);
      ref.invalidate(billsHubProvider);
      if (!mounted) return;
      setState(() {
        _existing = updated;
        _sending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = "We couldn't record that answer. Nothing changed.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final isDemo = ref.watch(billsGatewayProvider).isDemo;
    final title = widget.requestId != null ? 'A bill to pay' : 'Ask to pay';

    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: colors.scaffoldBackground,
        elevation: 0,
        title: Text(
          title,
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
                if (isDemo) const BillsDemoBanner(),
                if (_error != null) ...[
                  BillsEmptyNote(icon: HugeIconsSolid.alert01, text: _error!),
                  const SizedBox(height: 16),
                ],
                if (widget.requestId != null)
                  _existingDetail(colors)
                else if (_sent)
                  _sentState(colors)
                else
                  ..._compose(colors),
              ],
            ),
    );
  }

  List<Widget> _compose(AzamanColors colors) {
    final accounts = _accounts ?? const <SavedBillAccount>[];
    if (accounts.isEmpty) {
      return [
        const BillsSection(
          title: 'SAVED BILLS',
          child: BillsEmptyNote(
            text: 'Save a bill first — then you can ask someone to pay it.',
          ),
        ),
      ];
    }
    return [
      BillsSection(
        title: '1 · WHICH BILL',
        child: Column(
          children: [
            for (final account in accounts) ...[
              BillsAccountTile(
                title: account.displayName,
                subtitle: account.billerName,
                maskedIdentifier: account.identifierMasked,
                trailing: _account?.id == account.id
                    ? Icon(Icons.check_rounded, size: 18, color: colors.success)
                    : null,
                onTap: () => setState(() => _account = account),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      BillsSection(
        title: '2 · WHO TO ASK',
        child: BillsCard(
          child: TextField(
            controller: _recipient,
            style: AzText.body.copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: 'Azaman username',
              hintStyle: AzText.bodyS.copyWith(color: colors.textTertiary),
            ),
          ),
        ),
      ),
      BillsSection(
        title: '3 · DETAILS (OPTIONAL)',
        child: Column(
          children: [
            BillsCard(
              child: Column(
                children: [
                  TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: AzText.body.copyWith(color: colors.textPrimary),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: 'Amount, if you want to suggest one',
                      hintStyle: AzText.bodyS.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                  const Divider(height: 20),
                  TextField(
                    controller: _note,
                    maxLines: 2,
                    style: AzText.body.copyWith(color: colors.textPrimary),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: 'A note',
                      hintStyle: AzText.bodyS.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (_account != null)
        BillsSection(
          title: 'THIS IS WHAT THEY SEE',
          subtitle:
              'They get an invitation to pay it themselves. They cannot take '
              'money from you, and they can decline.',
          child: BillsCard(
            child: Column(
              children: [
                BillsKeyValue(label: 'Bill', value: _account!.displayName),
                BillsKeyValue(label: 'Biller', value: _account!.billerName),
                BillsKeyValue(
                  label: 'Account holder',
                  value:
                      _account!.holderName ??
                      'Not returned by the provider yet',
                ),
                BillsKeyValue(
                  label: 'Account',
                  value: _account!.identifierMasked,
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 14),
      BillsPrimaryButton(
        label: 'Send the request',
        busy: _sending,
        onPressed: _account == null ? null : _send,
      ),
    ];
  }

  Widget _sentState(AzamanColors colors) => BillsSection(
    title: 'SENT',
    child: Column(
      children: [
        BillsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(HugeIconsSolid.clock01, size: 18, color: colors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Waiting for an answer',
                      style: AzText.title.copyWith(color: colors.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Nothing has been paid. ${_recipient.text.trim()} sees the '
                'bill and pays it from their own balance if they accept.',
                style: AzText.bodyS.copyWith(
                  color: colors.textSecondary,
                  height: 1.45,
                ),
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

  Widget _existingDetail(AzamanColors colors) {
    final request = _existing;
    if (request == null) {
      return const BillsEmptyNote(text: 'That request is not available.');
    }
    return BillsSection(
      title: request.isIncoming ? 'THEY ASKED YOU' : 'YOU ASKED THEM',
      child: Column(
        children: [
          BillsCard(
            child: Column(
              children: [
                BillsKeyValue(label: 'Bill', value: request.displayName),
                BillsKeyValue(label: 'Biller', value: request.billerName),
                BillsKeyValue(
                  label: 'Account',
                  value: request.identifierMasked,
                ),
                BillsKeyValue(label: 'From', value: request.counterpartyName),
                if (request.amount != null)
                  BillsKeyValue(
                    label: 'Suggested amount',
                    value:
                        '${request.amount!.toStringAsFixed(2)} '
                        '${request.currency}',
                  ),
                if (request.note != null)
                  BillsKeyValue(label: 'Note', value: request.note!),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (request.isIncoming && request.state == BillRequestState.pending)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _sending ? null : () => _respond(false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      side: BorderSide(color: colors.divider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Decline',
                      style: AzText.button.copyWith(color: colors.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: BillsPrimaryButton(
                    label: 'Pay it myself',
                    busy: _sending,
                    onPressed: () => _respond(true),
                  ),
                ),
              ],
            )
          else
            Text(
              _stateWords(request.state),
              style: AzText.bodyS.copyWith(color: colors.textSecondary),
            ),
        ],
      ),
    );
  }

  String _stateWords(BillRequestState state) => switch (state) {
    BillRequestState.pending => 'Waiting for an answer.',
    BillRequestState.acceptedAwaitingPayment =>
      'Accepted — the payer still has to pay it.',
    BillRequestState.paid => 'Paid.',
    BillRequestState.failed => 'The payment failed.',
    BillRequestState.declined => 'Declined.',
    BillRequestState.cancelled => 'Cancelled.',
    BillRequestState.expired => 'Expired.',
  };
}
