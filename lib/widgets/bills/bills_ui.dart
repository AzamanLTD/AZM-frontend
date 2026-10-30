// AZAMAN — BILLS UI PRIMITIVES
//
// Small, shared pieces of the Bills surface. They exist so the Hub and the
// three flows read as one facility: the same card, the same section rhythm, the
// same honest-empty-state grammar, the same "this is money" typography.
//
// Nothing here formats money on its own. Amounts arrive already formatted from
// the quote or receipt, because a fee or a total is the server's number.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_text.dart';

/// The palette for a Bills surface.
///
/// The app installs [AzamanColors] as a ThemeExtension, and these widgets are
/// also used by tests that mount a bare `MaterialApp`, so the palette is read
/// from the app's theme provider when the extension is absent rather than
/// crashing on a null.
AzamanColors billsColors(BuildContext context) {
  final extension = Theme.of(context).extension<AzamanColors>();
  if (extension != null) return extension;
  return ProviderScope.containerOf(
    context,
    listen: false,
  ).read(themeProvider).colors;
}

/// A section of the Hub: a label, an optional action, and its content.
class BillsSection extends StatelessWidget {
  const BillsSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = billsColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AzText.eyebrow.copyWith(
                      color: colors.textTertiary,
                      letterSpacing: 0.9,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: AzText.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 10),
        child,
        const SizedBox(height: 22),
      ],
    );
  }
}

/// The one bordered card the whole facility uses.
class BillsCard extends StatelessWidget {
  const BillsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = billsColors(context);
    final body = Padding(padding: padding, child: child);
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.divider),
          ),
          child: onTap == null
              ? Semantics(
                  container: semanticLabel != null,
                  label: semanticLabel,
                  child: body,
                )
              : Semantics(button: true, label: semanticLabel, child: body),
        ),
      ),
    );
  }
}

/// An empty state that says what is true and offers no dead end.
class BillsEmptyNote extends StatelessWidget {
  const BillsEmptyNote({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = billsColors(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: colors.textTertiary),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              text,
              style: AzText.bodyS.copyWith(
                color: colors.textTertiary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Says, on its face, that the numbers below come from the demo gateway.
class BillsDemoBanner extends StatelessWidget {
  const BillsDemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = billsColors(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colors.accentSurface,
        border: Border.all(color: colors.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.science_outlined, size: 15, color: colors.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Demo data — billers, meters and receipts below are samples, not '
              'real bills.',
              style: AzText.caption.copyWith(
                color: colors.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A saved bill account, the way the member named it.
class BillsAccountTile extends StatelessWidget {
  const BillsAccountTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.maskedIdentifier,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String maskedIdentifier;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = billsColors(context);
    return BillsCard(
      onTap: onTap,
      semanticLabel: '$title, $subtitle, account $maskedIdentifier',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AzText.body.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '$subtitle · $maskedIdentifier',
                  style: AzText.caption.copyWith(color: colors.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A label/value row used in the review and receipt screens. Money is rendered
/// exactly as the quote or receipt supplied it.
class BillsKeyValue extends StatelessWidget {
  const BillsKeyValue({
    super.key,
    required this.label,
    required this.value,
    this.emphasised = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasised;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = billsColors(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AzText.bodyS.copyWith(color: colors.textTertiary),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.right,
            style: emphasised
                ? AzText.money(colors.textPrimary, size: 18)
                : AzText.body.copyWith(
                    color: valueColor ?? colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
          ),
        ],
      ),
    );
  }
}

/// One primary action at the bottom of a flow.
class BillsPrimaryButton extends StatelessWidget {
  const BillsPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = billsColors(context);
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.textPrimary,
          disabledBackgroundColor: colors.divider,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.textSecondary,
                ),
              )
            : Text(
                label,
                style: AzText.button.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
