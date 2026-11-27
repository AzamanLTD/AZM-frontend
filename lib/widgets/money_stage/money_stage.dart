// lib/widgets/money_stage/money_stage.dart
// =============================================================================
// THE MONEY STAGE — one grammar for every launcher action.
//
// Send, Receive, Add money, Withdraw, Convert, Request and Pay are different
// tasks with different features, but they share one stage so the app feels
// like one instrument:
//
//   [◯ close]        [ context pill ]        [◯ action]     ← chrome on the sky
//
//                     GH₵  250                              ← the amount, centred
//                  GH₵ 769.00 available
//
//                   1    2    3
//                   4    5    6                             ← keys ARE the type
//                   7    8    9
//                   .    0    ⌫
//
//   (            Review                 )                   ← one solid ink pill
//
// The sky ([AzAmbientBackdrop]) gives each action its identity; everything on
// it reads its colours from [AzStageSkin], so shared widgets (AmountKeypad,
// CurrencyWheelToggle, SlideToConfirm) restyle themselves on a stage and stay
// exactly as they were everywhere else.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/money_stage/az_ambient_backdrop.dart';

export 'package:azaman/widgets/money_stage/az_ambient_backdrop.dart'
    show AzMoneyMood, AzSkyPalette, AzAmbientBackdrop;

/// The colours of the stage a widget sits on. Absent off-stage.
class AzStageSkin extends InheritedWidget {
  const AzStageSkin({
    super.key,
    required this.mood,
    required this.palette,
    required this.brightness,
    required super.child,
  });

  final AzMoneyMood mood;
  final AzSkyPalette palette;
  final Brightness brightness;

  bool get isDark => brightness == Brightness.dark;

  Color get ink => palette.ink;
  Color get inkMuted => palette.inkMuted;
  Color get glass => palette.glass;

  /// A hairline that reads on the sky without drawing a box.
  Color get hairline => palette.ink.withValues(alpha: isDark ? 0.14 : 0.10);

  /// Surface for a card that must hold rows of facts (review, receipts).
  Color get card => isDark
      ? Colors.white.withValues(alpha: 0.07)
      : Colors.white.withValues(alpha: 0.52);

  /// The solid primary pill: ink on light skies, paper on night skies.
  Color get primaryFill => isDark ? const Color(0xFFF7F4FA) : const Color(0xFF15121A);
  Color get onPrimary => isDark ? const Color(0xFF15121A) : Colors.white;

  /// The app palette, re-tuned for a stage: cards become glass, text takes
  /// the sky's ink, the accent IS the ink (no off-brand blue on a lilac
  /// sky), dividers become hairlines. Screens whose sub-widgets take an
  /// [AzamanColors] restyle wholesale by passing this instead. Status
  /// colours (success, danger, warning) are kept: they carry meaning.
  static AzamanColors adapt(AzamanColors base, AzMoneyMood mood) {
    final p = AzSkyPalette.of(mood, base.isDark ? Brightness.dark : Brightness.light);
    final dark = base.isDark;
    final ink = p.ink;
    return base.copyWith(
      card: dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.52),
      softSurface: p.glass,
      divider: ink.withValues(alpha: dark ? 0.14 : 0.10),
      border: ink.withValues(alpha: dark ? 0.14 : 0.10),
      accent: ink,
      accentSecondary: ink,
      accentSurface: ink.withValues(alpha: dark ? 0.12 : 0.08),
      textPrimary: ink,
      textSecondary: p.inkMuted,
      textTertiary: ink.withValues(alpha: 0.48),
    );
  }

  static AzStageSkin? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AzStageSkin>();

  @override
  bool updateShouldNotify(AzStageSkin old) =>
      old.palette != palette || old.mood != mood || old.brightness != brightness;
}

/// Sky + skin. Wrap the stage's whole body in this; give the [Scaffold] a
/// transparent background.
class AzMoneyStage extends StatelessWidget {
  const AzMoneyStage({
    super.key,
    required this.mood,
    required this.child,
    this.brightness,
    this.skyPhase = 0,
  });

  final AzMoneyMood mood;
  final Widget child;
  final Brightness? brightness;

  /// Pinned by captures; live stages start at 0 and drift.
  final double skyPhase;

  @override
  Widget build(BuildContext context) {
    final b = brightness ?? Theme.of(context).brightness;
    final palette = AzSkyPalette.of(mood, b);
    return AzStageSkin(
      mood: mood,
      palette: palette,
      brightness: b,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AzAmbientBackdrop(mood: mood, brightness: b, phase: skyPhase),
          DefaultTextStyle.merge(
            style: TextStyle(color: palette.ink),
            child: IconTheme.merge(
              data: IconThemeData(color: palette.ink),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// A 44dp glass circle for stage chrome (close, back, scan, swap).
class AzStageRoundButton extends StatelessWidget {
  const AzStageRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticsLabel,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String semanticsLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final skin = AzStageSkin.maybeOf(context);
    final ink = skin?.ink ?? Theme.of(context).colorScheme.onSurface;
    return Semantics(
      container: true,
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: skin?.glass ?? Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
            border: Border.all(color: skin?.hairline ?? Colors.transparent, width: 0.6),
          ),
          child: Icon(icon, size: size * 0.45, color: ink),
        ),
      ),
    );
  }
}

/// The glass pill at the top centre of a stage: who or where this money is
/// going. Two lines: a small spaced caption and the subject.
class AzStagePill extends StatelessWidget {
  const AzStagePill({
    super.key,
    this.leading,
    this.caption,
    this.captionTrailing,
    this.captionUppercase = true,
    required this.title,
    this.trailing,
  });

  /// Identity captions ("@ama", "AZM-123456789") keep their case: they are
  /// data, not labels.
  final bool captionUppercase;

  final Widget? leading;
  final String? caption;

  /// Rides on the caption line after [caption] (a status like "FRIEND").
  final Widget? captionTrailing;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final skin = AzStageSkin.maybeOf(context);
    final ink = skin?.ink ?? Theme.of(context).colorScheme.onSurface;
    final muted = skin?.inkMuted ?? ink.withValues(alpha: 0.6);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: EdgeInsets.fromLTRB(leading == null ? 16 : 6, 6, trailing == null ? 16 : 8, 6),
      decoration: BoxDecoration(
        color: skin?.glass ?? Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: skin?.hairline ?? Colors.transparent, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (caption != null)
                  DefaultTextStyle.merge(
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          flex: 3,
                          child: Text(
                            captionUppercase ? caption!.toUpperCase() : caption!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: captionUppercase
                                ? AzStageType.caption(muted)
                                : AzStageType.line(muted).copyWith(fontSize: 11.5, height: 1.25),
                          ),
                        ),
                        if (captionTrailing != null) ...[
                          Text('  ·  ', style: AzStageType.caption(muted)),
                          Flexible(flex: 2, child: captionTrailing!),
                        ],
                      ],
                    ),
                  ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AzStageType.pillTitle(ink),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// The one primary action on a stage: a solid ink pill. Disabled reads as
/// glass, never as a grey slab.
class AzStagePrimaryButton extends StatelessWidget {
  const AzStagePrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.semanticsLabel,
    this.height = 58,
  });

  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final String? semanticsLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final skin = AzStageSkin.maybeOf(context);
    final scheme = Theme.of(context).colorScheme;
    final fill = enabled ? (skin?.primaryFill ?? scheme.primary) : (skin?.glass ?? scheme.surfaceContainerHighest);
    final text = enabled ? (skin?.onPrimary ?? scheme.onPrimary) : (skin?.inkMuted ?? scheme.onSurfaceVariant);
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(999),
            border: enabled ? null : Border.all(color: skin?.hairline ?? Colors.transparent, width: 0.6),
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            style: AzStageType.button(text),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

/// Stage typography. Numbers are Inter with tabular figures (no jitter while
/// typing); words follow the app's UI family.
abstract final class AzStageType {
  static TextStyle amount(Color c, {double size = 64}) => AzText.money(
        c,
        size: size,
        weight: FontWeight.w600,
        tracking: -size * 0.035,
      );

  static TextStyle unit(Color c, {double size = 28}) => TextStyle(
        fontFamily: AzText.numericFamily,
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        height: 1.0,
        color: c,
      );

  /// Spaced, small, uppercase: "SENDING TO", "KOFI'S SHOP IS NEARBY".
  static TextStyle caption(Color c) => TextStyle(
        fontFamily: AzText.numericFamily,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
        height: 1.25,
        color: c,
      );

  /// The action's name above the amount ("Send", "Add money"): quiet, but
  /// it anchors which stage the user is on, since every stage shares a
  /// layout.
  static TextStyle stageTitle(Color c) => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        height: 1.2,
        color: c,
      );

  static TextStyle pillTitle(Color c) => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: c,
      );

  static TextStyle line(Color c) => TextStyle(
        fontFamily: AzText.numericFamily,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.3,
        fontFeatures: AzText.tabular,
        color: c,
      );

  static TextStyle key(Color c) => TextStyle(
        fontFamily: AzText.numericFamily,
        fontSize: 30,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.5,
        height: 1.0,
        color: c,
      );

  static TextStyle button(Color c) => TextStyle(
        fontFamily: AzText.numericFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: c,
      );
}
