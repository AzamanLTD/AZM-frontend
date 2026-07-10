// =============================================================================
// AZAMAN — UNIFIED DEPOSIT SCREEN
//
// Replaces the old bottom-sheet chooser + two separate screens with a single,
// slender, Binance-style screen with two top-segmented tabs:
//
//   • Crypto       — user's dedicated Polygon USDC sub-wallet address +
//                    QR + copy + share. The address is derived once per
//                    user from the platform's HD wallet xpub (backend:
//                    GET /api/wallet/deposit-address/polygon).
//
//   • Mobile Money — fiat top-up via MTN / Telecel / AirtelTigo
//                    or bank transfer. Posts to /api/deposit/fiat/initiate
//                    and the gateway webhook credits the user once funds
//                    settle.
//
// Design intent: ALL deposit affordances on the dashboard ("Deposit" quick
// action, settings drawer shortcut, anywhere else) route here. The user
// gets one coherent surface with both options instead of guessing which
// flow to pick from a chooser sheet.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';


import 'package:azaman/screens/saved_wallets_screen.dart'; // For AddPayoutSheet
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:azaman/providers/saved_momo_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/saved_momo_accounts_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/socket_service.dart';


class DepositScreen extends ConsumerStatefulWidget {
  const DepositScreen({
    super.key,
    this.initialTab = DepositTab.fiat,
    this.prefillAmount,
    this.memo,
  });

  final DepositTab initialTab;

  /// Pre-fill amount for the Mobile Money tab. Set when the screen is
  /// reached via a deep link such as `/deposit?amount=12.34&memo=susu:abc`,
  /// most often the Susu T-24h reminder notification (Req 12.3 / 12.4).
  /// The value must be a positive decimal with at most two fractional
  /// digits, otherwise we ignore it and leave the input blank.
  final String? prefillAmount;

  /// Opaque memo string (e.g. `susu:<susuId>`). Logged into the resulting
  /// deposit's metadata server-side so operators can trace deposits back
  /// to the cycle that prompted them. Not surfaced visually.
  final String? memo;

  @override
  ConsumerState<DepositScreen> createState() => _DepositScreenState();
}

enum DepositTab { crypto, fiat }

class _DepositScreenState extends ConsumerState<DepositScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Phase 4 (Susu Sprint, 2026-05-31): when the screen is opened via
    // a deep link carrying ?amount=… (e.g. the T-24h reminder), force
    // the Mobile Money tab so the pre-filled amount is immediately
    // visible. Without this, a deposit reminder for $12.34 would land
    // on the Crypto tab and the user would have to tap over manually.
    final hasPrefill = (widget.prefillAmount?.isNotEmpty ?? false);
    _tabController = TabController(
      length: 2,
      initialIndex: hasPrefill || widget.initialTab == DepositTab.fiat ? 1 : 0,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

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
          'Deposit',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _SegmentedTabs(
              controller: _tabController,
              colors: colors,
              labels: const ['Crypto', 'Mobile Money'],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  const _CryptoDepositPanel(),
                  _FiatDepositPanel(
                    prefillAmount: widget.prefillAmount,
                    memo: widget.memo,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Segmented tab strip — Binance/Robinhood style, slender pill above content.
// ─────────────────────────────────────────────────────────────────────────────
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
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
        child: TabBar(
          controller: controller,
          isScrollable: true,
          indicatorSize: TabBarIndicatorSize.label,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: colors.accent, width: 2.5),
          ),
          labelColor: colors.accent,
          unselectedLabelColor: colors.textPrimary,
          labelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          labelPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
          dividerColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          tabs: labels.map((label) => Tab(text: label, height: 44)).toList(),
        ),
      ),
    );
  }
}

// =============================================================================
// CRYPTO PANEL  ── Polygon USDC, dedicated sub-address per user.
// =============================================================================
class _CryptoDepositPanel extends ConsumerStatefulWidget {
  const _CryptoDepositPanel();

  @override
  ConsumerState<_CryptoDepositPanel> createState() =>
      _CryptoDepositPanelState();
}

class _CryptoDepositPanelState extends ConsumerState<_CryptoDepositPanel>
    with AutomaticKeepAliveClientMixin {
  String? _address;
  bool _isLoading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchDepositAddress();
  }

  Future<void> _fetchDepositAddress() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await apiClient.get('/wallet/deposit-address/polygon');
      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body);
        final data = body['data'] ?? body;
        setState(() {
          _address = data['address'] as String?;
          _isLoading = false;
        });
      } else {
        final body = jsonDecode(response.body);
        setState(() {
          _error = body['message']?.toString() ?? 'Failed to load address';
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Network error. Tap retry.';
        _isLoading = false;
      });
    }
  }

  void _copyAddress(AzamanColors colors) {
    if (_address == null) return;
    Clipboard.setData(ClipboardData(text: _address!));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Address copied'),
        backgroundColor: colors.success,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _shareAddress() {
    if (_address == null) return;
    HapticFeedback.lightImpact();
    Share.share(
      'My Azaman deposit address (Polygon USDC):\n$_address\n\n'
      'IMPORTANT: send only USDC on the Polygon network. '
      'Other tokens or networks will be lost.',
      subject: 'Azaman Deposit Address',
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = ref.watch(themeProvider).colors;

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: colors.danger),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _fetchDepositAddress,
                icon: Icon(Icons.refresh, color: colors.accent),
                label: Text('Retry', style: TextStyle(color: colors.accent)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.accent.withValues(alpha: 0.4)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeading(
            colors: colors,
            title: 'Deposit USDC',
          ),
          const SizedBox(height: 18),
          _CryptoAddressCard(
            colors: colors,
            address: _address ?? '',
            onCopy: () => _copyAddress(colors),
            onShare: _shareAddress,
          ),
          const SizedBox(height: 20),
          FutureBuilder<List<Map<String,dynamic>>>(
            future: _fetchRecentCryptoDeposits(),
            builder: (context, snap) {
              if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Recent Deposits",
                  style: TextStyle(color: colors.textTertiary,
                    fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...snap.data!.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Icon(Icons.check_circle, color: colors.success, size: 14),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      "${(d["amountUsdc"] as num?)?.toStringAsFixed(2) ?? "0"} USDC",
                      style: TextStyle(color: colors.textPrimary,
                        fontSize: 13, fontWeight: FontWeight.w600))),
                    Text(_formatCryptoDate(DateTime.parse(d["createdAt"] ?? "")),
                      style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                  ]),
                )),
              ]);
            },
          ),
        ],
      ),
    );
  }

  Future<List<Map<String,dynamic>>> _fetchRecentCryptoDeposits() async {
    try {
      final resp = await apiClient.get("/finance/transactions?type=DEPOSIT_CRYPTO&limit=2");
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return List<Map<String,dynamic>>.from(data["items"] ?? []);
      }
      return [];
    } catch (_) { return []; }
  }

  String _formatCryptoDate(DateTime dt) {
    final diff = DateTime.now().difference(dt).inDays;
    if (diff == 0) return "Today";
    if (diff == 1) return "Yesterday";
    return "${dt.day}/${dt.month}/${dt.year}";
  }
}

// =============================================================================
// FIAT PANEL  ── Mobile Money / Bank Transfer.
// =============================================================================
class _FiatDepositPanel extends ConsumerStatefulWidget {
  const _FiatDepositPanel({this.prefillAmount, this.memo});

  /// Pre-fill amount (GHS string) propagated from the parent
  /// [DepositScreen] when the route carries `?amount=…`. Susu reminder
  /// notifications use this path (Req 12.4 / 12.6).
  final String? prefillAmount;

  /// Opaque memo string (e.g. `susu:<susuId>`). Forwarded to the BE in
  /// the initiate request so operators can trace deposits back.
  final String? memo;

  @override
  ConsumerState<_FiatDepositPanel> createState() => _FiatDepositPanelState();
}

class _FiatDepositPanelState extends ConsumerState<_FiatDepositPanel>
    with AutomaticKeepAliveClientMixin {
  final _amountController = TextEditingController();
  String _selectedProvider = 'MTN_MOMO';
  String? _selectedAccountId;
  SavedMomoAccount? _selectedAccount;
  bool _isSubmitting = false;
  Map<String, dynamic>? _depositResult;

  // ── Moolre on-ramp (2026-06-23) ──────────────────────────────────────────
  // Name-validation dialog + OTP branch (Moolre TP14 returns requiresOtp).
  String? _resolvedName;
  bool _isValidatingName = false;
  bool _requiresOtp = false;
  String? _pendingReference;
  final _otpController = TextEditingController();
  bool _isConfirmingOtp = false;
  bool _depositConfirmed = false;

  @override
  bool get wantKeepAlive => true;

  /// Map the canonical saved-account provider (MTN | VODAFONE | TELECEL) to the
  /// enum the backend's `initiateMoolreFiatDeposit` MOMO set accepts
  /// (MTN_MOMO | TELECEL_CASH | AIRTELTIGO). Telecel is the Vodafone Ghana
  /// rebrand — the backend treats VODAFONE and TELECEL as the same channel —
  /// so both map to TELECEL_CASH. The same enum is accepted by
  /// `/deposit/validate-name`, so one mapping serves both calls.
  String _backendProvider(String provider) {
    if (provider == 'MTN_MOMO' || provider == 'VODAFONE_CASH' || provider == 'AIRTELTIGO') {
      return provider;
    }
    switch (provider) {
      case 'MTN':
        return 'MTN_MOMO';
      case 'TELECEL':
      case 'VODAFONE': // legacy
        return 'TELECEL_CASH';
      case 'AIRTELTIGO':
        return 'AIRTELTIGO';
      default:
        return '${provider}_MOMO';
    }
  }

  @override
  void initState() {
    super.initState();
    // Phase 4 (Susu Sprint, 2026-05-31) — Req 12.4 / 12.6: pre-fill the
    // amount input when the screen was opened with `?amount=…`. Validate
    // the value has at most two fractional digits and is strictly > 0;
    // anything else is dropped silently and the input stays empty so the
    // user notices and re-enters.
    final raw = widget.prefillAmount?.trim();
    if (raw != null && raw.isNotEmpty) {
      final ok = RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(raw);
      final v = double.tryParse(raw);
      if (ok && v != null && v > 0) {
        _amountController.text = raw;
      }
    }
    SocketService.instance.onDepositSuccess(
      (amountGhs, amountUsdc, provider, reference) {
        if (!mounted) return;
        final pendingRef = _pendingReference ??
            (_depositResult?['reference']?.toString() ?? '');
        if (pendingRef.isEmpty || reference != pendingRef) return;
        setState(() => _depositConfirmed = true);
        final colors = ref.read(themeProvider).colors;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Deposit confirmed — GH₵ ${amountGhs.toStringAsFixed(2)} credited to your wallet',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            backgroundColor: colors.success,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    SocketService.instance.onDepositSuccess((_a, _b, _c, _d) {});
    _amountController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  /// Resolve the registered account name via Moolre, show a confirmation
  /// dialog, then proceed to the deposit. Name validation is best-effort —
  /// if it fails we proceed without it rather than block the deposit.
  Future<void> _validateAndConfirm() async {
    final account = _selectedAccount;
    if (account == null) return;

    setState(() => _isValidatingName = true);
    try {
      final resp = await apiClient.post('/deposit/validate-name', {
        'phoneNumber': account.phoneNumber,
        'provider': _backendProvider(account.provider),
      });
      final body = jsonDecode(resp.body);
      if (resp.statusCode == 200 && body['data'] != null) {
        setState(() => _resolvedName = body['data'] as String?);
      }
    } catch (_) {
      // Name validation is optional — proceed without it if it fails.
    } finally {
      if (mounted) setState(() => _isValidatingName = false);
    }

    if (_resolvedName != null && mounted) {
      final colors = ref.read(themeProvider).colors;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: colors.surface,
          title: Text('Confirm account',
              style: TextStyle(color: colors.textPrimary)),
          content: Text(
            'Paying to: $_resolvedName\nIs this correct?',
            style: TextStyle(color: colors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: colors.textTertiary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Confirm', style: TextStyle(color: colors.accent)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await _initiateDeposit();
  }

  Future<void> _initiateDeposit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    final account = _selectedAccount;
    if (account == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a payment account')));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // All saved accounts in this picker are Mobile Money (MTN / Vodafone /
      // Telecel), so every deposit routes through the Moolre PIN-push on-ramp.
      final body = <String, dynamic>{
        'amountGhs': amount,
        'provider': _backendProvider(account.provider),
        'phoneNumber': account.phoneNumber,
        // Susu memo trace (Req 12.4) — persisted into the deposit's metadata
        // server-side so operators can tie a deposit back to the cycle
        // reminder that prompted it.
        if (widget.memo != null && widget.memo!.isNotEmpty) 'memo': widget.memo,
      };
      final response =
          await apiClient.post('/deposit/fiat/initiate/moolre', body);
      final data = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        HapticFeedback.heavyImpact();
        if (data['requiresOtp'] == true) {
          setState(() {
            _isSubmitting = false;
            _requiresOtp = true;
            _pendingReference = data['data']?['reference']?.toString();
          });
        } else {
          setState(() {
            _depositResult = (data['data'] is Map<String, dynamic>)
                ? data['data'] as Map<String, dynamic>
                : data as Map<String, dynamic>;
            _isSubmitting = false;
          });
        }
      } else {
        setState(() => _isSubmitting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                data['message']?.toString() ?? 'Failed to initiate deposit',
              ),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        String msg;
        if (e is SocketException || e is TimeoutException) {
          msg = 'Connection failed. Check your internet and retry.';
        } else if (e is ApiException) {
          msg = e.message;
        } else {
          msg = 'Something went wrong. Please try again.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
        );
      }
    }
  }

  /// Confirm a Moolre deposit that came back requiresOtp=true.
  Future<void> _confirmOtp() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty) return;
    setState(() => _isConfirmingOtp = true);
    try {
      final resp = await apiClient.post('/deposit/fiat/initiate/moolre/otp', {
        'reference': _pendingReference,
        'otpCode': otp,
      });
      final body = jsonDecode(resp.body);
      if (resp.statusCode == 200 && body['success'] == true) {
        HapticFeedback.heavyImpact();
        setState(() {
          _isConfirmingOtp = false;
          _requiresOtp = false;
          _depositResult = {'reference': _pendingReference};
        });
      } else {
        setState(() => _isConfirmingOtp = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(body['message']?.toString() ?? 'OTP verification failed')),
          );
        }
      }
    } catch (e) {
      setState(() => _isConfirmingOtp = false);
      if (mounted) {
        final msg = (e is ApiException) ? e.message
            : (e is SocketException || e is TimeoutException)
                ? 'Connection failed. Check your internet and retry.'
                : 'Something went wrong. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
        );
      }
    }
  }

  void _reset() {
    setState(() {
      _depositResult = null;
      _requiresOtp = false;
      _pendingReference = null;
      _resolvedName = null;
      _depositConfirmed = false;
      _otpController.clear();
      _amountController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = ref.watch(themeProvider).colors;

    return _requiresOtp
        ? _buildOtpEntry(colors)
        : _depositResult != null
            ? _buildResult(colors)
            : _buildForm(colors);
  }

  // ── Form ───────────────────────────────────────────────────────────────────
  Widget _buildForm(AzamanColors colors) {
    final accountsAsync = ref.watch(savedMomoProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 48, // Accounts for padding (16 + 32)
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PanelHeading(
                    colors: colors,
                    title: 'Deposit with MoMo',
                  ),
                  const SizedBox(height: 18),
                  accountsAsync.when(
                    loading: () => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: CircularProgressIndicator(color: colors.accent),
                      ),
                    ),
                    error: (e, _) => _NoticeCard(
                      colors: colors,
                      icon: Icons.error_outline,
                      accent: colors.danger,
                      text: e.toString(),
                    ),
                    data: (accounts) {
                      if (accounts.isEmpty) {
                        return _InlineAddMomoCard(
                          colors: colors,
                          onAdded: () => ref.invalidate(savedMomoProvider),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PanelCard(
                            colors: colors,
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: accounts
                                  .map(
                                    (a) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _SavedAccountTile(
                                        account: a,
                                        colors: colors,
                                        selected: _selectedAccountId == a.id,
                                        onTap: () => setState(() {
                                          _selectedAccountId = a.id;
                                          _selectedAccount = a;
                                          _selectedProvider = a.provider;
                                        }),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // ── Add Account pill button ──────────────────────
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              AddPayoutSheet.show(
                                context,
                                onSaved: () {
                                  if (!mounted) return;
                                  ref.invalidate(savedMomoProvider);
                                },
                                initialTab: 'mobileMoney',
                              );
                            },
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: colors.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: colors.accent.withValues(alpha: 0.35),
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_circle_outline,
                                      color: colors.accent, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Add Account',
                                    style: TextStyle(
                                      color: colors.accent,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  _PanelCard(
                    colors: colors,
                    fillColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Amount',
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'GH₵ ',
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 100),
                              child: IntrinsicWidth(
                                child: TextField(
                                  controller: _amountController,
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 56,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1.0,
                                  ),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    filled: false,
                                    hintText: '0.00',
                                    hintStyle: TextStyle(
                                      color: colors.textTertiary,
                                      fontSize: 56,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1.0,
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8, runSpacing: 6,
                          children: [50, 100, 200, 500].map((amt) {
                            final isSelected = _amountController.text == amt.toString();
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _amountController.text = amt.toString();
                                  _amountController.selection = TextSelection.fromPosition(
                                    TextPosition(offset: _amountController.text.length));
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                decoration: BoxDecoration(
                                  color: isSelected ? colors.accent : colors.card,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: isSelected ? colors.accent : colors.accent.withOpacity(0.3)),
                                ),
                                child: Text("GH₵ $amt",
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : colors.accent,
                                    fontSize: 13, fontWeight: FontWeight.w700)),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(height: 16),
                  _PrimaryButton(
                    colors: colors,
                    label: _isValidatingName
                        ? 'Checking account...'
                        : _isSubmitting
                            ? 'Sending prompt...'
                            : 'Send deposit prompt',
                    onTap: (_isSubmitting ||
                            _isValidatingName ||
                            _selectedAccountId == null)
                        ? null
                        : _validateAndConfirm,
                    isBusy: _isSubmitting || _isValidatingName,
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      _selectedAccountId == null
                          ? 'Choose a saved number to continue.'
                          : 'Approve to complete the deposit.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Result ────────────────────────────────────────────────────────────────
  Widget _buildResult(AzamanColors colors) {
    final reference = _depositResult?['reference'] ?? '';
    final instructions =
        _depositResult?['instructions']?.toString() ??
        'Follow the prompt on your device to complete payment.';
    final amount =
        _depositResult?['amountGhs']?.toString() ?? _amountController.text;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeading(
            colors: colors,
            eyebrow: 'Deposit status',
            title: 'Prompt sent',
            body: 'Approve it on your phone to complete the deposit.',
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim, child: FadeTransition(opacity: anim, child: child)),
            child: _depositConfirmed
              ? Column(key: const ValueKey("confirmed"),
                  mainAxisSize: MainAxisSize.min, children: [
                  Lottie.asset("assets/animations/success.json",
                    width: 110, height: 110, repeat: false),
                  const SizedBox(height: 8),
                  Text("Deposit Confirmed!", style: TextStyle(
                    color: colors.success, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text("Your wallet has been funded.", style: TextStyle(
                    color: colors.textSecondary, fontSize: 13)),
                ])
              : Column(key: const ValueKey("waiting"),
                  mainAxisSize: MainAxisSize.min, children: [
                  _PulsingDots(color: colors.accent),
                  const SizedBox(height: 14),
                  Text("Waiting for confirmation...", style: TextStyle(
                    color: colors.textSecondary, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text("Approve the prompt on your phone.", style: TextStyle(
                    color: colors.textTertiary, fontSize: 12)),
                ]),
          ),
          if (_depositConfirmed) ...[
            const SizedBox(height: 12),
            _PanelCard(
              colors: colors,
              fillColor: colors.success.withValues(alpha: 0.10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GH₵ $amount',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Prompt sent to $_selectedProvider',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    reference.toString(),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              instructions,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
          ],
          _PrimaryButton(
            colors: colors,
            label: _depositConfirmed ? 'Start another deposit' : 'Cancel',
            onTap: _reset,
          ),
        ],
      ),
    );
  }

  // ── OTP entry ───────────────────────────────────────────────────────────────
  // Shown when Moolre returns requiresOtp=true (TP14). The user enters the code
  // sent to their registered phone; _confirmOtp posts it to the OTP endpoint.
  Widget _buildOtpEntry(AzamanColors colors) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeading(
            colors: colors,
            eyebrow: 'Verification',
            title: 'Enter OTP',
            body: 'Enter the code sent to your registered phone to authorise '
                'this deposit.',
          ),
          const SizedBox(height: 18),
          _PanelCard(
            colors: colors,
            child: TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              autofocus: true,
              maxLength: 6,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '••••••',
                hintStyle: TextStyle(
                  color: colors.textTertiary,
                  letterSpacing: 4,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _PrimaryButton(
            colors: colors,
            label: _isConfirmingOtp ? 'Verifying...' : 'Confirm deposit',
            onTap: _isConfirmingOtp ? null : _confirmOtp,
            isBusy: _isConfirmingOtp,
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _isConfirmingOtp
                  ? null
                  : () => setState(() {
                        _requiresOtp = false;
                        _pendingReference = null;
                        _otpController.clear();
                      }),
              child: Text('Cancel',
                  style: TextStyle(color: colors.textTertiary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeading extends StatelessWidget {
  final AzamanColors colors;
  final String? eyebrow;
  final String title;
  final String? body;

  const _PanelHeading({
    required this.colors,
    this.eyebrow,
    required this.title,
    this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!,
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          title,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.1,
          ),
        ),
        if (body != null) ...[
          const SizedBox(height: 8),
          Text(
            body!,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

class _PanelCard extends StatelessWidget {
  final AzamanColors colors;
  final Widget child;
  final Color? fillColor;
  final EdgeInsetsGeometry? padding;

  const _PanelCard({
    required this.colors,
    required this.child,
    this.fillColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: fillColor ?? colors.softSurface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final AzamanColors colors;
  final String label;
  final VoidCallback? onTap;
  final bool isBusy;

  const _PrimaryButton({
    required this.colors,
    required this.label,
    required this.onTap,
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: Colors.black,
          disabledBackgroundColor: colors.softSurface,
          disabledForegroundColor: colors.textTertiary,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: isBusy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
      ),
    );
  }
}

class _CryptoAddressCard extends StatelessWidget {
  final AzamanColors colors;
  final String address;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  const _CryptoAddressCard({
    required this.colors,
    required this.address,
    required this.onCopy,
    required this.onShare,
  });

  String _short(String addr) {
    if (addr.length < 14) return addr;
    return '${addr.substring(0, 6)}…${addr.substring(addr.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final qrSize = (MediaQuery.of(context).size.width - 130)
        .clamp(190.0, 250.0)
        .toDouble();

    return _PanelCard(
      colors: colors,
      fillColor: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 308),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: QrImageView(
                  data: address,
                  version: QrVersions.auto,
                  size: qrSize,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _short(address),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _PrimaryButton(
                  colors: colors,
                  label: 'Copy address',
                  onTap: onCopy,
                ),
              ),
              const SizedBox(width: 10),
              _IconActionButton(
                colors: colors,
                icon: Icons.share_outlined,
                tooltip: 'Share address',
                onTap: onShare,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Polygon USDC only',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  final AzamanColors colors;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconActionButton({
    required this.colors,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: colors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final AzamanColors colors;
  final IconData icon;
  final Color accent;
  final String text;

  const _NoticeCard({
    required this.colors,
    required this.icon,
    required this.accent,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      colors: colors,
      fillColor: accent.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 15),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedAccountTile extends StatelessWidget {
  final SavedMomoAccount account;
  final AzamanColors colors;
  final bool selected;
  final VoidCallback onTap;

  const _SavedAccountTile({
    required this.account,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  Color _providerColor() => switch (account.provider) {
    'MTN' => const Color(0xFFFFCC00),
    'TELECEL' => const Color(0xFFE60000),
    'VODAFONE' => const Color(0xFFE60000), // legacy
    'TELECEL' => const Color(0xFF0066CC),
    _ => colors.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final pcolor = _providerColor();
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: selected ? colors.accentSurface : colors.softSurface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: pcolor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.smartphone_outlined, color: pcolor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          account.nickname,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (account.isPrimary) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.star_outline,
                          color: colors.warning,
                          size: 12,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${account.provider} · ${account.phoneNumber}',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  if (account.accountName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      account.accountName!,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ],
              ),
            ),
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? colors.accent : colors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                selected
                    ? Icons.check_circle_outline
                    : Icons.circle_outlined,
                color: selected ? Colors.black : colors.textTertiary,
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineAddMomoCard extends ConsumerStatefulWidget {
  final AzamanColors colors;
  final VoidCallback onAdded;
  const _InlineAddMomoCard({required this.colors, required this.onAdded});
  @override
  ConsumerState<_InlineAddMomoCard> createState() => _InlineAddMomoCardState();
}

class _InlineAddMomoCardState extends ConsumerState<_InlineAddMomoCard> {
  final _phoneCtrl = TextEditingController();
  String _provider = "MTN_MOMO";
  bool _loading = false;
  String? _resolvedName;
  String? _error;
  final _providers = ["MTN_MOMO", "TELECEL_CASH", "AIRTELTIGO"];

  Future<void> _validateName() async {
    if (_phoneCtrl.text.trim().length < 9) {
      setState(() => _error = "Enter a valid phone number"); return;
    }
    setState(() { _loading = true; _error = null; _resolvedName = null; });
    try {
      final resp = await apiClient.post("/deposit/validate-name", {
        "phoneNumber": _phoneCtrl.text.trim(), "provider": _provider });
      final body = jsonDecode(resp.body);
      if (body["success"] == true && body["data"] != null) {
        // /api/deposit/validate-name returns data as a plain string (the name),
        // not a nested object. Read it directly.
        setState(() { _resolvedName = body["data"].toString(); _loading = false; });
      } else {
        setState(() { _error = body["message"] ?? "Could not verify"; _loading = false; });
      }
    } on ApiException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      setState(() { _error = "Network error"; _loading = false; });
    }
  }

  Future<void> _saveAndContinue() async {
    if (_resolvedName == null) return;

    // Backend requires password (security gate) before persisting any payout
    // destination. Prompt the user inline — same as AddPayoutSheet does.
    final passwordCtrl = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm password'),
        content: TextField(
          controller: passwordCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Your Azaman password'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, passwordCtrl.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (password == null || password.isEmpty) return;
    if (!mounted) return;

    setState(() => _loading = true);
    try {
      final notifier = ref.read(savedMomoProvider.notifier);
      await notifier.create(
        nickname: _resolvedName!,
        provider: _provider,
        phoneNumber: _phoneCtrl.text.trim(),
        password: password,
      );
      widget.onAdded();
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  void dispose() { _phoneCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Add Mobile Money Number", style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _provider,
          dropdownColor: c.card,
          decoration: InputDecoration(labelText: "Provider", labelStyle: TextStyle(color: c.textSecondary),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.divider))),
          items: _providers.map((p) => DropdownMenuItem(value: p, child: Text(p.replaceAll("_"," "), style: TextStyle(color: c.textPrimary)))).toList(),
          onChanged: (v) => setState(() => _provider = v!),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          style: TextStyle(color: c.textPrimary),
          decoration: InputDecoration(
            labelText: "Phone number", labelStyle: TextStyle(color: c.textSecondary),
            hintText: "024 XXX XXXX", hintStyle: TextStyle(color: c.textTertiary),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.divider))),
        ),
        if (_resolvedName != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.check_circle, color: c.success, size: 16), 
            const SizedBox(width: 6),
            Expanded(child: Text(_resolvedName!, style: TextStyle(color: c.success, fontWeight: FontWeight.w700)))
          ]),
        ],
        if (_error != null) ...[
          const SizedBox(height: 6), Text(_error!, style: TextStyle(color: c.danger, fontSize: 12)),
        ],
        const SizedBox(height: 14),
        SizedBox(width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _loading ? null : (_resolvedName == null ? _validateName : _saveAndContinue),
            child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_resolvedName == null ? "Verify Number" : "Save & Continue",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

class _PulsingDots extends StatefulWidget {
  final Color color;
  const _PulsingDots({required this.color});
  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) => AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600)));
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 180), () {
        if (mounted) _ctrls[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) => AnimatedBuilder(
        animation: _ctrls[i],
        builder: (_, __) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 10,
          height: 10 + (_ctrls[i].value * 10),
          decoration: BoxDecoration(
            color: widget.color.withOpacity(0.4 + _ctrls[i].value * 0.6),
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      )),
    );
  }
}
