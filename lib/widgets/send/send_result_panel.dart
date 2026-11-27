// =============================================================================
// AZAMAN — SEND RESULT PANEL (unified Send, 2026-10-20)
//
// Rendered ONLY after the canonical service confirmed the transfer with a
// 2xx. An ambiguous outcome never reaches this panel — it stays on the
// review stage with the honest unknown-state banner instead. No failure
// state is ever painted as a success.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/at_handle.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/scale_tap.dart';

class SendResultPanel extends StatelessWidget {
  const SendResultPanel({
    super.key,
    required this.colors,
    required this.amountText,
    required this.recipientName,
    required this.recipientUsername,
    required this.onDone,
    this.secondaryAmountText,
    this.secondaryAmountLabel = 'Transferred as',
  });

  final AzamanColors colors;

  /// The PRIMARY amount in the denomination the user entered — GHS-first
  /// when the composition was in cedis (the Ghana-first default).
  final String amountText;

  /// The USDC actually transferred on the wire, when the entry unit was
  /// GHS — rendered SECOND and explicitly labelled, never presented as
  /// proof of GHS settlement (a USDC rail moved USDC).
  final String? secondaryAmountText;
  final String secondaryAmountLabel;

  final String recipientName;

  /// RAW canonical username (unprefixed) — the panel formats the glyph
  /// itself via [AtHandle] so it can never double it.
  final String recipientUsername;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    // One formatter, at most one '@': '@@ama' can never render again.
    final handle = AtHandle.format(recipientUsername);
    final travel = AzMotion.of(context).travel;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    // Rise: the amount lifts 18px into place and fades in a beat after the
    // check lands. Still under reduced motion.
    Widget rise(Widget child, {int delayMs = 0}) {
      if (!travel) return child;
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 520 + delayMs),
        curve: Interval(delayMs / (520 + delayMs), 1, curve: Curves.easeOutCubic),
        builder: (context, t, c) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: c),
        ),
        child: child,
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 12 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // The check: an ink badge that springs in.
                    TweenAnimationBuilder<double>(
                      key: const ValueKey('send-success-icon'),
                      tween: Tween(begin: travel ? 0.0 : 1.0, end: 1.0),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.elasticOut,
                      builder: (context, value, child) =>
                          Transform.scale(scale: value, child: child),
                      child: Container(
                        width: 64,
                        height: 64,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.accent,
                        ),
                        child: Icon(Icons.check_rounded, size: 34, color: colors.onAccent),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Sent',
                      key: const ValueKey('send-success-title'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // The money leads: the amount, large and centred.
                    rise(
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          amountText,
                          key: const ValueKey('send-success-amount'),
                          style: AzText.money(colors.textPrimary, size: 52, weight: FontWeight.w600, tracking: -1.6),
                        ),
                      ),
                      delayMs: 140,
                    ),
                    const SizedBox(height: 10),
                    rise(
                      Text(
                        handle.isEmpty
                            ? 'to $recipientName'
                            : 'to $recipientName ($handle)',
                        key: const ValueKey('send-success-detail'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      delayMs: 220,
                    ),
                    if (secondaryAmountText != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '$secondaryAmountLabel $secondaryAmountText',
                        key: const ValueKey('send-success-wire-amount'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'The transfer appears in your conversation with '
                      '${handle.isEmpty ? recipientName : handle}.',
                      key: const ValueKey('send-success-chat-note'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.textTertiary, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ScaleTap(
            onTap: () {
              AzamanHaptics.nav();
              onDone();
            },
            child: Container(
              key: const ValueKey('send-success-done'),
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Done',
                style: TextStyle(
                  color: colors.onAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
