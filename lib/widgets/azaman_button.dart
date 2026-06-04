// =============================================================================
// AZAMAN BUTTON  (Master Sprint v2, 2026-05-27)
//
// The canonical button widget for the platform. Replaces every bare
// ElevatedButton/OutlinedButton across the app so the visual identity is
// consistent, the white-theme contrast issue is fixed at the source, and
// every button has the same press feel.
//
// Variants
//   • AzamanButtonVariant.primary    — gradient fill, accent color, white/black text
//   • AzamanButtonVariant.secondary  — frosted card, accent text, accent ring
//   • AzamanButtonVariant.danger     — red gradient
//   • AzamanButtonVariant.ghost      — invisible bg, accent text + underline on press
//
// Sizes
//   • small (32h), medium (40h, default), large (48h)
//
// Behaviour
//   • Press: scale to 0.96, micro haptic
//   • flutter_animate shimmer chains on first paint of primary buttons
//   • Loading state with white/dark spinner that contrasts the gradient
//   • Disabled state desaturates the gradient
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';

enum AzamanButtonVariant { primary, secondary, danger, ghost }

enum AzamanButtonSize { small, medium, large }

class AzamanButton extends ConsumerStatefulWidget {
  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final VoidCallback? onPressed;
  final AzamanButtonVariant variant;
  final AzamanButtonSize size;
  final bool isLoading;
  final bool fullWidth;

  const AzamanButton({
    super.key,
    required this.label,
    this.icon,
    this.trailingIcon,
    required this.onPressed,
    this.variant = AzamanButtonVariant.primary,
    this.size = AzamanButtonSize.medium,
    this.isLoading = false,
    this.fullWidth = false,
  });

  @override
  ConsumerState<AzamanButton> createState() => _AzamanButtonState();
}

class _AzamanButtonState extends ConsumerState<AzamanButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  ({double height, double pad, double iconSize, double fontSize}) _sizeSpec() {
    switch (widget.size) {
      case AzamanButtonSize.small:
        return (height: 32, pad: 12, iconSize: 14, fontSize: 12);
      case AzamanButtonSize.medium:
        return (height: 44, pad: 18, iconSize: 16, fontSize: 13.5);
      case AzamanButtonSize.large:
        return (height: 52, pad: 22, iconSize: 18, fontSize: 15);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final spec = _sizeSpec();
    final disabled = widget.onPressed == null || widget.isLoading;

    final (bgGradient, fg, ringColor, shadowColor) = _resolveStyles(colors);

    final inner = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      height: spec.height,
      padding: EdgeInsets.symmetric(horizontal: spec.pad),
      decoration: BoxDecoration(
        gradient: disabled ? null : bgGradient,
        color: disabled ? _disabledFill(colors) : null,
        borderRadius: BorderRadius.circular(_radiusForSize()),
        border: ringColor != null
            ? Border.all(color: ringColor, width: widget.variant == AzamanButtonVariant.secondary ? 1.4 : 0.8)
            : null,
        boxShadow: shadowColor != null && !disabled
            ? [
                BoxShadow(
                  color: shadowColor.withOpacity(_pressed ? 0.25 : 0.40),
                  blurRadius: _pressed ? 6 : 14,
                  spreadRadius: -2,
                  offset: Offset(0, _pressed ? 2 : 6),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.isLoading)
            SizedBox(
              width: spec.iconSize,
              height: spec.iconSize,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: fg,
              ),
            )
          else if (widget.icon != null) ...[
            Icon(widget.icon, size: spec.iconSize, color: fg),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: spec.fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
          if (widget.trailingIcon != null && !widget.isLoading) ...[
            const SizedBox(width: 8),
            Icon(widget.trailingIcon, size: spec.iconSize, color: fg),
          ],
        ],
      ),
    );

    final scaled = AnimatedScale(
      scale: _pressed ? 0.96 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: inner,
    );

    Widget body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: disabled ? null : (_) => _setPressed(true),
      onTapUp: disabled ? null : (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: disabled
          ? null
          : () {
              HapticFeedback.lightImpact();
              widget.onPressed!();
            },
      child: scaled,
    );

    // Primary buttons get a one-shot shimmer on mount so the CTA reads
    // as alive without continuous animation hammering the GPU.
    if (widget.variant == AzamanButtonVariant.primary && !disabled) {
      body = body
          .animate()
          .shimmer(
            delay: 250.ms,
            duration: 1500.ms,
            color: Colors.white.withOpacity(0.30),
          );
    }

    return widget.fullWidth ? SizedBox(width: double.infinity, child: body) : body;
  }

  double _radiusForSize() => switch (widget.size) {
        AzamanButtonSize.small => 10,
        AzamanButtonSize.medium => 12,
        AzamanButtonSize.large => 14,
      };

  Color _disabledFill(AzamanColors colors) {
    switch (widget.variant) {
      case AzamanButtonVariant.primary:
        return colors.accent.withOpacity(0.30);
      case AzamanButtonVariant.danger:
        return colors.danger.withOpacity(0.30);
      case AzamanButtonVariant.secondary:
        return colors.card;
      case AzamanButtonVariant.ghost:
        return Colors.transparent;
    }
  }

  /// Resolve gradient + foreground + optional ring + optional shadow for
  /// the selected variant. Designed so each variant looks the same in
  /// every theme without manually overriding per-screen.
  (Gradient bgGradient, Color fg, Color? ringColor, Color? shadowColor)
      _resolveStyles(AzamanColors colors) {
    switch (widget.variant) {
      case AzamanButtonVariant.primary:
        // Gradient ensures even white themes get a proper coloured fill,
        // and the foreground is forced to high-contrast (black on light
        // gold, white on dark) so labels never disappear.
        final fg = colors.isDark ? Colors.black : Colors.white;
        return (
          LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.accent,
              Color.alphaBlend(
                colors.accentSecondary.withOpacity(0.7),
                colors.accent,
              ),
            ],
          ),
          fg,
          null,
          colors.accent,
        );
      case AzamanButtonVariant.danger:
        return (
          LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.danger,
              Color.alphaBlend(
                Colors.black.withOpacity(0.10),
                colors.danger,
              ),
            ],
          ),
          Colors.white,
          null,
          colors.danger,
        );
      case AzamanButtonVariant.secondary:
        return (
          LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.accent.withOpacity(0.10),
              colors.accent.withOpacity(0.04),
            ],
          ),
          colors.accent,
          colors.accent.withOpacity(0.30),
          null,
        );
      case AzamanButtonVariant.ghost:
        return (
          const LinearGradient(colors: [Colors.transparent, Colors.transparent]),
          colors.accent,
          null,
          null,
        );
    }
  }
}
