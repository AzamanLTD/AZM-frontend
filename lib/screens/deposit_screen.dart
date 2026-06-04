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
//   • Mobile Money — fiat top-up via MTN / Vodafone / AirtelTigo (Telecel)
//                    or bank transfer. Posts to /api/deposit/fiat/initiate
//                    and the gateway webhook credits the user once funds
//                    settle.
//
// Design intent: ALL deposit affordances on the dashboard ("Deposit" quick
// action, settings drawer shortcut, anywhere else) route here. The user
// gets one coherent surface with both options instead of guessing which
// flow to pick from a chooser sheet.
// =============================================================================

import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/saved_momo_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/saved_momo_accounts_screen.dart';
import 'package:azaman/services/api_client.dart';

class DepositScreen extends ConsumerStatefulWidget {
  const DepositScreen({
    super.key,
    this.initialTab = DepositTab.crypto,
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: colors.textPrimary, size: 18),
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
            const SizedBox(height: 12),
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
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        dividerColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        tabs: labels.map((l) => Tab(height: 38, text: l)).toList(),
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
      final response =
          await apiClient.get('/wallet/deposit-address/polygon');
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
              Icon(Icons.error_outline_rounded,
                  size: 48, color: colors.danger),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, fontSize: 14)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _fetchDepositAddress,
                icon: Icon(Icons.refresh_rounded, color: colors.accent),
                label: Text('Retry',
                    style: TextStyle(color: colors.accent)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.accent.withOpacity(0.4)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      child: Column(
        children: [
          // ── Network capsule ───────────────────────────────────────────────
          _NetworkCapsule(colors: colors)
              .animate()
              .fadeIn(duration: 320.ms)
              .slideY(begin: -0.2, end: 0, curve: Curves.easeOutCubic),

          const SizedBox(height: 18),

          // ── Premium QR card (frosted, content-tight) ─────────────────────
          _PremiumQrCard(
            colors: colors,
            address: _address ?? '',
          )
              .animate()
              .fadeIn(delay: 120.ms, duration: 420.ms)
              .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),

          const SizedBox(height: 14),

          // ── Address card ──────────────────────────────────────────────────
          _SlenderCard(
            colors: colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AddressLabelRow(colors: colors),
                const SizedBox(height: 8),
                SelectableText(
                  _address ?? '',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    height: 1.5,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _GhostAction(
                        colors: colors,
                        icon: Icons.copy_rounded,
                        label: 'Copy',
                        onTap: () => _copyAddress(colors),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _GhostAction(
                        colors: colors,
                        icon: Icons.ios_share_rounded,
                        label: 'Share',
                        onTap: _shareAddress,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(delay: 220.ms, duration: 380.ms)
              .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),

          const SizedBox(height: 14),

          // ── Warning card ──────────────────────────────────────────────────
          _SlenderCard(
            colors: colors,
            tintColor: colors.warning,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: colors.warning, size: 16),
                    const SizedBox(width: 6),
                    Text('Send only USDC on Polygon',
                        style: TextStyle(
                          color: colors.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        )),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Sending any other token, or USDC on the wrong network '
                  '(Ethereum mainnet, BSC, Tron, etc.) will result in '
                  'permanent loss. Funds credit in 2–5 minutes after '
                  'on-chain confirmation.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(delay: 320.ms, duration: 380.ms)
              .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),
        ],
      ),
    );
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
  bool _isSubmitting = false;
  Map<String, dynamic>? _depositResult;

  static const _providers = [
    _FiatProvider('MTN_MOMO', 'MTN MoMo', Color(0xFFFFCC00)),
    _FiatProvider('VODAFONE_CASH', 'Vodafone Cash', Color(0xFFE60000)),
    _FiatProvider('AIRTELTIGO', 'AirtelTigo / Telecel', Color(0xFF0066CC)),
    _FiatProvider('BANK_TRANSFER', 'Bank Transfer', Color(0xFF2E7D32)),
  ];

  @override
  bool get wantKeepAlive => true;

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
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _initiateDeposit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final response = await apiClient.post('/deposit/fiat/initiate', {
        'amountGhs': amount,
        'provider': _selectedProvider,
        if (_selectedAccountId != null) 'savedAccountId': _selectedAccountId,
        // Susu memo trace (Req 12.4) — the BE persists this on the
        // resulting deposit's transaction metadata so operators can
        // tie a deposit back to the cycle reminder that prompted it.
        if (widget.memo != null && widget.memo!.isNotEmpty)
          'memo': widget.memo,
      });
      final body = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        HapticFeedback.heavyImpact();
        setState(() {
          _depositResult = (body['data'] is Map<String, dynamic>)
              ? body['data'] as Map<String, dynamic>
              : body as Map<String, dynamic>;
          _isSubmitting = false;
        });
      } else {
        setState(() => _isSubmitting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(body['message']?.toString() ??
                  'Failed to initiate deposit'),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _reset() {
    setState(() {
      _depositResult = null;
      _amountController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = ref.watch(themeProvider).colors;

    return _depositResult != null
        ? _buildResult(colors)
        : _buildForm(colors);
  }

  // ── Form ───────────────────────────────────────────────────────────────────
  Widget _buildForm(AzamanColors colors) {
    final accountsAsync = ref.watch(savedMomoProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Deposit From',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          accountsAsync.when(
            loading: () => Padding(
              padding: const EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator(color: colors.accent)),
            ),
            error: (e, _) => Text(e.toString()),
            data: (accounts) {
              if (accounts.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.warning.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.warning.withOpacity(0.30)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: colors.warning, size: 14),
                          const SizedBox(width: 8),
                          Text(
                            'No saved deposit addresses',
                            style: TextStyle(
                                color: colors.warning, fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Save a mobile-money number first. We send the deposit prompt to your saved number — you don\'t enter payment details here.',
                        style: TextStyle(color: colors.textSecondary, fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SavedMomoAccountsScreen(),
                              ),
                            );
                          },
                          icon: Icon(Icons.add_rounded, size: 16, color: colors.warning),
                          label: Text(
                            'Add a Deposit Address',
                            style: TextStyle(color: colors.warning, fontWeight: FontWeight.w800),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.warning.withOpacity(0.40)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                children: accounts
                    .map((a) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _SavedAccountTile(
                            account: a,
                            colors: colors,
                            selected: _selectedAccountId == a.id,
                            onTap: () => setState(() {
                              _selectedAccountId = a.id;
                              _selectedProvider = '${a.provider}_MOMO';
                            }),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 18),
          Text(
            'Amount (GHS)',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          _SlenderCard(
            colors: colors,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '0.00',
                hintStyle: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
                prefixText: 'GH₵ ',
                prefixStyle: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_isSubmitting || _selectedAccountId == null) ? null : _initiateDeposit,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.isDark ? Colors.black : Colors.white,
                disabledBackgroundColor: colors.accent.withOpacity(0.4),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Text(
                      'Send Deposit Prompt',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'We send the prompt to your saved number — approve it on your phone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textTertiary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  // ── Result ────────────────────────────────────────────────────────────────
  Widget _buildResult(AzamanColors colors) {
    final reference = _depositResult?['reference'] ?? '';
    final instructions = _depositResult?['instructions']?.toString() ??
        'Follow the prompt on your device to complete payment.';
    final amount = _depositResult?['amountGhs']?.toString() ??
        _amountController.text;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SlenderCard(
            colors: colors,
            tintColor: colors.success,
            child: Column(
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 44, color: colors.success),
                const SizedBox(height: 10),
                Text(
                  'Deposit Initiated',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'GH₵ $amount via $_selectedProvider',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SlenderCard(
            colors: colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reference',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  reference.toString(),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Instructions',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  instructions,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: _reset,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: colors.divider),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Start another deposit',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiatProvider {
  final String id;
  final String name;
  final Color color;
  const _FiatProvider(this.id, this.name, this.color);
}

class _ProviderTile extends StatelessWidget {
  final _FiatProvider provider;
  final AzamanColors colors;
  final bool selected;
  final VoidCallback onTap;

  const _ProviderTile({
    required this.provider,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? provider.color.withOpacity(0.1)
                : colors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? provider.color.withOpacity(0.7)
                  : colors.divider,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: provider.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.phone_android_rounded,
                    color: provider.color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  provider.name,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: selected
                    ? Icon(Icons.check_circle_rounded,
                        key: const ValueKey('on'),
                        color: provider.color,
                        size: 20)
                    : Icon(Icons.radio_button_unchecked_rounded,
                        key: const ValueKey('off'),
                        color: colors.textTertiary,
                        size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable presentational helpers (private to this screen).
// ─────────────────────────────────────────────────────────────────────────────
class _SlenderCard extends StatelessWidget {
  final AzamanColors colors;
  final Widget child;
  final Color? tintColor;
  final EdgeInsetsGeometry? padding;

  const _SlenderCard({
    required this.colors,
    required this.child,
    this.tintColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tintColor != null
            ? tintColor!.withOpacity(0.06)
            : colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tintColor != null
              ? tintColor!.withOpacity(0.25)
              : colors.divider,
        ),
      ),
      child: child,
    );
  }
}

class _GhostAction extends StatelessWidget {
  final AzamanColors colors;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GhostAction({
    required this.colors,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: colors.accent),
      label: Text(
        label,
        style: TextStyle(
          color: colors.accent,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: colors.accent.withOpacity(0.4)),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

class _NetworkCapsule extends StatelessWidget {
  final AzamanColors colors;
  const _NetworkCapsule({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.accent.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hexagon_outlined, color: colors.accent, size: 14),
          const SizedBox(width: 6),
          Text(
            'Polygon',
            style: TextStyle(
              color: colors.accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 6),
          Container(width: 1, height: 10, color: colors.accent.withOpacity(0.3)),
          const SizedBox(width: 6),
          Text(
            'USDC',
            style: TextStyle(
              color: colors.success,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}


// =============================================================================
// PREMIUM QR CARD — frosted glass plate, gradient ring around the QR,
// stylized eyes/dots, center "bolt" logo plate (covered by H-error correction).
// Replaces the plain white QR rectangle.
// =============================================================================
class _PremiumQrCard extends ConsumerWidget {
  final AzamanColors colors;
  final String address;
  const _PremiumQrCard({required this.colors, required this.address});

  String _short(String addr) {
    if (addr.length < 14) return addr;
    return '${addr.substring(0, 6)}…${addr.substring(addr.length - 4)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final username =
        (user?.username.isNotEmpty ?? false) ? user!.username : 'azaman';

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.accent.withOpacity(0.12),
                Colors.white.withOpacity(0.02),
              ],
            ),
            border: Border.all(
              color: colors.accent.withOpacity(0.25),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.accent.withOpacity(0.18),
                blurRadius: 28,
                spreadRadius: -8,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
          child: Column(
            children: [
              // Top row — chain badge + handle
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF8247E5),
                              Color(0xFF5A2EBA),
                            ],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.hexagon_rounded,
                            color: Colors.white, size: 14),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '@$username',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.success.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: colors.success.withOpacity(0.30),
                          width: 0.7),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.success,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: colors.success,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // QR centerpiece with gradient ring + frosted plate
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [
                      colors.accent.withOpacity(0.55),
                      colors.accentSecondary.withOpacity(0.55),
                    ],
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      QrImageView(
                        data: address,
                        version: QrVersions.auto,
                        size: 196,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.H,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.circle,
                          color: Color(0xFF0B0B0D),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.circle,
                          color: Color(0xFF0B0B0D),
                        ),
                      ),
                      // Center logo plate — H-error correction covers it
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                            color: const Color(0xFF0B0B0D),
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.bolt_rounded,
                          color: Color(0xFF0B0B0D),
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Truncated address chip
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.10),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  _short(address),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    letterSpacing: 0.4,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Scan to deposit USDC',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ADDRESS LABEL ROW — slender section header with accent rule
// =============================================================================
class _AddressLabelRow extends StatelessWidget {
  final AzamanColors colors;
  const _AddressLabelRow({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: colors.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Polygon USDC Address',
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}


// =============================================================================
// SAVED ACCOUNT TILE — slender selectable row used by the deposit form to
// pick which saved MoMo number receives the STK push.
// =============================================================================
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
        'VODAFONE' => const Color(0xFFE60000),
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
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: selected ? pcolor.withOpacity(0.10) : colors.card.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? pcolor.withOpacity(0.55) : colors.divider,
            width: selected ? 1.4 : 0.7,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: pcolor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.smartphone_rounded, color: pcolor, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        account.nickname,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (account.isPrimary) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.star_rounded, color: colors.warning, size: 12),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${account.provider} · ${account.phoneNumber}',
                    style: TextStyle(color: colors.textTertiary, fontSize: 11),
                  ),
                  if (account.accountName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      account.accountName!,
                      style: TextStyle(
                          color: colors.success,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? pcolor : colors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
