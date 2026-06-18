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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:azaman/providers/saved_momo_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/saved_momo_accounts_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:hugeicons_pro/hugeicons.dart';

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
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            HugeIconsSolid.arrowLeft01,
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
              Icon(HugeIconsSolid.alertCircle, size: 48, color: colors.danger),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _fetchDepositAddress,
                icon: Icon(HugeIconsSolid.refresh01, color: colors.accent),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
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
        if (widget.memo != null && widget.memo!.isNotEmpty) 'memo': widget.memo,
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
              content: Text(
                body['message']?.toString() ?? 'Failed to initiate deposit',
              ),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
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

    return _depositResult != null ? _buildResult(colors) : _buildForm(colors);
  }

  // ── Form ───────────────────────────────────────────────────────────────────
  Widget _buildForm(AzamanColors colors) {
    final accountsAsync = ref.watch(savedMomoProvider);
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              icon: HugeIconsSolid.alertCircle,
              accent: colors.danger,
              text: e.toString(),
            ),
            data: (accounts) {
              if (accounts.isEmpty) {
                return _PanelCard(
                  colors: colors,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add a mobile money number first',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _PrimaryButton(
                        colors: colors,
                        label: 'Add saved number',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SavedMomoAccountsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              }
              return _PanelCard(
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
                              _selectedProvider = '${a.provider}_MOMO';
                            }),
                          ),
                        ),
                      )
                      .toList(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
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
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'GH₵ ',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 80),
                      child: IntrinsicWidth(
                        child: TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            filled: false,
                            hintText: '0.00',
                            hintStyle: TextStyle(
                              color: colors.textTertiary,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PrimaryButton(
            colors: colors,
            label: _isSubmitting ? 'Sending prompt...' : 'Send deposit prompt',
            onTap: (_isSubmitting || _selectedAccountId == null)
                ? null
                : _initiateDeposit,
            isBusy: _isSubmitting,
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
          _PrimaryButton(
            colors: colors,
            label: 'Start another deposit',
            onTap: _reset,
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
                icon: HugeIconsSolid.share01,
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
              child: Icon(HugeIconsSolid.smartPhone01, color: pcolor, size: 18),
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
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (account.isPrimary) ...[
                        const SizedBox(width: 6),
                        Icon(
                          HugeIconsSolid.star,
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
                    ? HugeIconsSolid.checkmarkCircle01
                    : HugeIconsSolid.circle,
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
