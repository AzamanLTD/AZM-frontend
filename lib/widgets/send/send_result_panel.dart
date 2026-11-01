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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TweenAnimationBuilder<double>(
              key: const ValueKey('send-success-icon'),
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 450),
              curve: Curves.elasticOut,
              builder: (context, value, child) =>
                  Transform.scale(scale: value, child: child),
              child: Container(
                width: 80,
                height: 80,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.success.withValues(alpha: 0.15),
                ),
                child: Icon(
                  Icons.check_circle_outline,
                  size: 40,
                  color: colors.success,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Sent',
              key: const ValueKey('send-success-title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              handle.isEmpty
                  ? '$amountText to $recipientName'
                  : '$amountText to $recipientName ($handle)',
              key: const ValueKey('send-success-detail'),
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
            if (secondaryAmountText != null) ...[
              const SizedBox(height: 6),
              Text(
                '$secondaryAmountLabel $secondaryAmountText',
                key: const ValueKey('send-success-wire-amount'),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textTertiary, fontSize: 12),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'The transfer appears in your conversation with '
              '${handle.isEmpty ? recipientName : handle}.',
              key: const ValueKey('send-success-chat-note'),
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 28),
            ScaleTap(
              onTap: () {
                AzamanHaptics.nav();
                onDone();
              },
              child: Container(
                key: const ValueKey('send-success-done'),
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Done',
                  style: TextStyle(
                    color: colors.onAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
