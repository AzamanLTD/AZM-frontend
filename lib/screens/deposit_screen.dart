// =============================================================================
// AZAMAN — ADD CASH  (deposit redesign, 2026-10)
//
// The deposit surface redesigned as ONE composed product sheet:
//
//   [X] Add Cash            ← the single authoritative close affordance
//   Fiat | Crypto           ← the switch, immediately below the header
//   GH₵ 0                   ← odometer amount, huge, the visual anchor
//   [50][100][200][500]     ← quick amounts
//   1 2 3 / 4 5 6 / 7 8 9 / . 0 ⌫   ← custom keypad
//   [network] Name / 024 … / ˅      ← ONE payment-method row → selector sheet
//   [ Add Cash ]            ← CTA, bottom safe area
//
// The canonical `/deposit` route (NEW-A) is unchanged: the rise transition at
// route level is what makes this surface arrive from the bottom, and a
// deliberate downward pull dismisses it (see _DepositScreenState).
//
// ── FINANCIAL CONTRACT (do not weaken) ────────────────────────────────────────
// The visual layer changed completely in the 2026-10 redesign; the financial
// layer did NOT:
//   • /deposit/validate-name confirmation before mutation
//   • /deposit/fiat/initiate/moolre via postFinancial with a durable
//     FinancialOperationRef (one key per logical initiation, retried safely)
//   • the OTP branch (requiresOtp=true → /deposit/fiat/initiate/moolre/otp)
//   • socket confirmation (SocketService.onDepositSuccess)
//   • demo-mode auto-confirmation
//   • ?amount= pre-fill + ?memo= trace (Susu reminder deep links)
// The UI may change; this contract may not.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:share_plus/share_plus.dart';

import 'package:azaman/config.dart';
import 'package:azaman/providers/saved_momo_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/utils/amount_input.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/amount_keypad.dart';
import 'package:azaman/widgets/animated_qr_dust.dart';
import 'package:azaman/widgets/momo_network.dart';
import 'package:azaman/widgets/odometer_number.dart';
import 'package:azaman/widgets/scale_tap.dart';
import 'package:azaman/screens/saved_wallets_screen.dart' show AddPayoutSheet;

// =============================================================================
// DEPOSIT SCREEN — the Add Cash surface
// =============================================================================

class DepositScreen extends ConsumerStatefulWidget {
  const DepositScreen({
    super.key,
    this.initialTab = DepositTab.fiat,
    this.prefillAmount,
    this.memo,
  });

  final DepositTab initialTab;

  /// Pre-fill amount for the Fiat tab. Set when the screen is reached via a
  /// deep link such as `/deposit?amount=12.34&memo=susu:abc`, most often the
  /// Susu T-24h reminder notification (Req 12.3 / 12.4). The value must be a
  /// positive decimal with at most two fractional digits, otherwise we
  /// ignore it and leave the input blank.
  final String? prefillAmount;

  /// Opaque memo string (e.g. `susu:<susuId>`). Logged into the resulting
  /// deposit's metadata server-side so operators can trace deposits back to
  /// the cycle that prompted them. Not surfaced visually.
  final String? memo;

  @override
  ConsumerState<DepositScreen> createState() => _DepositScreenState();
}

enum DepositTab { crypto, fiat }

class _DepositScreenState extends ConsumerState<DepositScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  // ── Pull-down dismissal ─────────────────────────────────────────────────
  // The Add Cash surface follows a downward finger pull with resistance and
  // pops the route once the pull is committed (threshold or fling velocity).
  // Below threshold it springs back to rest. Reduced motion keeps the
  // interaction semantics and drops the travel choreography.
  double _dragDy = 0;
  double _settleFrom = 0;
  bool _armed = false;
  late final AnimationController _settle;

  static const double _dragResistance = 0.55;
  static const double _maxDragTravel = 240;
  static const double _commitThreshold = 110;
  static const double _flingVelocity = 700;

  @override
  void initState() {
    super.initState();
    // Phase 4 (Susu Sprint, 2026-05-31): when the screen is opened via a
    // deep link carrying ?amount=… (e.g. the T-24h reminder), force the Fiat
    // tab so the pre-filled amount is immediately visible.
    final hasPrefill = (widget.prefillAmount?.isNotEmpty ?? false);
    _tabController = TabController(
      length: 2,
      initialIndex: hasPrefill || widget.initialTab == DepositTab.fiat ? 1 : 0,
      vsync: this,
    );
    _settle = AnimationController(
      vsync: this,
      duration: MotionTokens.control,
      value: 1,
    );
    // When the spring-back completes, the builder falls back from the
    // animated value to [_dragDy]. [_dragDy] must therefore be at rest by
    // then, or the sheet visibly jumps back to the old dragged offset the
    // frame after the spring finishes.
    _settle.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      if (_dragDy == 0 && _settleFrom == 0) return;
      if (mounted) {
        setState(() {
          _dragDy = 0;
          _settleFrom = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _settle.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _closeSurface() {
    AzamanHaptics.navigation();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  void _onDragStart(DragStartDetails _) {
    // A new gesture may land while a spring-back is still running. The
    // builder renders the animated offset while animating, so the drag
    // must resume from the on-screen position — NOT from the stale
    // pre-spring [_dragDy], which would visibly slam the sheet back down.
    if (_settle.isAnimating) {
      final visual =
          _settleFrom * (1.0 - MotionTokens.enter.transform(_settle.value));
      _settle.stop();
      setState(() {
        _dragDy = visual;
        _settleFrom = 0;
        _armed = visual >= _commitThreshold;
      });
      return;
    }
    _armed = false;
    _settle.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (details.delta.dy <= 0 && _dragDy == 0) return;
    final next = (_dragDy + details.delta.dy * _dragResistance).clamp(
      0.0,
      _maxDragTravel,
    );
    if (next == _dragDy) return;
    // The threshold haptic fires EXACTLY ONCE per crossing (see
    // AzamanHaptics.threshold) — not on every frame past the line.
    if (!_armed && next >= _commitThreshold) {
      _armed = true;
      AzamanHaptics.threshold();
    } else if (_armed && next < _commitThreshold) {
      _armed = false;
    }
    setState(() => _dragDy = next);
  }

  void _onDragEnd(DragEndDetails details) {
    final committed =
        _dragDy >= _commitThreshold ||
        details.velocity.pixelsPerSecond.dy >= _flingVelocity;
    if (committed) {
      _closeSurface(); // keep the current offset; the route animates out
      return;
    }
    if (_dragDy <= 0) return;
    if (MediaQuery.of(context).disableAnimations) {
      setState(() => _dragDy = 0);
      return;
    }
    // Spring back to rest.
    _settleFrom = _dragDy;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          // Translucent so taps pass through to buttons beneath; this
          // recognizer only claims *vertical drag* gestures.
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: _onDragStart,
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          child: AnimatedBuilder(
            animation: _settle,
            builder: (context, child) {
              final double dy = _settle.isAnimating
                  ? _settleFrom *
                        (1.0 - MotionTokens.enter.transform(_settle.value))
                  : _dragDy;
              return Transform.translate(offset: Offset(0, dy), child: child);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AddCashHeader(colors: colors, onClose: _closeSurface),
                _FiatCryptoSwitch(controller: _tabController, colors: colors),
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
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER — [X] Add Cash. The X is the ONE close affordance: no back arrow,
// no duplicate close controls.
// ─────────────────────────────────────────────────────────────────────────────

class _AddCashHeader extends StatelessWidget {
  const _AddCashHeader({required this.colors, required this.onClose});

  final AzamanColors colors;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Close Add Cash',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.softSurface,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.close, size: 18, color: colors.textPrimary),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Add Cash',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FIAT | CRYPTO SWITCH — a restrained two-way switch. The selected side
// carries the accent underline; there is no heavy segmented container. The
// TabController keeps the selection stable across rebuilds, and TabBarView
// keeps the Crypto panel lazy: landing on Fiat does NOT fetch the Polygon
// deposit address.
// ─────────────────────────────────────────────────────────────────────────────

class _FiatCryptoSwitch extends StatelessWidget {
  const _FiatCryptoSwitch({required this.controller, required this.colors});

  final TabController controller;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    // The selector must track the controller, not just its own taps: a
    // swipe on the TabBarView (or a programmatic animateTo) changes the
    // visible content without rebuilding a StatelessWidget sibling —
    // leaving the selector claiming the wrong tab is selected.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _switchTab('Fiat', 1),
              const SizedBox(width: 28),
              _switchTab('Crypto', 0),
            ],
          ),
        );
      },
    );
  }

  Widget _switchTab(String label, int index) {
    final selected = controller.index == index;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label tab',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (controller.index == index) return;
          AzamanHaptics.toggle();
          controller.animateTo(
            index,
            duration: MotionTokens.control,
            curve: MotionTokens.enter,
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? colors.textPrimary : colors.textTertiary,
                fontSize: 15,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: MotionTokens.control,
              curve: MotionTokens.enter,
              width: 26,
              height: 3,
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
}

// =============================================================================
// FIAT PANEL — odometer amount, quick pills, keypad, method row, CTA.
// =============================================================================

class _FiatDepositPanel extends ConsumerStatefulWidget {
  const _FiatDepositPanel({this.prefillAmount, this.memo});

  final String? prefillAmount;
  final String? memo;

  @override
  ConsumerState<_FiatDepositPanel> createState() => _FiatDepositPanelState();
}

class _FiatDepositPanelState extends ConsumerState<_FiatDepositPanel>
    with AutomaticKeepAliveClientMixin {
  // ── Amount state machine ────────────────────────────────────────────────
  // The keypad writes into a raw digits string; the odometer renders it.
  // Invariants, enforced here (the ONLY place that can produce an amount):
  //   • '' renders as 0 and parses to "no amount"
  //   • at most one decimal point
  //   • at most two fractional digits
  //   • no leading-zero buildup ('0' + '5' → '5')
  //   • no negative values (no sign key exists)
  //   • at most 7 integer digits (GH₵ 9,999,999.99 covers every product cap)
  String _amountRaw = '';

  // The user's EXPLICIT payment-method choice (survives selector open/close
  // and every rebuild). Auto-selection (primary account / lone account) is
  // derived, never silently stored.
  String? _selectedAccountId;
  bool _isSubmitting = false;

  // r42: one key per LOGICAL deposit initiation, reused across retries
  // (a lost response may mean the initiation already committed); retired
  // on any answered non-409 outcome.
  // r42 OPERATION-INSTANCE MODEL: the action id names the operation TYPE.
  // Each genuinely new deposit initiation gets a fresh durable instance;
  // the ref is this flow's retry handle — a re-tap after a lost response
  // retries the SAME instance (same key), and a materially different body
  // begins a genuinely new instance without disturbing the old one.
  static const _initiateActionId = 'deposit.fiat.moolre.initiate';
  final _initiateRef = FinancialOperationRef();
  Map<String, dynamic>? _depositResult;

  // ── Moolre on-ramp (2026-06-23) ──────────────────────────────────────────
  // Name-validation dialog + OTP branch (Moolre TP14 returns requiresOtp).
  String? _resolvedName;
  // The account whose number actually produced [_resolvedName]. The name
  // may only be shown for, or charged against, THIS account — a stale name
  // from a previously selected account must never survive a selection
  // change (release-level review blocker 3).
  String? _validatedAccountId;
  bool _isValidatingName = false;
  bool _requiresOtp = false;
  String? _pendingReference;
  final _otpController = TextEditingController();
  bool _isConfirmingOtp = false;
  bool _depositConfirmed = false;

  @override
  bool get wantKeepAlive => true;

  /// Map the canonical saved-account provider (MTN | TELECEL | AIRTELTIGO,
  /// VODAFONE legacy still accepted) to the enum the backend's
  /// `initiateMoolreFiatDeposit` MOMO set accepts
  /// (MTN_MOMO | TELECEL_CASH | AIRTELTIGO). Telecel is the Vodafone Ghana
  /// rebrand — the backend treats VODAFONE and TELECEL as the same channel —
  /// so both map to TELECEL_CASH. The same enum is accepted by
  /// `/deposit/validate-name`, so one mapping serves both calls.
  String _backendProvider(String provider) {
    if (provider == 'MTN_MOMO' ||
        provider == 'VODAFONE_CASH' ||
        provider == 'AIRTELTIGO') {
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
    // amount when the screen was opened with `?amount=…`. Validate the value
    // has at most two fractional digits and is strictly > 0; anything else
    // is dropped silently and the input stays empty so the user notices and
    // re-enters.
    final raw = widget.prefillAmount?.trim();
    if (raw != null && raw.isNotEmpty) {
      final ok = RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(raw);
      final v = double.tryParse(raw);
      if (ok && v != null && v > 0) {
        _amountRaw = raw;
      }
    }
    SocketService.instance.onDepositSuccess((
      amountGhs,
      amountUsdc,
      provider,
      reference,
    ) {
      if (!mounted) return;
      final pendingRef =
          _pendingReference ?? (_depositResult?['reference']?.toString() ?? '');
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
    });
  }

  @override
  void dispose() {
    SocketService.instance.onDepositSuccess((a, b, c, d) {});
    _otpController.dispose();
    super.dispose();
  }

  // ── Amount input state machine ──────────────────────────────────────────

  void _onKeypadKey(String key) {
    if (_isSubmitting || _isValidatingName) return;
    setState(() => _amountRaw = AmountInput.applyKey(_amountRaw, key));
  }

  /// The amount as the user entered it, or null when there is no amount.
  /// Every invalid-state rule (single decimal point, two fractional digits,
  /// leading zeros, 7-digit integer cap) is enforced by the pure
  /// [AmountInput] state machine — the same code the unit tests exercise.
  double? get _amountValue => AmountInput.value(_amountRaw);

  /// The odometer string: grouped integer part, fraction exactly as typed.
  /// Empty input displays as '0'.
  String get _amountDisplay => AmountInput.display(_amountRaw);

  // ── Payment-method selection ─────────────────────────────────────────────

  /// The account that actually backs this deposit. Priority:
  ///   1. the user's explicit choice (if it still exists),
  ///   2. the primary account,
  ///   3. the ONLY account when exactly one exists,
  ///   4. null — never an arbitrary first account.
  SavedMomoAccount? _currentAccount(List<SavedMomoAccount> accounts) {
    if (_selectedAccountId != null) {
      for (final a in accounts) {
        if (a.id == _selectedAccountId) return a;
      }
    }
    SavedMomoAccount? primary;
    for (final a in accounts) {
      if (a.isPrimary) {
        primary = a;
        break;
      }
    }
    if (primary != null) return primary;
    if (accounts.length == 1) return accounts.single;
    return null;
  }

  // ── Financial flow (unchanged contract) ───────────────────────────────────

  /// Resolve the registered account name via Moolre, show a confirmation
  /// dialog, then proceed to the deposit. Name validation is best-effort —
  /// if it fails we proceed without it rather than block the deposit.
  Future<void> _validateAndConfirm() async {
    final account = _currentAccount(
      ref.read(savedMomoProvider).valueOrNull ?? const <SavedMomoAccount>[],
    );
    if (account == null) return;

    // Clear any name from a PREVIOUS validation before this one resolves —
    // the result below belongs to THIS account and no other.
    setState(() {
      _isValidatingName = true;
      _resolvedName = null;
      _validatedAccountId = null;
    });
    try {
      final resp = await apiClient.post('/deposit/validate-name', {
        'phoneNumber': account.phoneNumber,
        'provider': _backendProvider(account.provider),
      });
      final body = jsonDecode(resp.body);
      if (resp.statusCode == 200 && body['data'] != null) {
        if (mounted) {
          setState(() {
            _resolvedName = body['data'] as String?;
            _validatedAccountId = account.id;
          });
        }
      }
    } catch (_) {
      // Name validation is optional — proceed without it if it fails.
    } finally {
      if (mounted) setState(() => _isValidatingName = false);
    }

    // The payment-method row is disabled while validation is in flight, but
    // defense-in-depth: if the selection is no longer the account that was
    // validated, abort. The newly selected account must be validated on its
    // own — a name resolved for account A can never confirm or charge
    // account B.
    if (_currentAccount(
          ref.read(savedMomoProvider).valueOrNull ?? const <SavedMomoAccount>[],
        )?.id !=
        account.id) {
      if (mounted) {
        setState(() {
          _resolvedName = null;
          _validatedAccountId = null;
        });
      }
      return;
    }

    if (_resolvedName != null && mounted) {
      final colors = ref.read(themeProvider).colors;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: colors.surface,
          title: Text(
            'Confirm account',
            style: TextStyle(color: colors.textPrimary),
          ),
          content: Text(
            'Paying to: $_resolvedName\nIs this correct?',
            style: TextStyle(color: colors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.textTertiary),
              ),
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

    await _initiateDeposit(account);
  }

  /// [validatedAccount] is the exact account whose registered name the
  /// user confirmed (or that failed name-validation best-effort) — the
  /// deposit initiates against THIS snapshot, never a re-resolved
  /// "current" selection that might have changed in between.
  Future<void> _initiateDeposit([SavedMomoAccount? validatedAccount]) async {
    final amount = _amountValue;
    if (amount == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    final account =
        validatedAccount ??
        _currentAccount(
          ref.read(savedMomoProvider).valueOrNull ?? const <SavedMomoAccount>[],
        );
    if (account == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a payment account')));
      return;
    }
    // Belt and suspenders: a name that was resolved for a different account
    // must never reach the user or the wire.
    if (_resolvedName != null && _validatedAccountId != account.id) {
      setState(() {
        _resolvedName = null;
        _validatedAccountId = null;
      });
      await _validateAndConfirm();
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // All saved accounts in this picker are Mobile Money (MTN / Telecel /
      // AirtelTigo), so every deposit routes through the Moolre PIN-push
      // on-ramp.
      final body = <String, dynamic>{
        'amountGhs': amount,
        'provider': _backendProvider(account.provider),
        'phoneNumber': account.phoneNumber,
        // Susu memo trace (Req 12.4) — persisted into the deposit's
        // metadata server-side so operators can tie a deposit back to the
        // cycle reminder that prompted it.
        if (widget.memo != null && widget.memo!.isNotEmpty) 'memo': widget.memo,
      };
      // r42: initiating a fiat deposit is a protected mutation — one key
      // per LOGICAL initiation (the OTP confirmation is a separate route),
      // reused across retries of the same initiation.
      final response = await apiClient.postFinancial(
        '/deposit/fiat/initiate/moolre',
        body,
        operationType: _initiateActionId,
        ref: _initiateRef,
      );
      final data = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        AzamanHaptics.commit();
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
          // In demo mode there's no real Moolre prompt to approve —
          // auto-confirm after a short delay so the user sees the full
          // deposit success flow.
          if (AppConfig.demoMode) {
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && _depositResult != null && !_depositConfirmed) {
                setState(() => _depositConfirmed = true);
              }
            });
          }
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
        AzamanHaptics.commit();
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
              content: Text(
                body['message']?.toString() ?? 'OTP verification failed',
              ),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isConfirmingOtp = false);
      if (mounted) {
        final msg = (e is ApiException)
            ? e.message
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
      _validatedAccountId = null;
      _depositConfirmed = false;
      _otpController.clear();
      _amountRaw = '';
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

  // ── Resting form: the composed Add Cash instrument ──────────────────────

  Widget _buildForm(AzamanColors colors) {
    final accountsAsync = ref.watch(savedMomoProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 620;
        final bottomInset = MediaQuery.of(context).padding.bottom;

        return Column(
          children: [
            // Negative space above the amount — deliberate, proportional.
            Expanded(
              flex: compact ? 1 : 3,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          AzMoney.ghsSymbol,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: compact ? 24 : 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // The amount is the visual anchor. Empty input
                      // renders as 0; only changed digits roll.
                      OdometerNumber(
                        value: _amountDisplay,
                        style: AzText.money(
                          colors.textPrimary,
                          size: compact ? 52 : 64,
                        ),
                        semanticsLabel: '${AzMoney.ghsSymbol} $_amountDisplay',
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Quick amounts — replace the current amount, roll the odometer.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final amt in const [50, 100, 200, 500])
                    _QuickAmountPill(
                      colors: colors,
                      amount: amt,
                      selected: _amountRaw == amt.toString(),
                      onTap: () {
                        if (_isSubmitting || _isValidatingName) return;
                        AzamanHaptics.toggle();
                        setState(() => _amountRaw = amt.toString());
                      },
                    ),
                ],
              ),
            ),
            SizedBox(height: compact ? 10 : 16),

            // The keypad stays fixed while the amount changes — it never
            // scrolls independently and never moves under the CTA.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: AmountKeypad(
                onKey: _onKeypadKey,
                enabled: !_isSubmitting && !_isValidatingName,
                rowHeight: compact ? 46 : 54,
              ),
            ),

            // Payment method — ONE row, not a list.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: accountsAsync.when(
                loading: () => const _MethodRowSkeleton(),
                error: (e, _) => _MethodErrorRow(
                  colors: colors,
                  onRetry: () => ref.invalidate(savedMomoProvider),
                ),
                data: (accounts) {
                  final account = _currentAccount(accounts);
                  // No payment-method changes while a validation or a
                  // submission is in flight — a mid-validation switch is
                  // exactly the race that would confirm one account's name
                  // and charge another (release-level review blocker 3).
                  final bool locked = _isSubmitting || _isValidatingName;
                  if (accounts.isEmpty) {
                    return _AddMethodRow(
                      colors: colors,
                      onTap: locked ? null : () => _openAddAccountSheet(),
                    );
                  }
                  if (account == null) {
                    return _ChooseMethodRow(
                      colors: colors,
                      onTap: locked
                          ? null
                          : () => _showPaymentSelector(colors, accounts),
                    );
                  }
                  return _SelectedMethodRow(
                    colors: colors,
                    account: account,
                    onTap: locked
                        ? null
                        : () => _showPaymentSelector(colors, accounts),
                  );
                },
              ),
            ),

            // CTA — bottom safe area, never obscured by the keypad.
            Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 12 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PrimaryButton(
                    colors: colors,
                    label: _isValidatingName
                        ? 'Checking account…'
                        : _isSubmitting
                        ? 'Sending prompt…'
                        : 'Add Cash',
                    onTap:
                        (_isSubmitting ||
                            _isValidatingName ||
                            _amountValue == null ||
                            _currentAccount(
                                  accountsAsync.valueOrNull ??
                                      const <SavedMomoAccount>[],
                                ) ==
                                null)
                        ? null
                        : _validateAndConfirm,
                    isBusy: _isSubmitting || _isValidatingName,
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: _ctaHint(
                      colors,
                      accounts:
                          accountsAsync.valueOrNull ??
                          const <SavedMomoAccount>[],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _ctaHint(
    AzamanColors colors, {
    required List<SavedMomoAccount> accounts,
  }) {
    final hasAccount = _currentAccount(accounts) != null;
    final String text;
    if (accounts.isEmpty) {
      text = 'Add a mobile money account to continue.';
    } else if (!hasAccount) {
      text = 'Choose a payment method to continue.';
    } else if (_amountValue == null) {
      text = 'Enter an amount to continue.';
    } else {
      text = 'Approve to complete the deposit.';
    }
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: colors.textTertiary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
    );
  }

  void _openAddAccountSheet() {
    AzamanHaptics.navigation();
    AddPayoutSheet.show(
      context,
      onSaved: () {
        if (!mounted) return;
        ref.invalidate(savedMomoProvider);
      },
      initialTab: 'mobileMoney',
    );
  }

  Future<void> _showPaymentSelector(
    AzamanColors colors,
    List<SavedMomoAccount> accounts,
  ) async {
    AzamanHaptics.navigation();
    final maxHeight = MediaQuery.of(context).size.height * 0.72;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => _PaymentSelectorSheet(
        colors: colors,
        accounts: accounts,
        selectedId: _selectedAccountId ?? _currentAccount(accounts)?.id,
        maxHeight: maxHeight,
        onSelect: (account) {
          Navigator.pop(sheetCtx);
          setState(() => _selectedAccountId = account.id);
        },
        onAdd: () {
          Navigator.pop(sheetCtx);
          _openAddAccountSheet();
        },
      ),
    );
  }

  // ── Result ────────────────────────────────────────────────────────────
  Widget _buildResult(AzamanColors colors) {
    final reference = _depositResult?['reference'] ?? '';
    final instructions =
        _depositResult?['instructions']?.toString() ??
        'Follow the prompt on your device to complete payment.';
    final account = _currentAccount(
      ref.read(savedMomoProvider).valueOrNull ?? const <SavedMomoAccount>[],
    );
    final networkName = account != null
        ? MomoNetwork.of(account.provider).displayName
        : '';
    final amount = _depositResult?['amountGhs']?.toString() ?? _amountDisplay;

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
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: _depositConfirmed
                ? Column(
                    key: const ValueKey("confirmed"),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Lottie.asset(
                        "assets/animations/success.json",
                        width: 110,
                        height: 110,
                        repeat: false,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Deposit Confirmed!",
                        style: TextStyle(
                          color: colors.success,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Your wallet has been funded.",
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  )
                : Column(
                    key: const ValueKey("waiting"),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PulsingDots(color: colors.accent),
                      const SizedBox(height: 14),
                      Text(
                        "Waiting for confirmation...",
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Approve the prompt on your phone.",
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
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
                    'Prompt sent to $networkName',
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

  // ── OTP entry ───────────────────────────────────────────────────────────
  // Shown when Moolre returns requiresOtp=true (TP14). The user enters the
  // code sent to their registered phone; _confirmOtp posts it to the OTP
  // endpoint.
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
            body:
                'Enter the code sent to your registered phone to authorise '
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
            label: _isConfirmingOtp ? 'Verifying…' : 'Confirm deposit',
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
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.textTertiary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QUICK AMOUNT PILL
// ─────────────────────────────────────────────────────────────────────────────

class _QuickAmountPill extends StatelessWidget {
  const _QuickAmountPill({
    required this.colors,
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final AzamanColors colors;
  final int amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${AzMoney.ghsSymbol} $amount',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: MotionTokens.control,
          curve: MotionTokens.enter,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? colors.accent.withValues(alpha: 0.14)
                : colors.softSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? colors.accent
                  : colors.border.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          child: Text(
            '${AzMoney.ghsSymbol} $amount',
            style: TextStyle(
              color: selected ? colors.accent : colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAYMENT METHOD ROW — the single selected-method surface.
// Primary identity: the verified registered name (accountName) when one
// exists; the nickname is the fallback, never the other way around.
// ─────────────────────────────────────────────────────────────────────────────

class _SelectedMethodRow extends StatelessWidget {
  const _SelectedMethodRow({
    required this.colors,
    required this.account,
    required this.onTap,
  });

  final AzamanColors colors;
  final SavedMomoAccount account;

  /// Null while a validation or submission is in flight — no method
  /// changes during that window (see _validateAndConfirm).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final network = MomoNetwork.of(account.provider);
    // Verified registered name wins; nickname is the fallback.
    final name =
        (account.accountName != null && account.accountName!.trim().isNotEmpty)
        ? account.accountName!
        : account.nickname;
    final phone = MomoNetwork.formatPhone(account.phoneNumber);

    return ScaleTap(
      onTap: onTap,
      child: Semantics(
        button: true,
        label:
            'Payment method: $name, ${network.displayName}, $phone. '
            'Double tap to change.',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.softSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colors.border.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              MomoNetworkBadge(provider: account.provider, showLabel: false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (account.isPrimary) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.star_rounded,
                            color: colors.warning,
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      phone,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.expand_more, color: colors.textTertiary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// No saved accounts at all: an honest call-to-add, never a fabricated
/// payment method.
class _AddMethodRow extends StatelessWidget {
  const _AddMethodRow({required this.colors, required this.onTap});

  final AzamanColors colors;

  /// Null while a validation or submission is in flight — no method
  /// changes during that window (see _validateAndConfirm).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Add mobile money account',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: colors.softSurface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colors.accent.withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.add_circle_outline, color: colors.accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Add mobile money account',
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Accounts exist but none is auto-selectable (multiple, none primary):
/// the user must choose — we never silently pick the first.
class _ChooseMethodRow extends StatelessWidget {
  const _ChooseMethodRow({required this.colors, required this.onTap});

  final AzamanColors colors;

  /// Null while a validation or submission is in flight — no method
  /// changes during that window (see _validateAndConfirm).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Choose a payment method',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: colors.softSurface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colors.border.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: colors.textTertiary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Choose a payment method',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.expand_more, color: colors.textTertiary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodRowSkeleton extends ConsumerWidget {
  const _MethodRowSkeleton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: colors.softSurface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }
}

class _MethodErrorRow extends StatelessWidget {
  const _MethodErrorRow({required this.colors, required this.onRetry});

  final AzamanColors colors;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Couldn’t load saved accounts.',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'Retry',
              style: TextStyle(
                color: colors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAYMENT SELECTOR — compact bottom sheet listing saved accounts + the
// add-account action. The user's choice survives opening and closing.
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentSelectorSheet extends StatelessWidget {
  const _PaymentSelectorSheet({
    required this.colors,
    required this.accounts,
    required this.selectedId,
    required this.maxHeight,
    required this.onSelect,
    required this.onAdd,
  });

  final AzamanColors colors;
  final List<SavedMomoAccount> accounts;
  final String? selectedId;
  final double maxHeight;
  final ValueChanged<SavedMomoAccount> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Payment method',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Close payment methods',
                    excludeSemantics: true,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close,
                        color: colors.textTertiary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: accounts.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No saved mobile money accounts yet. Add one to '
                        'deposit with MoMo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13.5,
                          height: 1.5,
                        ),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      children: [
                        for (final account in accounts)
                          _PaymentOptionRow(
                            colors: colors,
                            account: account,
                            selected: account.id == selectedId,
                            onTap: () => onSelect(account),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: _AddMethodRow(colors: colors, onTap: onAdd),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentOptionRow extends StatelessWidget {
  const _PaymentOptionRow({
    required this.colors,
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final AzamanColors colors;
  final SavedMomoAccount account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final network = MomoNetwork.of(account.provider);
    final name =
        (account.accountName != null && account.accountName!.trim().isNotEmpty)
        ? account.accountName!
        : account.nickname;

    return Semantics(
      button: true,
      selected: selected,
      label:
          '$name, ${network.displayName}, '
          '${MomoNetwork.formatPhone(account.phoneNumber)}',
      excludeSemantics: true,
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: MomoNetworkBadge(provider: account.provider, showLabel: false),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          '${network.displayName} · ${MomoNetwork.formatPhone(account.phoneNumber)}',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        trailing: AnimatedContainer(
          duration: MotionTokens.microInteraction,
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: selected ? colors.accent : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? colors.accent
                  : colors.border.withValues(alpha: 0.8),
              width: 1.6,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, size: 15, color: Colors.black)
              : null,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CRYPTO PANEL — deposit USDC on Polygon.
// A deliberately different composition from Fiat: the QR is the main visual,
// the address is copyable/shareable, and the network statement is explicit,
// never buried.
// Fetch is lazy: the TabBarView inflates this panel only when the user
// switches to Crypto, so landing on Fiat never fetches the address.
// ─────────────────────────────────────────────────────────────────────────────

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
    AzamanHaptics.confirm();
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
    AzamanHaptics.navigation();
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                color: colors.accent,
                strokeWidth: 2.6,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading your deposit address…',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 44, color: colors.danger),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 620;
        final qrSize = (constraints.maxWidth - 110)
            .clamp(compact ? 160.0 : 190.0, 250.0)
            .toDouble();

        return Column(
          children: [
            Expanded(
              flex: 2,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Deposit USDC',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: compact ? 20 : 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Network identity — explicit, not decorative.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.softSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF8247E5).withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.hexagon_outlined,
                            color: Color(0xFF8247E5),
                            size: 13,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Polygon',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // The QR is the main visual.
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: AnimatedQrDust(
                  data: _address ?? '',
                  size: qrSize,
                  inkColor: const Color(0xFF141416),
                  backgroundColor: Colors.white,
                  errorCorrectLevel: 0, // QrErrorCorrectLevel.M = 0
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Shortened visually; the FULL address stays available to
            // semantics, copy and share.
            Semantics(
              label: 'Polygon USDC deposit address: ${_address ?? ''}',
              // A standalone node: the full address must never merge with
              // neighbouring announcements.
              container: true,
              excludeSemantics: true,
              child: Text(
                _short(_address ?? ''),
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  letterSpacing: 0.1,
                ),
              ),
            ),
            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _PrimaryButton(
                      colors: colors,
                      label: 'Copy address',
                      onTap: _address == null
                          ? null
                          : () => _copyAddress(colors),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _IconActionButton(
                    colors: colors,
                    icon: Icons.share_outlined,
                    tooltip: 'Share address',
                    onTap: _address == null ? null : _shareAddress,
                  ),
                ],
              ),
            ),

            Expanded(
              flex: 1,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Send only USDC on the Polygon network. '
                    'Other tokens or networks will be lost.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _short(String addr) {
    if (addr.length < 14) return addr;
    return '${addr.substring(0, 6)}…${addr.substring(addr.length - 4)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED LOW-LEVEL PANEL PIECES (OTP / result views reuse these)
// ─────────────────────────────────────────────────────────────────────────────

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

  const _PanelCard({required this.colors, required this.child, this.fillColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: enabled ? colors.accent : colors.accent.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              height: 56,
              alignment: Alignment.center,
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
          ),
        ),
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  final AzamanColors colors;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _IconActionButton({
    required this.colors,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      enabled: onTap != null,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: colors.softSurface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              child: Icon(icon, color: colors.textPrimary, size: 20),
            ),
          ),
        ),
      ),
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
    _ctrls = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 180), () {
        if (mounted) _ctrls[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (i) => AnimatedBuilder(
          animation: _ctrls[i],
          builder: (_, __) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 10,
            height: 10 + (_ctrls[i].value * 10),
            decoration: BoxDecoration(
              color: widget.color.withValues(
                alpha: 0.4 + _ctrls[i].value * 0.6,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ),
    );
  }
}
