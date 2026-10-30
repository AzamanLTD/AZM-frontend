// AZAMAN — BILLS: SAVE A BILL
//
// biller → identifier → GENUINE lookup → the holder name the provider returned
// → confirm → optional alias → save.
//
// The member is never asked to trust a name this app made up. Until a lookup
// comes back, the screen shows no holder, no address and no amount; if the
// lookup says the identifier is unknown, the screen says exactly that and
// leaves the field editable.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/bills/bills_gateway.dart';
import 'package:azaman/services/bills/demo_bills_gateway.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/bills/bills_ui.dart';

class BillsAddAccountScreen extends ConsumerStatefulWidget {
  const BillsAddAccountScreen({super.key, this.categoryId});

  final String? categoryId;

  @override
  ConsumerState<BillsAddAccountScreen> createState() =>
      _BillsAddAccountScreenState();
}

class _BillsAddAccountScreenState extends ConsumerState<BillsAddAccountScreen> {
  final TextEditingController _identifier = TextEditingController();
  final TextEditingController _alias = TextEditingController();

  List<Biller>? _billers;
  Biller? _biller;
  BillLookup? _lookup;

  /// Set when the server says this service has no provider lookup yet. It is a
  /// reason, not an error: the account can still be saved, unverified.
  String? _lookupUnavailable;
  bool _loadingBillers = true;
  bool _looking = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBillers();
  }

  @override
  void dispose() {
    _identifier.dispose();
    _alias.dispose();
    super.dispose();
  }

  Future<void> _loadBillers() async {
    try {
      final list = await ref
          .read(billsGatewayProvider)
          .billers(categoryId: widget.categoryId);
      if (!mounted) return;
      setState(() {
        _billers = list;
        _loadingBillers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingBillers = false;
        _error = 'Those billers are not reachable right now.';
      });
    }
  }

  Future<void> _runLookup() async {
    final biller = _biller;
    final raw = _identifier.text.trim();
    if (biller == null || raw.isEmpty || _looking) return;
    setState(() {
      _looking = true;
      _error = null;
      _lookup = null;
    });
    try {
      final result = await ref
          .read(billsGatewayProvider)
          .lookup(billerId: biller.id, identifier: raw);
      if (!mounted) return;
      setState(() {
        _lookup = result;
        _looking = false;
      });
      HapticFeedback.selectionClick();
    } on BillsUnavailableException catch (e) {
      // The gateway refusing to look up is the truth about this service: no
      // provider is connected. Offering "save unverified" is the honest next
      // step, and the account carries no holder name it did not receive.
      if (!mounted) return;
      setState(() {
        _looking = false;
        _lookup = null;
        _lookupUnavailable =
            e.message ?? 'This biller cannot verify accounts yet.';
      });
    } on BillsLookupNotFoundException {
      if (!mounted) return;
      setState(() {
        _looking = false;
        _error =
            '${biller.name} has no account with that '
            '${biller.identifierLabel.toLowerCase()}. Check it and try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _looking = false;
        _error = "We couldn't reach ${biller.name} just now. Try again.";
      });
    }
  }

  Future<void> _save() async {
    final lookup = _lookup;
    if (lookup == null || _saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(billsGatewayProvider)
          .saveAccount(
            billerId: lookup.billerId,
            identifier: _identifier.text.trim(),
            alias: _alias.text.trim(),
          );
      ref.invalidate(billsHubProvider);
      ref.invalidate(savedBillAccountsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = "We couldn't save that bill. Nothing was charged.";
      });
    }
  }

  /// Saves the reference without a verification step, because the provider
  /// offers none. Nothing about the member's typing is promoted to a holder
  /// name: the server answers with the mask it made.
  Future<void> _saveUnverified() async {
    final biller = _biller;
    final raw = _identifier.text.trim();
    if (biller == null || raw.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(billsGatewayProvider)
          .saveAccount(
            billerId: biller.id,
            identifier: raw,
            alias: _alias.text.trim(),
          );
      ref.invalidate(billsHubProvider);
      ref.invalidate(savedBillAccountsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = "We couldn't save that bill. Nothing was charged.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final isDemo = ref.watch(billsGatewayProvider).isDemo;
    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: colors.scaffoldBackground,
        elevation: 0,
        title: Text(
          'Add a bill',
          style: AzText.title.copyWith(color: colors.textPrimary),
        ),
      ),
      body: _loadingBillers
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
                  _ErrorNote(text: _error!, colors: colors),
                  const SizedBox(height: 16),
                ],

                // ── 1. Which biller ───────────────────────────────────
                BillsSection(
                  title: '1 · BILLER',
                  child: Column(
                    children: [
                      for (final biller in _billers ?? const <Biller>[]) ...[
                        _ChoiceRow(
                          label: biller.name,
                          selected: _biller?.id == biller.id,
                          colors: colors,
                          onTap: () => setState(() {
                            _biller = biller;
                            _lookup = null;
                            _lookupUnavailable = null;
                            _error = null;
                          }),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if ((_billers ?? const []).isEmpty)
                        const BillsEmptyNote(
                          text: 'No billers are reachable right now.',
                        ),
                    ],
                  ),
                ),

                // ── 2. The identifier ─────────────────────────────────
                if (_biller != null)
                  BillsSection(
                    title: '2 · ${_biller!.identifierLabel.toUpperCase()}',
                    child: BillsCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _identifier,
                            enabled: _lookup == null && !_looking,
                            keyboardType: TextInputType.text,
                            textCapitalization: TextCapitalization.characters,
                            style: AzText.body.copyWith(
                              color: colors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              hintText:
                                  _biller!.identifierHint ??
                                  'Enter the '
                                      '${_biller!.identifierLabel.toLowerCase()}',
                              hintStyle: AzText.body.copyWith(
                                color: colors.textTertiary,
                              ),
                            ),
                            onSubmitted: (_) => _runLookup(),
                          ),
                          // Once the server has said this service has no
                          // lookup, offering the button again would just repeat
                          // the same refusal.
                          if (_lookup == null &&
                              _lookupUnavailable == null) ...[
                            const SizedBox(height: 12),
                            BillsPrimaryButton(
                              label: 'Look it up',
                              busy: _looking,
                              onPressed: _runner(_runLookup),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                // ── 3a. No lookup available: save it anyway, unverified ──
                if (_lookup == null &&
                    _lookupUnavailable != null &&
                    _identifier.text.trim().isNotEmpty)
                  BillsSection(
                    title: '3 · SAVE UNVERIFIED',
                    subtitle: _lookupUnavailable,
                    child: Column(
                      children: [
                        const BillsEmptyNote(
                          text:
                              'We can hold this reference for you, but no '
                              'holder name will be shown until the provider '
                              'connects account lookup. Nothing is paid by '
                              'saving.',
                        ),
                        const SizedBox(height: 12),
                        BillsCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'NAME IT (OPTIONAL)',
                                style: AzText.eyebrow.copyWith(
                                  color: colors.textTertiary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _alias,
                                style: AzText.body.copyWith(
                                  color: colors.textPrimary,
                                ),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  hintText: 'My Apartment',
                                  hintStyle: AzText.body.copyWith(
                                    color: colors.textTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        BillsPrimaryButton(
                          label: 'Save without verification',
                          busy: _saving,
                          onPressed: _runner(_saveUnverified),
                        ),
                      ],
                    ),
                  ),

                // ── 3. What the provider said ─────────────────────────
                if (_lookup != null)
                  BillsSection(
                    title: '3 · CONFIRM',
                    subtitle:
                        'This is what ${_lookup!.billerName} returned. Check '
                        'the name before saving.',
                    child: Column(
                      children: [
                        BillsCard(
                          child: Column(
                            children: [
                              BillsKeyValue(
                                label: 'Account holder',
                                value: _lookup!.holderName,
                              ),
                              BillsKeyValue(
                                label: _biller!.identifierLabel,
                                value: _lookup!.identifierMasked,
                              ),
                              BillsKeyValue(
                                label: 'Biller',
                                value: _lookup!.billerName,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        BillsCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'NAME IT (OPTIONAL)',
                                style: AzText.eyebrow.copyWith(
                                  color: colors.textTertiary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _alias,
                                style: AzText.body.copyWith(
                                  color: colors.textPrimary,
                                ),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  hintText: 'My Apartment',
                                  hintStyle: AzText.body.copyWith(
                                    color: colors.textTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        BillsPrimaryButton(
                          label: 'Save this bill',
                          busy: _saving,
                          onPressed: _runner(_save),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                  _lookup = null;
                                  _identifier.clear();
                                }),
                          child: Text(
                            'Not my account — look up another',
                            style: AzText.bodyS.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  /// Wraps an async action so a tap that arrives mid-flight cannot start a
  /// second lookup or a second save.
  VoidCallback _runner(Future<void> Function() action) =>
      () => unawaitedAction(action);
}

/// Local helper: run and swallow, because each action already reports its own
/// failure in place.
void unawaitedAction(Future<void> Function() action) {
  action();
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AzamanColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BillsCard(
      onTap: onTap,
      semanticLabel: selected ? '$label, selected' : label,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AzText.body.copyWith(
                color: colors.textPrimary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (selected)
            Icon(Icons.check_rounded, size: 18, color: colors.success),
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.text, required this.colors});

  final String text;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.danger.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: AzText.bodyS.copyWith(color: colors.danger, height: 1.4),
      ),
    );
  }
}
