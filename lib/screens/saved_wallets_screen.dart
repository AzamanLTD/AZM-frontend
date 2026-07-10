// =============================================================================
// AZAMAN — WITHDRAWAL ADDRESSES (a.k.a. Saved Wallets)
//
// CRITICAL DESIGN RULE (Phase UI-1 + UI-2, 2026-05-26):
//
//   This screen is for SAVING PAYOUT DESTINATIONS only — i.e. "where do I
//   want Azaman to send my money when I withdraw?". Two categories are
//   permitted, NOTHING ELSE:
//
//     1. Local Mobile Money — MTN MoMo, Telecel Cash, AirtelTigo,
//                             Telecel Cash.
//     2. Crypto Wallets     — Polygon USDC addresses, Binance Pay IDs,
//                             TRC20 USDT, ERC20/BEP20 USDC.
//
//   FORBIDDEN HERE: global fiat trade accounts. Specifically, the
//   following 11 method types from `tradeAccountValidation.js` MUST NEVER
//   appear in this screen, because they are vendor-side ad-receipt handles
//   used to receive payment from buyers on P2P ads — NOT user payout
//   destinations:
//     • Zelle, CashApp, Venmo, PayPal, Apple Pay, Google Pay, Wise,
//       Revolut, Gift Cards, Western Union, Wire Transfer.
//   Those live exclusively under the Vendor Dashboard → MANAGE TRADE
//   ACCOUNTS button (`trade_accounts_screen.dart`), on a different
//   table (`TradeAccount`).
//
//   The previous version of this screen mixed both, which produced a
//   surface that looked like Withdrawal Addresses but actually managed
//   trade accounts. This rewrite enforces the split end-to-end:
//   - Add-form options are exclusively MoMo / Telecel / Crypto.
//   - Server response is filtered: any legacy `network='FIAT_ACCOUNT'`
//     row, or any row whose `provider` matches a global-fiat label, is
//     hidden so old conflated rows don't leak in.
//
// Backend contract: GET / POST / DELETE /api/wallet/saved.
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/saved_momo_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/azaman_button.dart';


class SavedWalletsScreen extends ConsumerStatefulWidget {
  const SavedWalletsScreen({super.key});

  @override
  ConsumerState<SavedWalletsScreen> createState() =>
      _SavedWalletsScreenState();
}

enum _Bucket { mobileMoney, crypto }

class _SavedWalletsScreenState extends ConsumerState<SavedWalletsScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  List<dynamic> _wallets = const [];
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchSavedWallets();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchSavedWallets() async {
    setState(() => _isLoading = true);
    try {
      // Master Sprint v2 (2026-05-27): merge entries from both backing
      // tables so this single screen shows every saved address —
      // legacy SavedWallet rows + new SavedMomoAccount rows.
      final results = await Future.wait([
        apiClient.get('/wallet/saved'),
        apiClient.get('/saved-momo'),
      ]);
      final merged = <Map<String, dynamic>>[];
      // Legacy SavedWallet rows
      if (results[0].statusCode == 200) {
        final data = jsonDecode(results[0].body);
        final list = (data['wallets'] as List? ?? [])
            .map((w) => Map<String, dynamic>.from(w as Map))
            .where(_isValidPayoutWallet)
            .toList();
        merged.addAll(list);
      }
      // New SavedMomoAccount rows — projected into the legacy shape
      if (results[1].statusCode == 200) {
        final data = jsonDecode(results[1].body) as Map<String, dynamic>;
        final accounts = data['accounts'] as List<dynamic>? ?? const [];
        for (final raw in accounts) {
          final a = raw as Map<String, dynamic>;
          final providerLegacy = switch (a['provider']) {
            'MTN' => 'MTN_MOMO',
            'VODAFONE' => 'TELECEL_CASH', // legacy mapping
            'TELECEL' => 'TELECEL_CASH',
            'TELECEL' => 'AIRTELTIGO',
            _ => 'MTN_MOMO',
          };
          merged.add({
            'id': 'momo:${a['id']}',
            'label': a['nickname'] ?? '',
            'address': a['phoneNumber'] ?? '',
            'network': providerLegacy,
            'provider': a['provider'] ?? '',
            'accountName': a['accountName'],
            'createdAt': a['createdAt'],
            // Synthetic flag so the delete handler can route to the right
            // backend endpoint (DELETE /saved-momo/:id vs /wallet/saved/:id).
            '_source': 'savedMomo',
          });
        }
      }
      // De-dup by address — same number stored in both tables shows once.
      final seen = <String>{};
      final unique = <Map<String, dynamic>>[];
      for (final w in merged) {
        final addr = (w['address'] ?? '').toString();
        if (addr.isEmpty) {
          unique.add(w);
          continue;
        }
        if (seen.add(addr)) unique.add(w);
      }
      if (mounted) {
        setState(() {
          _wallets = unique;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isValidPayoutWallet(dynamic w) {
    final network = (w['network'] ?? '').toString().toUpperCase();
    final provider = (w['provider'] ?? '').toString().toUpperCase();
    final type = (w['type'] ?? '').toString().toUpperCase();

    // BLOCKLIST FIRST: explicit reject for the 11 global-fiat trade
    // account types. Even if a legacy row somehow has a `network` value
    // that would otherwise pass the allow-list, we never let one of
    // these surface here. They belong in TradeAccount, not SavedWallet.
    const blocked = {
      'ZELLE',
      'CASHAPP',
      'CASH APP',
      'VENMO',
      'PAYPAL',
      'APPLE PAY',
      'APPLEPAY',
      'GOOGLE PAY',
      'GOOGLEPAY',
      'WISE',
      'REVOLUT',
      'GIFT CARD',
      'GIFT CARDS',
      'WESTERN UNION',
      'WIRE TRANSFER',
      'FIAT_ACCOUNT',
    };
    if (blocked.contains(network) ||
        blocked.contains(provider) ||
        blocked.contains(type)) {
      return false;
    }

    // ALLOW LIST: anything that's a recognised mobile-money network or a
    // recognised crypto network. Anything else (UNKNOWN, miscategorised
    // legacy rows) is hidden.
    const allowed = {
      'MTN_MOMO', 'TELECEL_CASH', 'AIRTELTIGO',
      'BINANCE_ID', 'TRC20', 'ERC20_BEP20', 'POLYGON',
    };
    if (allowed.contains(network)) return true;
    // Provider-based fallback for older rows that don't set `network`.
    const allowedProviders = {
      'MTN MOMO', 'TELECEL CASH', 'AIRTELTIGO',
      'BINANCE PAY', 'EXTERNAL WALLET',
    };
    return allowedProviders.contains(provider);
  }

  bool _isCrypto(dynamic w) {
    final network = (w['network'] ?? '').toString().toUpperCase();
    return network == 'BINANCE_ID' ||
        network == 'TRC20' ||
        network == 'ERC20_BEP20' ||
        network == 'POLYGON';
  }

  Future<void> _delete(dynamic w) async {
    HapticFeedback.mediumImpact();
    final rawId = w['id'].toString();
    final colors = ref.read(themeProvider).colors;
    try {
      // Master Sprint v2: route to the right backend depending on which
      // table the row came from. Synthetic 'momo:UUID' ids point at the
      // new SavedMomoAccount endpoint; legacy numeric ids stay on the
      // original /wallet/saved/:id route.
      final res = rawId.startsWith('momo:')
          ? await apiClient.delete('/saved-momo/${rawId.substring(5)}')
          : await apiClient.delete('/wallet/saved/$rawId');
      if (res.statusCode == 200) {
        await _fetchSavedWallets();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Removed'),
            backgroundColor: colors.success,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (_) {/* swallow */}
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final mobileMoney = _wallets.where((w) => !_isCrypto(w)).toList();
    final crypto = _wallets.where((w) => _isCrypto(w)).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Withdrawal Addresses',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: colors.accent, size: 24),
            onPressed: () => _showAddSheet(colors),
          ),
        ],
      ),
      body: Column(
        children: [
          _SegmentedTabs(
            controller: _tabController,
            colors: colors,
            labels: const ['Mobile Money', 'Crypto'],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              'Where Azaman sends your money when you withdraw. '
              'Global fiat handles (Zelle, CashApp, etc.) live in the '
              'Vendor Dashboard\u2019s Trade Accounts area, not here.',
              style: TextStyle(color: colors.textTertiary, fontSize: 11.5),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _isLoading
                ? Center(
                    child:
                        CircularProgressIndicator(color: colors.accent))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildList(mobileMoney, colors, isCrypto: false),
                      _buildList(crypto, colors, isCrypto: true),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<dynamic> items, AzamanColors colors,
      {required bool isCrypto}) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isCrypto
                    ? Icons.currency_bitcoin
                    : Icons.smartphone_outlined,
                size: 44,
                color: colors.textTertiary,
              ),
              const SizedBox(height: 10),
              Text(
                isCrypto
                    ? 'No crypto payout wallets yet'
                    : 'No mobile money accounts yet',
                style:
                    TextStyle(color: colors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                'Tap + to add one.',
                style:
                    TextStyle(color: colors.textTertiary, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final w = items[i];
        return _WalletTile(
          wallet: w,
          colors: colors,
          isCrypto: isCrypto,
          onDelete: () => _delete(w),
        );
      },
    );
  }

  // ── Add sheet ─────────────────────────────────────────────────────────────
  void _showAddSheet(AzamanColors colors) {
    AddPayoutSheet.show(
      context,
      onSaved: _fetchSavedWallets,
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  final TabController controller;
  final AzamanColors colors;
  final List<String> labels;

  const _SegmentedTabs({
    required this.controller,
    required this.colors,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          color: colors.accent,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: colors.isDark ? Colors.black : Colors.white,
        unselectedLabelColor: colors.textSecondary,
        labelStyle: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.4),
        unselectedLabelStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        dividerColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        tabs: labels.map((l) => Tab(height: 38, text: l)).toList(),
      ),
    );
  }
}

class _WalletTile extends StatelessWidget {
  final dynamic wallet;
  final AzamanColors colors;
  final bool isCrypto;
  final VoidCallback onDelete;

  const _WalletTile({
    required this.wallet,
    required this.colors,
    required this.isCrypto,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final label = (wallet['label'] ?? '').toString();
    final address = (wallet['address'] ?? '').toString();
    final provider = (wallet['provider'] ?? '').toString();
    final accent = isCrypto ? colors.accent : colors.success;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isCrypto
                  ? Icons.currency_bitcoin
                  : Icons.smartphone_outlined,
              color: accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.isEmpty ? provider : label,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 12,
                    fontFamily: isCrypto ? 'monospace' : null,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                color: colors.danger, size: 18),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add-payout sheet — mobile money + crypto only.
// Master Sprint v2 (2026-05-27): made public + accepts `initialTab` so the
// withdrawal screen can launch the same sheet pre-tabbed to either MoMo or
// Crypto from its empty-state CTAs. The single source of truth pattern
// avoids two divergent add-flows for what's logically the same operation.
// ─────────────────────────────────────────────────────────────────────────────
class AddPayoutSheet extends ConsumerStatefulWidget {
  final VoidCallback onSaved;
  final String initialTab; // 'mobileMoney' | 'crypto'
  const AddPayoutSheet({
    super.key,
    required this.onSaved,
    this.initialTab = 'mobileMoney',
  });

  /// Convenience launcher that the rest of the app should call instead of
  /// creating the widget by hand. Picks the same modal style + barrier that
  /// the saved-wallets screen uses.
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onSaved,
    String initialTab = 'mobileMoney',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.92;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: AddPayoutSheet(onSaved: onSaved, initialTab: initialTab),
        );
      },
    );
  }

  @override
  ConsumerState<AddPayoutSheet> createState() => _AddPayoutSheetState();
}

class _AddPayoutSheetState extends ConsumerState<AddPayoutSheet> {
  late String _category;
  String _momoNetwork = 'MTN_MOMO';

  final _labelCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();

  final _cryptoLabelCtrl = TextEditingController();
  final _cryptoAddrCtrl = TextEditingController();

  bool _submitting = false;

  static const _momos = [
    {'id': 'MTN_MOMO',     'name': 'MTN MoMo',     'color': Color(0xFFFFCC00)},
    {'id': 'TELECEL_CASH', 'name': 'Telecel Cash',  'color': Color(0xFFE60000)},
    {'id': 'AIRTELTIGO',   'name': 'AirtelTigo',    'color': Color(0xFFD62828)},
  ];

  @override
  void initState() {
    super.initState();
    // Master Sprint v2: respect the launcher's initial tab so callers
    // (e.g. withdrawal screen → "Add Crypto Wallet") can deep-link to
    // the correct sub-form without forcing the user to switch tabs.
    _category = widget.initialTab == 'crypto' ? 'crypto' : 'mobileMoney';
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _phoneCtrl.dispose();
    _accountNameCtrl.dispose();
    _cryptoLabelCtrl.dispose();
    _cryptoAddrCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final colors = ref.read(themeProvider).colors;
    if (_submitting) return;

    Map<String, dynamic> payload;
    if (_category == 'mobileMoney') {
      final phone = _phoneCtrl.text.trim();
      final accountName = _accountNameCtrl.text.trim();
      if (phone.isEmpty || accountName.isEmpty) {
        _showError('Phone and account name are required.');
        return;
      }
      payload = {
        'type': _momoNetwork,
        'label': _labelCtrl.text.trim().isEmpty
            ? _momos.firstWhere((m) => m['id'] == _momoNetwork)['name']
            : _labelCtrl.text.trim(),
        'address': phone,
        'accountName': accountName,
      };
    } else {
      final addr = _cryptoAddrCtrl.text.trim();
      if (_cryptoLabelCtrl.text.trim().isEmpty || addr.isEmpty) {
        _showError('Label and address are required.');
        return;
      }
      payload = {
        'type': 'Crypto Wallet',
        'label': _cryptoLabelCtrl.text.trim(),
        'address': addr,
      };
    }

    setState(() => _submitting = true);
    try {
      // Master Sprint v2 (2026-05-27): backend requires password (or 2FA
      // token) re-confirmation. Prompt the user inline before posting.
      final password = await _promptPassword();
      if (password == null) {
        if (mounted) setState(() => _submitting = false);
        return;
      }
      payload['password'] = password;
      final res = await apiClient.post('/wallet/saved', payload);
      if (res.statusCode == 201 || res.statusCode == 200) {
        if (mounted) {
          HapticFeedback.heavyImpact();
          Navigator.of(context).pop();
          widget.onSaved();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Payout destination saved'),
            backgroundColor: colors.success,
            behavior: SnackBarBehavior.floating,
          ));
        }
      } else {
        final body = jsonDecode(res.body);
        _showError(body['message']?.toString() ?? 'Failed to save.');
      }
    } catch (e) {
      _showError('Network error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String msg) {
    final colors = ref.read(themeProvider).colors;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: colors.danger,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Master Sprint v2: inline password prompt for the security gate. The
  /// backend requires this (or a 2FA token) before persisting any payout
  /// destination — see middleware in walletController.addSavedWallet.
  Future<String?> _promptPassword() async {
    final colors = ref.read(themeProvider).colors;
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: colors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Icon(Icons.lock_outline, color: colors.warning, size: 18),
              const SizedBox(width: 8),
              Text(
                'Confirm with Password',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saving a payout destination requires re-entering your password.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  obscureText: true,
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: colors.background.withOpacity(0.6),
                    hintText: 'Password',
                    hintStyle: TextStyle(color: colors.textTertiary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.divider),
                    ),
                  ),
                  onSubmitted: (v) => Navigator.pop(ctx, v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text('Confirm',
                  style: TextStyle(
                      color: colors.accent, fontWeight: FontWeight.w800)),
            ),
          ],
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    return result == null || result.isEmpty ? null : result;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Header row
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: colors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.account_balance_wallet_outlined,
                    color: colors.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Add Payout Destination',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 17, fontWeight: FontWeight.w900,
                          letterSpacing: -0.3)),
                      const SizedBox(height: 2),
                      Text('Saved accounts for quick withdrawals',
                        style: TextStyle(
                          color: colors.textTertiary, fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: colors.textTertiary, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Divider(color: colors.divider, height: 1),
            const SizedBox(height: 18),

            // Category toggle
            Row(
              children: [
                Expanded(
                  child: _segmentButton(
                      colors, 'Mobile Money', _category == 'mobileMoney',
                      () => setState(() => _category = 'mobileMoney')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _segmentButton(
                      colors, 'Crypto', _category == 'crypto',
                      () => setState(() => _category = 'crypto')),
                ),
              ],
            ),
            const SizedBox(height: 18),

            if (_category == 'mobileMoney') ..._momoForm(colors),
            if (_category == 'crypto') ..._cryptoForm(colors),

            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor:
                      colors.isDark ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Text('Save',
                        style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segmentButton(
      AzamanColors colors, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.accent.withOpacity(0.15) : colors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? colors.accent : colors.divider,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.accent : colors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  List<Widget> _momoForm(AzamanColors colors) {
    return [
      Text('Network',
          style: TextStyle(
              color: colors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8)),
      const SizedBox(height: 8),
      Row(
        children: _momos.map((m) {
          final selected = _momoNetwork == m['id'];
          final c = m['color'] as Color;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () { HapticFeedback.selectionClick(); setState(() => _momoNetwork = m['id'] as String); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? c.withOpacity(0.13) : colors.softSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? c : colors.divider,
                      width: selected ? 1.8 : 1.0,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(m['name'] as String,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected ? c : colors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 14),
      // Master Sprint v2 (2026-05-27): Replace the manual "Account Holder
      // Name" text field with a phone-first flow. The user types the
      // number, taps Verify, and the platform queries the network's name
      // lookup service to populate the holder's registered name. This
      // mirrors the deposit-side SavedMomoAccount flow and prevents
      // typos sending money to the wrong person.
      _Field(
        controller: _phoneCtrl,
        label: 'Phone Number',
        hint: '0541234567 or +233541234567',
        colors: colors,
        keyboardType: TextInputType.phone,
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: AzamanButton(
              label: _accountNameCtrl.text.isEmpty
                  ? 'Verify Account Holder'
                  : 'Re-verify',
              icon: Icons.search,
              variant: AzamanButtonVariant.secondary,
              onPressed: () async {
                final phone = _phoneCtrl.text.trim();
                if (phone.isEmpty) {
                  _showError('Enter the phone number first.');
                  return;
                }
                // Map the legacy MTN_MOMO/VODAFONE_CASH/AIRTELTIGO id back
                // to the canonical provider strings the lookup service
                // expects (MTN / VODAFONE / TELECEL).
                final providerStr = switch (_momoNetwork) {
                  'MTN_MOMO' => 'MTN',
                  'VODAFONE_CASH' => 'TELECEL', // legacy
                  'TELECEL_CASH' => 'TELECEL',
                  'AIRTELTIGO' || 'TELECEL_CASH' => 'TELECEL',
                  _ => 'MTN',
                };
                try {
                  final res = await ref
                      .read(savedMomoProvider.notifier)
                      .lookupName(provider: providerStr, phoneNumber: phone);
                  setState(() {
                    _accountNameCtrl.text = res.name;
                    _phoneCtrl.text = res.msisdn;
                  });
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
            ),
          ),
        ],
      ),
      if (_accountNameCtrl.text.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.success.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.success.withOpacity(0.30)),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: colors.success, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Registered to: ${_accountNameCtrl.text}',
                  style: TextStyle(
                    color: colors.success,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      _Field(
        controller: _labelCtrl,
        label: 'Label (optional)',
        hint: 'e.g. "My MTN" / "Mum\'s phone"',
        colors: colors,
      ),
    ];
  }

  List<Widget> _cryptoForm(AzamanColors colors) {
    return [
      _Field(
        controller: _cryptoLabelCtrl,
        label: 'Wallet Label',
        hint: 'e.g. "My Binance" / "Cold Storage"',
        colors: colors,
      ),
      const SizedBox(height: 12),
      _Field(
        controller: _cryptoAddrCtrl,
        label: 'Address or Binance ID',
        hint: 'Polygon / TRC20 / ERC20 / Binance Pay ID',
        colors: colors,
        monospace: true,
      ),
      const SizedBox(height: 8),
      Text(
        'Tip: Binance Pay IDs incur zero gas fees. External chains '
        '(TRC20 / ERC20) carry network fees that may be split per the '
        'platform fee schedule.',
        style: TextStyle(
            color: colors.textTertiary, fontSize: 11, height: 1.4),
      ),
    ];
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final AzamanColors colors;
  final TextInputType? keyboardType;
  final bool monospace;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.colors,
    this.keyboardType,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: colors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(
            color: colors.textPrimary,
            fontFamily: monospace ? 'monospace' : null,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                TextStyle(color: colors.textTertiary, fontSize: 13),
            filled: true,
            fillColor: colors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}
