// =============================================================================
// AZAMAN — AZM VISA CARD (sample surface) + CARD PIN GATE  (NEW-HOME §5, §6)
//
// The second card in the Home deck is a SAMPLE Visa-concept card for the
// product experience:
//   * premium AZM card visual, but unmistakably safe demo UI ("SAMPLE" tag,
//     masked number, placeholder expiry — never a real credential)
//   * "powered by Flutterwave" mark, as the brief requests for the sample
//     surface. Production issuer/network details remain sourced from the
//     actual card programme — the visual does not claim a production
//     network/API relationship.
//
// Architecture seam: everything issuer-shaped hides behind
// [AzmCardProgramme]. [DemoCardProgramme] is the explicitly-placeholder
// implementation: session-only, never persisted, never logged. Real issuing
// data replaces it WITHOUT rebuilding the Home interaction.
//
// PIN GATE (§6): once the pull commits, sensitive card content stays hidden
// behind a secure verification step — "Set your card PIN" when none exists,
// "Enter your card PIN" when one does. The card PIN is a SEPARATE credential
// from the AZM account PIN. No plaintext storage, no logging, no fake
// security state: the demo vault is clearly a demo vault.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';

// ── THE SEAM ──────────────────────────────────────────────────────────────

/// Everything issuer-shaped hides behind this seam. The Home UI NEVER talks
/// to a card network, store, or issuer directly.
abstract class AzmCardProgramme {
  /// Whether a card PIN has been established for this programme.
  bool get hasPin;

  /// Establish a first PIN. Returns success. The value is treated as an
  /// opaque credential: never logged, never stored in plaintext at rest
  /// (the demo implementation keeps it session-only in memory).
  Future<bool> setPin(String pin);

  /// Verify a PIN attempt. Constant result for equal comparisons; the
  /// attempt value is never logged.
  Future<bool> verifyPin(String pin);

  /// Masked card number for the sample surface.
  String get maskedNumber;

  /// Placeholder expiry — deliberately not a real date.
  String get expiryLabel;

  /// Cardholder display name.
  String get cardholderLabel;
}

/// The placeholder programme. PLACEHOLDER — REPLACE WITH THE REAL CARD
/// PROGRAMME INTEGRATION. It keeps the PIN in process memory for the
/// session only; it is not persisted, so it can never masquerade as a real
/// issued credential. Demo PINs must be 4-6 digits.
class DemoCardProgramme implements AzmCardProgramme {
  /// True so tests/hosts can assert they are on the demo path.
  static const bool isDemo = true;

  String? _sessionPin;

  @override
  bool get hasPin => _sessionPin != null;

  @override
  Future<bool> setPin(String pin) async {
    if (!_valid(pin)) return false;
    // Session-only. No storage, no logging — plaintext never persists.
    _sessionPin = pin;
    return true;
  }

  @override
  Future<bool> verifyPin(String pin) async {
    final stored = _sessionPin;
    if (stored == null || !_valid(pin)) return false;
    // Avoid early-exit comparison timing differences (defence in depth; the
    // demo has nothing at stake, production code keeps the same habit).
    var ok = stored.length == pin.length;
    for (var i = 0; i < stored.length; i++) {
      if (stored.codeUnitAt(i) != pin.codeUnitAt(i)) ok = false;
    }
    return ok;
  }

  @override
  String get maskedNumber => '4\u2022\u2022\u2022 \u2022\u2022\u2022\u2022 \u2022\u2022\u2022\u2022 \u202224';

  @override
  String get expiryLabel => 'MM/YY';

  @override
  String get cardholderLabel => 'CARDHOLDER';

  static bool _valid(String pin) =>
      pin.length >= 4 && pin.length <= 6 && RegExp(r'^\d+$').hasMatch(pin);
}

/// Riverpod seam so the UI has one injectable source and tests can swap it.
final azmCardProgrammeProvider = Provider<AzmCardProgramme>(
  (ref) => DemoCardProgramme(),
);

// ── THE SAMPLE CARD ──────────────────────────────────────────────────────

/// The sample Visa-concept card. Sensitive detail content (the expanded
/// details surface) is a SEPARATE widget ([AzmCardDetailsPanel]) that the
/// host may only mount AFTER the PIN gate passes — the card itself never
/// carries it.
class AzmVisaCard extends ConsumerWidget {
  const AzmVisaCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final user = ref.watch(authProvider).user;
    final name = (user?.username ?? '').toUpperCase();

    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.accent, colors.accentSecondary],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'AZM',
                      style: AzText.titleL.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    // SAMPLE network mark — Visa-concept visual only. The
                    // production network claim lives with the real card
                    // programme, not this placeholder surface.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'VISA',
                        style: AzText.title.copyWith(
                          color: const Color(0xFF1A1F71),
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          fontSize: 14,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  ref.watch(azmCardProgrammeProvider).maskedNumber,
                  style: AzText.titleXl.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.5,
                  ),
                ),
                const SizedBox(height: AzSpace.md),
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VALID THRU',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          ref.watch(azmCardProgrammeProvider).expiryLabel,
                          style: AzText.bodyL.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: AzSpace.xl),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ref.watch(azmCardProgrammeProvider).cardholderLabel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          name,
                          style: AzText.bodyL.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Unmistakably-safe demo tag: this card has NOT been issued.
          Positioned(
            top: AzSpace.md,
            right: AzSpace.md,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'SAMPLE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          // "powered by Flutterwave" mark for the sample surface.
          Positioned(
            bottom: AzSpace.md,
            right: AzSpace.md,
            child: Text(
              'powered by Flutterwave',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The sensitive detail surface. The host mounts this ONLY after the PIN gate
/// passes (§6). Keeping it a separate widget is what makes "sensitive card
/// data is not exposed before successful gate" testable: it is absent from
/// the tree, not merely hidden.
class AzmCardDetailsPanel extends ConsumerWidget {
  const AzmCardDetailsPanel({super.key, required this.programme});

  final AzmCardProgramme programme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Card details',
          style: AzText.titleL.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AzSpace.sm),
        Text(
          'Number  ${programme.maskedNumber}',
          style: AzText.bodyL.copyWith(color: colors.textSecondary),
        ),
        Text(
          'Expiry  ${programme.expiryLabel}',
          style: AzText.bodyL.copyWith(color: colors.textSecondary),
        ),
        Text(
          'Demo card — not issued. Production card data arrives with the '
          'real card programme.',
          style: AzText.bodyS.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

// ── THE PIN GATE ──────────────────────────────────────────────────────────

/// Secure verification step shown after the pull commits. Owns nothing
/// security-shaped itself — everything flows through the [AzmCardProgramme]
/// seam, and the PIN value is never logged or persisted by this widget.
class CardPinGateSheet extends ConsumerStatefulWidget {
  const CardPinGateSheet({super.key, required this.onVerified});

  /// Called exactly once, after successful verification.
  final VoidCallback onVerified;

  @override
  ConsumerState<CardPinGateSheet> createState() => _CardPinGateSheetState();
}

class _CardPinGateSheetState extends ConsumerState<CardPinGateSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final programme = ref.read(azmCardProgrammeProvider);
    final pin = _controller.text;
    if (pin.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = programme.hasPin
        ? await programme.verifyPin(pin)
        : await programme.setPin(pin);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      AzamanHaptics.success();
      widget.onVerified();
    } else {
      AzamanHaptics.warn();
      _controller.clear();
      setState(() => _error = programme.hasPin
          ? 'That PIN does not match. Try again.'
          : 'Use 4-6 digits for your card PIN.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final programme = ref.watch(azmCardProgrammeProvider);
    final isNewPin = !programme.hasPin;

    return Padding(
      padding: EdgeInsets.only(
        left: AzSpace.lg,
        right: AzSpace.lg,
        top: AzSpace.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + AzSpace.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(HugeIconsSolid.lockKey, size: 20, color: colors.accent),
              const SizedBox(width: AzSpace.sm),
              Expanded(
                child: Text(
                  isNewPin ? 'Set your card PIN' : 'Enter your card PIN',
                  style: AzText.titleXl.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AzSpace.sm),
          Text(
            'The card PIN is separate from your AZM account PIN.',
            style: AzText.bodyS.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AzSpace.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            decoration: InputDecoration(
              hintText: isNewPin ? 'Choose 4-6 digits' : 'Card PIN',
              counterText: '',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AzSpace.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : () => _submit(),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isNewPin ? 'Set PIN' : 'Unlock card details'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the gate as a modal bottom sheet. Returns true when verification
/// passed, false when dismissed without a successful verification.
Future<bool> showCardPinGate(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    isScrollControlled: true,
    builder: (sheetContext) => CardPinGateSheet(
      onVerified: () => Navigator.of(sheetContext).pop(true),
    ),
  );
  return result ?? false;
}
