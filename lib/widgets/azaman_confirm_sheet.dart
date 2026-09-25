// =============================================================================
// AZAMAN — CONFIRM SHEET  (Phase H)
//
// Replaces the legacy `showDialog<bool>(... AlertDialog ...)` pattern with
// a bottom-sheet confirmation that feels native on both iOS and Android.
// Audit §11 explicitly called out "Bottom-sheet modal style for 'are you
// sure?' actions instead of AlertDialog" as a premium-feel must.
//
// Same return contract as `showDialog<bool>` — so callsites only have to
// swap one line:
//
//   final ok = await AzamanConfirmSheet.show(
//     context,
//     title: 'Sign Out',
//     message: 'Are you sure you want to sign out?',
//     confirmLabel: 'Sign Out',
//     destructive: true,
//   );
//   if (ok != true) return;
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class AzamanConfirmSheet {
  const AzamanConfirmSheet._();

  /// Returns `true` on confirm, `false` on cancel, `null` on dismiss
  /// (tapping the backdrop). Same shape as `showDialog<bool>`.
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
    IconData? icon,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ConfirmBody(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
        icon: icon,
      ),
    );
  }
}

class _ConfirmBody extends ConsumerWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final IconData? icon;

  const _ConfirmBody({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
    required this.icon,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final accent = destructive ? colors.danger : colors.accent;
    final onAccent = colors.isDark ? Colors.black : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (icon != null)
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: accent, size: 26),
                  ),
                ),
              if (icon != null) const SizedBox(height: 14),
              Center(
                child: Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // Primary action.
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    // Phase H review pass: use the named haptic vocabulary
                    // rather than HapticFeedback directly. `warn` for
                    // destructive flows (sign-out, delete), `commit` for
                    // safe-but-final commits (e.g. submit form).
                    if (destructive) {
                      AzamanHaptics.warn();
                    } else {
                      AzamanHaptics.commit();
                    }
                    Navigator.pop(context, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: onAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    confirmLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Cancel.
              SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: () {
                    AzamanHaptics.nav();
                    Navigator.pop(context, false);
                  },
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    cancelLabel,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
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
