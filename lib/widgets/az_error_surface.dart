// lib/widgets/az_error_surface.dart
// =============================================================================
// AZ ERROR SURFACE  (TASK-023)
//
// The designed replacement for two things:
//   1. `main.dart`'s `ErrorWidget.builder` (a hardcoded #1A1A2E Material box).
//   2. Ad-hoc "something went wrong" bodies inside screens.
//
// Rules it enforces:
//   * A Level-2 surface (Plate/Raised), never a bare hardcoded colour.
//   * One human sentence + one action. No stack traces, no blame.
//   * A way FORWARD: retry, and (when the data is merely stale) continue offline.
//   * Never claims the retry worked. It calls the callback and gets out of the way.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/az_state_illustration.dart';

class AzErrorSurface extends StatelessWidget {
  /// One sentence, in the product's voice. Never a raw exception string.
  final String message;

  /// Optional second line: what the user can still do.
  final String? hint;

  final VoidCallback? onRetry;

  /// Shown only when cached data exists — otherwise "continue offline" is a lie.
  final VoidCallback? onContinueOffline;

  final AzStateScene scene;

  /// Set false when this is rendered inside a list cell rather than a page.
  final bool expand;

  const AzErrorSurface({
    super.key,
    required this.message,
    this.hint,
    this.onRetry,
    this.onContinueOffline,
    this.scene = AzStateScene.error,
    this.expand = true,
  });

  /// Used by `main.dart`'s framework error hook. Deliberately generic: a build
  /// error has no user-meaningful detail, and inventing one would be a lie.
  ///
  /// The 2026-09-30 review correction applies here: there is no safe way to
  /// "re-run the failed build" from inside ErrorWidget.builder, so the shell
  /// passes NO onRetry and this copy never promises one. The honest way out is
  /// the OS back gesture, and the hint says exactly that. onRetry remains a
  /// parameter so a genuinely safe rebuild mechanism can supply one later —
  /// but nothing here may ship a button that lies about what it does.
  factory AzErrorSurface.fromFramework({Key? key, VoidCallback? onRetry}) =>
      AzErrorSurface(
        key: key,
        message: 'This part of Azaman did not load.',
        hint: 'Your data is safe. Go back and continue where you were.',
        onRetry: onRetry,
        scene: AzStateScene.error,
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).brightness == Brightness.dark
        ? ThemeProvider.getColors(AzamanTheme.dark)
        : ThemeProvider.getColors(AzamanTheme.light);

    return Container(
      width: double.infinity,
      color: colors.background,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AzStateIllustration(scene: scene, colors: colors, size: 92),
              const SizedBox(height: 18),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 8),
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                _Action(
                  colors: colors,
                  label: 'Try again',
                  primary: true,
                  onTap: () {
                    AzamanHaptics.confirm();
                    onRetry!();
                  },
                ),
              ],
              if (onContinueOffline != null) ...[
                const SizedBox(height: 10),
                _Action(
                  colors: colors,
                  label: 'Continue offline',
                  primary: false,
                  onTap: () {
                    AzamanHaptics.navigation();
                    onContinueOffline!();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final AzamanColors colors;
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _Action({
    required this.colors,
    required this.label,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: MotionTokens.control,
        curve: MotionTokens.symmetric,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: primary ? colors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: primary ? colors.accent : colors.border,
            width: primary ? 0 : 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: primary ? (colors.isDark ? Colors.black : Colors.white) : colors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
