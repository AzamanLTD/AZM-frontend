// lib/screens/withdrawal_screen.dart
//
// =============================================================================
// AZAMAN V2 — WITHDRAWAL SCREEN
// Phase B update: bridges the Kotani Pay V3 mobile-money gateway.
//
// Two co-existing paths on the same screen:
//
//   1. Mobile Money  → POST /api/finance/withdraw/fiat
//      Body: { amount, recipientPhone, network, accountName? }
//      Backend: Phase B Kotani Pay flow — debits availableBalance (USDC),
//      applies the 2 % exit fee + 1 %/1 % influencer split, dispatches a
//      MoMo payout. The "limited fiat" banner reads from
//      GET /api/finance/fiat-pool-status (fiatPoolStatusProvider).
//
//   2. Crypto Wallet → POST /api/wallet/withdraw  (whitelist-only)
//      Phase 15 stance preserved verbatim — saved-method picker only,
//      no free-form address input.
//
// The user toggles between the two paths via a segmented control at the top.
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/fiat_pool_provider.dart';
import 'package:azaman/providers/saved_momo_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/azm_spend_provider.dart';
import 'package:azaman/providers/platform_config_provider.dart';
import 'package:azaman/services/azm_spend_service.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/screens/saved_wallets_screen.dart';
import 'package:azaman/screens/smart_route/smart_route_list_screen.dart';
import 'package:azaman/services/receipt_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/utils/biometric_gate.dart';
import 'package:azaman/widgets/slide_to_confirm.dart';
import 'package:azaman/widgets/nav_transitions.dart';


// ── Mode / network enums ─────────────────────────────────────────────────────

enum _WithdrawMode { mobileMoney, cryptoWallet }

enum MomoNetwork { mtn, telecel, airtelTigo }

extension on MomoNetwork {
  /// Backend-canonical token sent on the wire.
  String get apiValue {
    switch (this) {
      case MomoNetwork.mtn:
        return 'MTN';
      case MomoNetwork.telecel:
        return 'TELECEL';
      case MomoNetwork.airtelTigo:
        return 'AIRTELTIGO';
    }
  }
}

// ── Screen ──────────────────────────────────────────────────────────────────

class WithdrawalScreen extends ConsumerStatefulWidget {
  const WithdrawalScreen({super.key});

  @override
  ConsumerState<WithdrawalScreen> createState() => _WithdrawalScreenState();
}

class _WithdrawalScreenState extends ConsumerState<WithdrawalScreen> {
  // ── Common ──────────────────────────────────────────────────────────────
  final TextEditingController _amountController = TextEditingController();
  // Phase H3 — GlobalKey on the slider so the biometric gate's onCancelled
  // path can reset the thumb after a failed/cancelled auth prompt. Without
  // this the slide widget commits to _confirmed=true on swipe completion
  // and the user is stuck looking at a dead thumb until they navigate away.
  final GlobalKey<SlideToConfirmState> _slideKey =
      GlobalKey<SlideToConfirmState>();
  bool _isSubmitting = false;
  _WithdrawMode _mode = _WithdrawMode.mobileMoney;

  // ── Crypto-wallet path (Phase 15 whitelist) ─────────────────────────────
  bool _isLoadingWallets = true;
  List<Map<String, dynamic>> _savedWallets = [];
  Map<String, dynamic>? _selectedWallet;

  // ── Mobile Money path (Phase B Kotani fields) ───────────────────────────
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _accountNameController = TextEditingController();
  MomoNetwork _selectedNetwork = MomoNetwork.mtn;
  // Master Sprint v2: when set, indicates the user picked a saved MoMo
  // account; the FE blocks submission until a saved account is selected.
  String? _selectedSavedMomoId;

  // ── Balance + role ──────────────────────────────────────────────────────
  double _availableBalance = 0.0; // USDC — used for both fiat and crypto paths

  // ── AZM Fee Discount (Phase E2) ────────────────────────────────────────
  // The current AZM balance is read live from `azmSpendProvider.options`
  // (single source of truth — kept fresh by the spend service after every
  // debit). The previous local `_azmBalance` mirror went stale once the BE
  // started owning the AZM debit (Phase E2 BUGFIX 2026-05-27) and was
  // retired.
  FeeDiscountTier? _selectedFeeDiscount;

  // ── Fee preview ────────────────────────────────────────────────────────
  double _feeComputed = 0.0;
  double _youReceive  = 0.0;
  double _amountVal   = 0.0;

  void _updateFeePreview(String raw) {
    final amt = double.tryParse(raw) ?? 0.0;
    const baseRate = 0.02;
    final discount = _selectedFeeDiscount?.discount ?? 0.0;
    final fee = amt * baseRate * (1 - discount);
    setState(() {
      _amountVal   = amt;
      _feeComputed = fee;
      _youReceive  = amt - fee;
    });
  }

  // ── Recent Withdrawals (Phase Q11) ─────────────────────────────────────
  List<Map<String, dynamic>> _recentCompletedWithdrawals = [];
  bool _isLoadingHistory = false;
  bool _hasLoadedHistory = false;
  bool _recentWithdrawalsExpanded = false;
  String? _downloadingId;

  // ──────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_fetchSavedWallets(), _fetchUserBalance()]);
    // Phase E2 — prime AZM spend options for the fee-discount selector
    ref.read(azmSpendProvider.notifier).primeIfNeeded();
  }

  Future<void> _fetchUserBalance() async {
    try {
      final auth = ref.read(authProvider);
      final userId = auth.user?.id;
      if (userId == null) return;

      final response = await apiClient.get('/auth/me/$userId');

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        setState(() {
          _availableBalance =
              double.tryParse(data['availableBalance']?.toString() ?? '0') ??
              0.0;
        });
      }
    } catch (e) {
      debugPrint('Error fetching balance: $e');
    }
  }

  Future<void> _fetchSavedWallets() async {
    try {
      final response = await apiClient.get('/wallet/saved');

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        final wallets = List<Map<String, dynamic>>.from(data['wallets'] ?? []);
        setState(() {
          _savedWallets = wallets;
          _selectedWallet = wallets.isNotEmpty ? wallets.first : null;
          _isLoadingWallets = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingWallets = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingWallets = false);
    }
  }

  // ── Submission paths ────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0) {
      _showSnack('Enter a valid amount', isError: true);
      return;
    }

    if (_mode == _WithdrawMode.mobileMoney) {
      await _submitMobileMoney(amount);
    } else {
      await _submitCryptoWallet(amount);
    }
  }

  Future<void> _submitMobileMoney(double amount) async {
    final phone = _phoneController.text.trim();
    final accountName = _accountNameController.text.trim();

    if (amount > _availableBalance) {
      _showSnack(
        'Insufficient USDC balance for fiat withdrawal',
        isError: true,
      );
      return;
    }
    if (phone.length < 9) {
      _showSnack(
        'Enter a valid recipient phone number (min 9 digits)',
        isError: true,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    // Phase E2 — AZM fee discount.
    //
    // BUGFIX (2026-05-27): the FE previously called
    // `azmSpendProvider.applyFeeDiscount(tierId)` here AND then sent
    // `feeDiscountTierId` in the withdrawal request body. The BE
    // `fiatWithdrawal` controller forwards `feeDiscountTierId` to
    // `azmSpendService.applyFeeDiscount` itself, so the user's AZM was
    // being debited TWICE per withdrawal — once on the FE pre-call, then
    // again inside the BE controller. The fix: forward the tier id only.
    // The BE is the single source of truth for the AZM debit (and runs
    // it inside the same logical flow as the withdrawal so a withdrawal
    // failure doesn't strand a user without their AZM).

    try {
      final response = await apiClient.post('/finance/withdraw/fiat', {
        'amount': amount,
        'recipientPhone': phone,
        'network': _selectedNetwork.apiValue,
        // Master Sprint v2: the optional `accountName` field is now used
        // as a free-form REFERENCE attached to the SMS sent to the
        // recipient (e.g. "Rent for May"). The backend Kotani Pay payload
        // already supports a free-text reference field; the server-side
        // normaliser maps `accountName` → `note` for the gateway.
        if (accountName.isNotEmpty) 'accountName': accountName,
        if (_selectedSavedMomoId != null)
          'savedAccountId': _selectedSavedMomoId,
        if (_selectedFeeDiscount != null)
          'feeDiscountTierId': _selectedFeeDiscount!.id,
      });

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        HapticFeedback.heavyImpact();
        // Refresh the pool status — a successful payout debits SystemFiatPool
        // so the banner state may have changed.
        ref.invalidate(fiatPoolStatusProvider);
        // The BE applied the AZM debit server-side, so refresh the local
        // AZM mirror by re-priming the spend options provider. Cheap
        // call (one row + tier definitions) and keeps the discount UI
        // accurate if the user opens this screen again.
        ref.read(azmSpendProvider.notifier).refresh();
        // Clear the selection so a back-then-forward navigation doesn't
        // re-arm the same tier accidentally.
        setState(() => _selectedFeeDiscount = null);
        _showSnack(
          data['message']?.toString() ?? 'Mobile-money withdrawal accepted',
          isError: false,
        );
        Navigator.pop(context);
      } else {
        // Phase E2 surface: BE returns code=AZM_SPEND_FAILED when the tier
        // can't be debited (insufficient AZM, invalid tier, etc.). Show
        // a precise message so the user knows the AZM half failed and
        // their USDC is untouched.
        final code = data['code']?.toString();
        final msg = code == 'AZM_SPEND_FAILED'
            ? 'AZM discount failed: ${data['message'] ?? 'unable to apply'}'
            : (data['message']?.toString() ??
                  'Withdrawal failed (status ${response.statusCode})');
        _showSnack(msg, isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSnack('Network error.', isError: true);
      }
    }
  }

  Future<void> _submitCryptoWallet(double amount) async {
    // BUGFIX (2026-05-27): the previous logic capped the crypto-withdrawal
    // balance check at `_azmBalance` for non-vendor users. That reflected
    // the obsolete Phase D-2 state where AZM was the withdrawal currency;
    // Phase D-3 reverted it and AZM is now strictly a loyalty-point ledger
    // (see `User.azmBalance` doc-comment in `prisma/schema.prisma`). The
    // BE `walletController.requestWithdrawal` debits `availableBalance`
    // (USDC) for ALL roles. The FE check now mirrors that — every user,
    // vendor or not, withdraws USDC from `availableBalance`.
    if (amount > _availableBalance) {
      _showSnack('Insufficient USDC balance', isError: true);
      return;
    }
    if (_selectedWallet == null) {
      _showSnack('Select a saved payment method', isError: true);
      return;
    }

    final destination = _selectedWallet!['address']?.toString() ?? '';
    final networkPref =
        _selectedWallet!['network']?.toString() ??
        _selectedWallet!['provider']?.toString() ??
        'MOMO';

    setState(() => _isSubmitting = true);
    try {
      final response = await apiClient.post('/wallet/withdraw', {
        'amount': amount,
        'destination': destination,
        'networkPref': networkPref,
      });

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        HapticFeedback.heavyImpact();
        _showSnack(
          data['message']?.toString() ?? 'Withdrawal requested!',
          isError: false,
        );
        Navigator.pop(context);
      } else {
        _showSnack(
          data['message']?.toString() ?? 'Withdrawal failed',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSnack('Network error.', isError: true);
      }
    }
  }

  // ── UX helpers ──────────────────────────────────────────────────────────

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    final colors = ref.read(themeProvider).colors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? colors.danger : colors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _goToAddPaymentMethod() {
    HapticFeedback.selectionClick();
    // Master Sprint v2 (2026-05-27): instead of pushing the full saved-
    // wallets screen, open the same AddPayoutSheet inline with the tab
    // matching whichever withdrawal mode the user is on. The sheet
    // saves to the same SavedWallet table, so the new entry shows up
    // in both Settings → Deposit Addresses (legacy 'Withdrawal Addresses'
    // also pulls from this table) AND on the withdrawal screen after
    // we re-fetch.
    final initialTab = _mode == _WithdrawMode.cryptoWallet
        ? 'crypto'
        : 'mobileMoney';
    AddPayoutSheet.show(
      context,
      onSaved: () {
        if (!mounted) return;
        _fetchSavedWallets();
      },
      initialTab: initialTab,
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _phoneController.dispose();
    _accountNameController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // UI
  // ──────────────────────────────────────────────────────────────────────────

  // ── Phase Q11: Recent completed withdrawals with receipt download ──────
  Future<void> _fetchRecentWithdrawals() async {
    if (_hasLoadedHistory || !mounted) return;
    setState(() => _isLoadingHistory = true);
    try {
      final response = await apiClient.get('/wallet/history');
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawHistory = data['history'] ?? data['withdrawals'] ?? const [];
        final history = rawHistory is List ? rawHistory : const [];
        final completed = history
            .whereType<Map>()
            .where(
              (w) =>
                  (w['status']?.toString().toUpperCase() ?? '') == 'COMPLETED',
            )
            .take(5)
            .map((w) => Map<String, dynamic>.from(w))
            .toList();
        setState(() {
          _recentCompletedWithdrawals = completed;
          _hasLoadedHistory = true;
        });
      } else {
        setState(() {
          _recentCompletedWithdrawals = const [];
          _hasLoadedHistory = true;
        });
      }
    } catch (e) {
      debugPrint('[WithdrawalScreen] history fetch error: $e');
      if (mounted) {
        setState(() {
          _recentCompletedWithdrawals = const [];
          _hasLoadedHistory = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  /// Master Sprint v2 (2026-05-27): Smart Routes entry point relocated
  /// from the settings drawer to the withdrawal screen. Recurring
  /// outbound payments (MoMo, transfer, vault deposit, savings deposit)
  /// belong wherever the user is already in the "I'm sending money"
  /// mental model.
  Widget _buildSmartRoutesEntry(AzamanColors colors) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        pushWithVerticalTransition(context, const SmartRouteListScreen());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.turn_left, color: colors.accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Smart Routes',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Automate recurring withdrawals',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: colors.textTertiary, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentWithdrawalsSection(AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () async {
            if (!mounted) return;
            HapticFeedback.selectionClick();
            if (_recentWithdrawalsExpanded) {
              setState(() => _recentWithdrawalsExpanded = false);
              return;
            }
            setState(() => _recentWithdrawalsExpanded = true);
            if (!_hasLoadedHistory) await _fetchRecentWithdrawals();
          },
          child: Row(
            children: [
              Icon(
                Icons.history,
                color: colors.textPrimary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Recent withdrawals',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (_recentWithdrawalsExpanded)
                IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _recentWithdrawalsExpanded = false);
                  },
                  icon: Icon(
                    Icons.cancel_outlined,
                    color: colors.textTertiary,
                    size: 18,
                  ),
                )
              else
                Icon(
                  Icons.arrow_downward,
                  color: colors.textTertiary,
                  size: 18,
                ),
            ],
          ),
        ),
        if (_recentWithdrawalsExpanded && _isLoadingHistory)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: colors.accent,
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
        if (_recentWithdrawalsExpanded &&
            _hasLoadedHistory &&
            _recentCompletedWithdrawals.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'No completed withdrawals yet.',
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
          ),
        if (_recentWithdrawalsExpanded &&
            _recentCompletedWithdrawals.isNotEmpty)
          ...List.generate(_recentCompletedWithdrawals.length, (i) {
            final w = _recentCompletedWithdrawals[i];
            final id = w['id']?.toString() ?? '';
            final amount = w['amount']?.toString() ?? '0';
            final method =
                w['payoutMethod']?.toString() ??
                w['network']?.toString() ??
                'Withdrawal';
            final isDownloading = _downloadingId == id;

            return Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: colors.success,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '\$$amount',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          method,
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: isDownloading
                        ? null
                        : () => _downloadWithdrawalReceipt(id, colors),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: isDownloading
                          ? SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(
                                color: colors.accent,
                                strokeWidth: 2,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.download_outlined,
                                  color: colors.accent,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Receipt',
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Future<void> _downloadWithdrawalReceipt(
    String id,
    AzamanColors colors,
  ) async {
    setState(() => _downloadingId = id);
    try {
      await ReceiptService.downloadWithdrawalReceipt(id);
      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Receipt downloaded'),
            backgroundColor: colors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: colors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Granular theme read (Phase 0b convention).
    final colors = ref.watch(themeProvider.select((t) => t.colors));

    // BUGFIX (2026-05-27): both withdrawal paths debit USDC from
    // `User.availableBalance` server-side (mobile-money via
    // `processFiatWithdrawal`, crypto via `requestWithdrawal`). The
    // previous version showed "USDT" for vendors and "AZM" for non-vendor
    // crypto withdrawals — both wrong. AZM is a loyalty-point ledger
    // (Phase D-3), not a withdrawable currency. The label is now USDC
    // for both modes regardless of role.
    final bool isMomo = _mode == _WithdrawMode.mobileMoney;
    const String balanceLabel = 'USDC';
    final double activeBalance = _availableBalance;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: colors.textPrimary,
            size: 18,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Withdraw',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
      body: _isLoadingWallets
          ? Center(child: CircularProgressIndicator(color: colors.accent))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isMomo) _buildFiatPoolBanner(colors),
                  _buildModeToggle(colors),
                  const SizedBox(height: 28),
                  _buildBalanceCard(colors, balanceLabel, activeBalance),
                  const SizedBox(height: 28),
                  _buildAmountField(colors, balanceLabel, activeBalance),
                  const SizedBox(height: 28),
                  if (isMomo)
                    _buildMobileMoneyFields(colors)
                  else
                    _buildDestinationSection(colors),
                  if (!isMomo && _selectedWallet != null) ...[
                    const SizedBox(height: 18),
                    _buildFeePreview(colors),
                  ],
                  if (isMomo) ...[
                    const SizedBox(height: 24),
                    _buildKotaniFeePreview(colors),
                    _buildAzmFeeDiscountSelector(colors),
                  ],
                  const SizedBox(height: 28),
                  _buildSubmitButton(colors),
                  const SizedBox(height: 28),
                  _buildSmartRoutesEntry(colors),
                  const SizedBox(height: 16),
                  _buildRecentWithdrawalsSection(colors),
                ],
              ),
            ),
    );
  }

  // ── Fiat-pool banner (Phase B) ──────────────────────────────────────────

  Widget _buildFiatPoolBanner(AzamanColors colors) {
    final asyncSnapshot = ref.watch(fiatPoolStatusProvider);
    return asyncSnapshot.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (snap) {
        if (!snap.isLimited) return const SizedBox.shrink();
        final isCritical = snap.status == FiatPoolStatus.critical;
        final accent = isCritical ? colors.danger : colors.warning;
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isCritical
                    ? Icons.error_outline
                    : Icons.info_outline,
                color: accent,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isCritical
                      ? 'Local fiat is low. Withdrawals may take longer.'
                      : 'Local fiat is limited. Some withdrawals may be delayed.',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Mode toggle (matches deposit screen's _SegmentedTabs style) ──────────

  Widget _buildModeToggle(AzamanColors colors) {
    Widget tile(_WithdrawMode mode, String label) {
      final selected = _mode == mode;
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _mode = mode);
        },
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? colors.accent : colors.textPrimary,
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 28 : 0,
                height: 2.5,
                decoration: BoxDecoration(
                  color: selected ? colors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            tile(_WithdrawMode.mobileMoney, 'Mobile Money'),
            tile(_WithdrawMode.cryptoWallet, 'Crypto Wallet'),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(
    AzamanColors colors,
    String balanceLabel,
    double active,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available',
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${active.toStringAsFixed(2)} $balanceLabel',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 34,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildAmountField(
    AzamanColors colors,
    String balanceLabel,
    double active,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Amount',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) { setState(() {}); _updateFeePreview(v); },
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: colors.softSurface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            hintText: '0.00',
            hintStyle: TextStyle(color: colors.textTertiary),
            prefixText: '$balanceLabel ',
            prefixStyle: TextStyle(
              color: colors.textTertiary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            suffixIcon: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _amountController.text = active.toStringAsFixed(2);
                });
              },
              child: Center(
                widthFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Max',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  // ── Mobile-money input fields (Phase B) ─────────────────────────────────

  Widget _buildMobileMoneyFields(AzamanColors colors) {
    // Master Sprint v2 (2026-05-27): MoMo withdrawal is now strictly a
    // saved-account picker. The user cannot type a phone number, network,
    // or recipient name here — they must save the destination first via
    // Settings → Withdrawal Addresses (where the platform pre-verifies
    // the registered name on the number). What we DO accept inline is
    // an optional reference that gets included in the SMS the recipient
    // receives alongside the payout.
    final accountsAsync = ref.watch(savedMomoProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Send to',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        accountsAsync.when(
          loading: () => Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: CircularProgressIndicator(color: colors.accent),
            ),
          ),
          error: (_, __) => Text(
            'Could not load saved accounts.',
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
          data: (accounts) {
            if (accounts.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.smartphone_outlined,
                        color: colors.textPrimary,
                        size: 19,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No saved mobile money account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          AddPayoutSheet.show(
                            context,
                            onSaved: () {
                              if (!mounted) return;
                              _fetchSavedWallets();
                              ref.read(savedMomoProvider.notifier).refresh();
                            },
                            initialTab: 'mobileMoney',
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: colors.accent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Add account',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Column(
              children: accounts
                  .map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MomoAccountPicker(
                        account: a,
                        colors: colors,
                        selected: _selectedSavedMomoId == a.id,
                        onTap: () => setState(() {
                          _selectedSavedMomoId = a.id;
                          _phoneController.text = a.phoneNumber;
                          _accountNameController.text = a.accountName ?? '';
                          // Map provider → MomoNetwork enum for backend
                          // compatibility — the existing _handleMomoWithdraw
                          // path still reads _selectedNetwork.apiValue.
                          // Map saved account provider → MomoNetwork enum
                          switch (a.provider.toUpperCase()) {
                            case 'MTN':
                              _selectedNetwork = MomoNetwork.mtn;
                              break;
                            case 'TELECEL':
                            case 'VODAFONE': // legacy stored value
                              _selectedNetwork = MomoNetwork.telecel;
                              break;
                            case 'AIRTELTIGO':
                            case 'AT':
                              _selectedNetwork = MomoNetwork.airtelTigo;
                              break;
                            default:
                              _selectedNetwork = MomoNetwork.mtn;
                          }
                        }),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 24),
        Text(
          'Reference',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _accountNameController,
          keyboardType: TextInputType.text,
          maxLength: 80,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: colors.softSurface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            hintText: 'Optional note',
            hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  // ── Crypto-wallet whitelist picker (Phase 15 stance preserved) ──────────

  Widget _buildDestinationSection(AzamanColors colors) {
    // Master Sprint v2 (2026-05-27): the crypto-tab destination picker
    // must show only crypto wallets (BINANCE_ID, TRC20, ERC20_BEP20).
    // Anything else (MTN_MOMO, VODAFONE_CASH, etc.) is a payout-MoMo
    // entry that belongs on the Mobile Money tab. The saved-wallets
    // screen accepts both surfaces; this filter ensures the right ones
    // show on the right tab.
    final cryptoWallets = _savedWallets.where((w) {
      final network = (w['network'] ?? '').toString().toUpperCase();
      return network == 'BINANCE_ID' ||
          network == 'TRC20' ||
          network == 'ERC20_BEP20' ||
          network == 'POLYGON' ||
          network == 'ETHEREUM' ||
          network == 'BITCOIN';
    }).toList();
    if (cryptoWallets.isEmpty) return _buildEmptyMethodsCard(colors);
    return _buildSavedMethodPicker(colors, cryptoWallets);
  }

  Widget _buildEmptyMethodsCard(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: colors.textPrimary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No saved crypto wallet',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Add a verified wallet to withdraw.',
            style: TextStyle(color: colors.textTertiary, fontSize: 13),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _goToAddPaymentMethod,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: colors.textPrimary,
            ),
            child: const Text(
              'Add wallet',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedMethodPicker(
    AzamanColors colors, [
    List<Map<String, dynamic>>? walletsOverride,
  ]) {
    final wallets = walletsOverride ?? _savedWallets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Wallet',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            GestureDetector(
              onTap: _goToAddPaymentMethod,
              child: Text(
                'Add',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: colors.softSurface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Map<String, dynamic>>(
              dropdownColor: colors.card,
              isExpanded: true,
              value: wallets.contains(_selectedWallet)
                  ? _selectedWallet
                  : (wallets.isNotEmpty ? wallets.first : null),
              icon: Icon(
                Icons.arrow_downward,
                color: colors.textTertiary,
              ),
              items: wallets.map((wallet) {
                final label = wallet['label']?.toString() ?? 'Unnamed';
                final provider = wallet['provider']?.toString() ?? '';
                final address = wallet['address']?.toString() ?? '';
                final masked = _maskAddress(address);
                return DropdownMenuItem<Map<String, dynamic>>(
                  value: wallet,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          _iconForProvider(provider),
                          color: colors.accent,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$label  •  $provider',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (masked.isNotEmpty)
                                Text(
                                  masked,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.textTertiary,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                HapticFeedback.selectionClick();
                setState(() => _selectedWallet = value);
              },
            ),
          ),
        ),
      ],
    );
  }

  // ── Fee preview cards ───────────────────────────────────────────────────

  Widget _buildFeePreview(AzamanColors colors) {
    final config = ref.watch(platformConfigProvider);
    final network = _selectedWallet?['network']?.toString() ?? '';
    final bool isBinance = network == 'BINANCE_ID';
    final bool isFiat = network == 'FIAT_ACCOUNT';
    final Color previewColor = isBinance ? colors.success : colors.accent;

    String title;
    String subtitle;
    if (isBinance) {
      title = '0.00 (Free)';
      subtitle = 'Binance Pay transfers are instant and incur zero gas fees.';
    } else if (isFiat) {
      title = 'Local Transfer';
      subtitle = 'Funds settle to your saved MoMo / bank account in minutes.';
    } else {
      title = 'Split 50/50 + Platform Fee';
      subtitle =
          'Admin covers 50% of blockchain gas. Platform fee also applies.';
    }

    final amount = double.tryParse(_amountController.text) ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Network Fee:',
                style: TextStyle(color: colors.textSecondary),
              ),
              Text(
                title,
                style: TextStyle(
                  color: previewColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          // Phase ADMIN-CONTROL-2-FE: live crypto fee breakdown for
          // non-Binance, non-fiat crypto withdrawals
          if (!isBinance && !isFiat && amount > 0) ...[
            const SizedBox(height: 8),
            _buildCryptoFeeRow(
              colors: colors,
              label:
                  'Gas fee (${(config.cryptoWithdrawalFeePct * 100).toStringAsFixed(2)}%):',
              value:
                  '${(amount * config.cryptoWithdrawalFeePct).toStringAsFixed(4)} USDC',
            ),
            const SizedBox(height: 4),
            _buildCryptoFeeRow(
              colors: colors,
              label:
                  'Platform fee (${(config.cryptoPlatformFeePct * 100).toStringAsFixed(2)}%):',
              value:
                  '${(amount * config.cryptoPlatformFeePct).toStringAsFixed(4)} USDC',
            ),
            const SizedBox(height: 4),
            _buildCryptoFeeRow(
              colors: colors,
              label:
                  'Total fee (${((config.cryptoWithdrawalFeePct + config.cryptoPlatformFeePct) * 100).toStringAsFixed(2)}%):',
              value:
                  '${(amount * (config.cryptoWithdrawalFeePct + config.cryptoPlatformFeePct)).toStringAsFixed(4)} USDC',
              isBold: true,
              valueColor: previewColor,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(color: colors.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// Single fee row used inside the crypto withdrawal fee breakdown.
  Widget _buildCryptoFeeRow({
    required AzamanColors colors,
    required String label,
    required String value,
    bool isBold = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: colors.textTertiary, fontSize: 11)),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? colors.textSecondary,
            fontSize: 11,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  /// Phase B exit-fee preview — Phase ADMIN-CONTROL-2-FE: fee rate now sourced
  /// from live PlatformConfig instead of hardcoded 0.02.
  /// Phase E2: updated to reflect AZM fee discount when selected.
  Widget _buildKotaniFeePreview(AzamanColors colors) {
    final config = ref.watch(platformConfigProvider);
    final amount = double.tryParse(_amountController.text) ?? 0;
    final discountMultiplier = _selectedFeeDiscount?.discount ?? 0.0;
    // Live fee rate from backend — was hardcoded 0.02
    final effectiveFeeRate =
        config.fiatWithdrawalFeePct * (1.0 - discountMultiplier);
    final exitFee = amount * effectiveFeeRate;
    final double net = (amount - exitFee) > 0 ? (amount - exitFee) : 0.0;
    final bool hasDiscount = _selectedFeeDiscount != null;
    final feeLabel = hasDiscount
        ? 'Exit Fee (${(effectiveFeeRate * 100).toStringAsFixed(1)}%):'
        : 'Exit Fee (${(config.fiatWithdrawalFeePct * 100).toStringAsFixed(1)}%):';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(feeLabel, style: TextStyle(color: colors.textSecondary)),
              Row(
                children: [
                  if (hasDiscount) ...[
                    Text(
                      // Strikethrough: undiscounted fee
                      (amount * config.fiatWithdrawalFeePct).toStringAsFixed(2),
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontWeight: FontWeight.w400,
                        fontSize: 13,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    '${exitFee.toStringAsFixed(2)} USDC',
                    style: TextStyle(
                      color: hasDiscount ? colors.success : colors.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'You receive',
                style: TextStyle(color: colors.textSecondary),
              ),
              Text(
                net.toStringAsFixed(2),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (hasDiscount) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.diamond_outlined, size: 14, color: colors.success),
                const SizedBox(width: 6),
                Text(
                  '${_selectedFeeDiscount!.label} AZM discount applied',
                  style: TextStyle(
                    color: colors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── AZM Fee Discount Selector (Phase E2) ────────────────────────────────

  Widget _buildAzmFeeDiscountSelector(AzamanColors colors) {
    final spendState = ref.watch(azmSpendProvider);
    final options = spendState.options;

    // Don't show if no AZM balance or options not loaded
    if (options == null || options.currentBalance <= 0) {
      return const SizedBox.shrink();
    }

    // Don't show if user can't afford any tier
    final affordableTiers = options.feeDiscounts
        .where((t) => t.affordable)
        .toList();
    if (affordableTiers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        // Header
        Row(
          children: [
            Icon(Icons.diamond_outlined, size: 16, color: colors.textPrimary),
            const SizedBox(width: 8),
            Text(
              'Use AZM to reduce the fee',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '${options.currentBalance.toStringAsFixed(1)} AZM',
              style: TextStyle(
                color: colors.accent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Tier chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.feeDiscounts.map((tier) {
            final isSelected = _selectedFeeDiscount?.id == tier.id;
            final canAfford = tier.affordable;

            return GestureDetector(
              onTap: canAfford
                  ? () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        if (isSelected) {
                          _selectedFeeDiscount = null;
                        } else {
                          _selectedFeeDiscount = tier;
                        }
                      });
                    }
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colors.softSurface
                      : canAfford
                      ? Colors.transparent
                      : colors.softSurface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tier.label,
                      style: TextStyle(
                        color: isSelected
                            ? colors.textPrimary
                            : canAfford
                            ? colors.textPrimary
                            : colors.textTertiary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${tier.cost.toInt()} AZM',
                      style: TextStyle(
                        color: isSelected
                            ? colors.textSecondary
                            : colors.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Submit button ───────────────────────────────────────────────────────

  Widget _buildSubmitButton(AzamanColors colors) {
    final bool canSubmit;
    if (_mode == _WithdrawMode.mobileMoney) {
      // Master Sprint v2: must have selected a saved MoMo address. The
      // phone field is auto-populated from the picker — no manual entry.
      final amountOk = (double.tryParse(_amountController.text) ?? 0) > 0;
      canSubmit = _selectedSavedMomoId != null && amountOk;
    } else {
      canSubmit = _selectedWallet != null;
    }

    // Phase H2 — slide-to-confirm replaces the legacy ElevatedButton on
    // the highest-stakes financial commit in the app. We still render a
    // *disabled* ElevatedButton when the form isn't ready (`canSubmit`
    // false) so the page tells the user what to fill in next; once the
    // form is valid AND we're not already submitting, we swap to the
    // SlideToConfirm. The slide widget routes through `_submit()` so all
    // existing validation, network calls, and balance double-checks fire
    // unchanged. `AzamanHaptics.commit()` fires the moment value moves.
    if (!canSubmit || _isSubmitting) {
      return SizedBox(
        width: double.infinity,
        height: 55,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.accent.withValues(alpha: 0.35),
            foregroundColor: colors.isDark ? Colors.black : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          onPressed: null,
          child: _isSubmitting
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: colors.isDark ? Colors.black : Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  _mode == _WithdrawMode.mobileMoney
                      ? 'Choose an account'
                      : 'Choose a wallet',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_youReceive > 0) ...[
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: colors.divider)),
            child: Column(children: [
              _FeeRow("Amount", "${_amountVal.toStringAsFixed(2)} USDC", colors),
              _FeeRow("Service fee (2%)", "-${_feeComputed.toStringAsFixed(2)} USDC", colors, isDanger: true),
              const Divider(height: 16),
              _FeeRow("You receive", "${_youReceive.toStringAsFixed(2)} USDC", colors, isBold: true),
            ]),
          ),
        ],
        SlideToConfirm(
      key: _slideKey,
      text: _mode == _WithdrawMode.mobileMoney
          ? 'Slide to send mobile money'
          : 'Slide to send to wallet',
      backgroundColor: colors.card,
      thumbColor: colors.accent,
      isLoading: _isSubmitting,
      onConfirmed: () {
        // Phase H3 — biometric pre-gate. No-op when biometric lock is
        // disabled in Settings (opt-in); blocks _submit() if enabled and
        // the prompt fails or is cancelled. The commit() haptic now fires
        // INSIDE the gate's success path so a cancelled auth doesn't
        // emit a "transaction sent" buzz.
        AzamanBiometricGate.runSync(
          context,
          () {
            AzamanHaptics.commit();
            _submit();
          },
          reason: _mode == _WithdrawMode.mobileMoney
              ? 'Authenticate to send mobile money'
              : 'Authenticate to send crypto',
          onCancelled: () => _slideKey.currentState?.reset(),
        );
      },
    ),
      ],
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  String _maskAddress(String input) {
    if (input.isEmpty) return '';
    if (input.length <= 8) return input;
    return '${input.substring(0, 4)}••••${input.substring(input.length - 4)}';
  }

  IconData _iconForProvider(String provider) {
    switch (provider) {
      case 'MTN MoMo':
        return Icons.smartphone_outlined;
      case 'Telecel Cash':
        return Icons.sim_card_outlined;
      case 'AirtelTigo Money':
        return Icons.smartphone_outlined;
      case 'Bank Transfer':
        return Icons.account_balance_outlined;
      case 'BINANCE PAY':
        return Icons.currency_bitcoin;
      case 'EXTERNAL WALLET':
        return Icons.account_balance_wallet_outlined;
      default:
        return Icons.payments_outlined;
    }
  }
}

// =============================================================================
// MOMO ACCOUNT PICKER — slender selectable row used by the withdrawal
// screen. Shows the registered name (auto-resolved at save time) + provider
// chip + masked number.
// =============================================================================
class _MomoAccountPicker extends StatelessWidget {
  final SavedMomoAccount account;
  final AzamanColors colors;
  final bool selected;
  final VoidCallback onTap;

  const _MomoAccountPicker({
    required this.account,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  Color get _providerColor {
    switch (account.provider.toUpperCase()) {
      case 'MTN': return const Color(0xFFFFCC00);
      case 'TELECEL': return const Color(0xFFE60000);
      case 'AIRTELTIGO': case 'AT': return const Color(0xFFD62828);
      default: return const Color(0xFF888888);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _providerColor;
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.10) : colors.softSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? c.withValues(alpha: 0.70) : colors.divider,
            width: selected ? 1.8 : 1.0,
          ),
          boxShadow: selected
            ? [BoxShadow(color: c.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3))]
            : const [],
        ),
        child: Row(
          children: [
            // Provider dot
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    account.accountName ?? account.nickname,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13.5, fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${account.provider}  ·  ${account.phoneNumber}',
                    style: TextStyle(color: colors.textTertiary, fontSize: 11),
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                key: ValueKey(selected),
                color: selected ? c : colors.textTertiary.withValues(alpha: 0.5),
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String label;
  final String value;
  final AzamanColors colors;
  final bool isDanger;
  final bool isBold;
  const _FeeRow(this.label, this.value, this.colors,
    {this.isDanger = false, this.isBold = false});
  @override
  Widget build(BuildContext context) {
    final color = isDanger ? colors.danger
      : isBold ? colors.textPrimary : colors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 12)),
          Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: isBold ? FontWeight.w800 : FontWeight.w500)),
        ]),
    );
  }
}
