// =============================================================================
// AZAMAN — SHARED LAUNCHER EXIT PROMPT (original programme §C.1)
//
// ONE shared prompt for every launcher surface (Send, Withdraw, Add Cash,
// Convert). No surface implements its own close dialog: when a MEANINGFUL
// unsubmitted form is about to be closed (X, system back, pull-down), the
// user chooses exactly one of:
//
//   KEEP FOR 5 MINUTES — persist the editable inputs as a local, user-
//       scoped, expiring draft (see launcher_drafts.dart). Repeated Keeps
//       renew expiry; the draft resumes from its exact state.
//   DISCARD DRAFT — drop the stored draft (if any) AND close. Gone for
//       good; it cannot return on refresh.
//   STAY HERE — nothing happens. The form is untouched.
//
// A genuinely empty form NEVER shows this prompt — it just closes.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../services/launcher_drafts.dart';
import 'azaman_sheet.dart';

enum LauncherExitChoice { keep, discard, stay }

/// The shared three-choice prompt. Returns the user's explicit choice, or
/// null if the sheet was dismissed by a backdrop tap (treated by callers
/// as "stay" — a stray tap must never destroy state).
Future<LauncherExitChoice?> showLauncherExitPrompt(
  BuildContext context, {
  required String surfaceLabel,
  required AzamanColors c,
}) {
  return AzamanSheet.showWhisper<LauncherExitChoice>(
    context,
    // The three choice rows measure taller than the default whisper cap
    // on short viewports; the raised cap keeps every choice visible
    // without scrolling, still far below a panel.
    maxHeightFraction: 0.66,
    builder: (ctx) {
      Widget choice({
        required LauncherExitChoice value,
        required IconData icon,
        required String title,
        required String subtitle,
        required Color tint,
        bool emphasize = false,
      }) =>
          Semantics(
            button: true,
            label: '$title. $subtitle',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(ctx).pop(value),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: emphasize ? tint.withValues(alpha: 0.12) : c.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: emphasize
                          ? tint.withValues(alpha: 0.55)
                          : c.divider.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 22, color: tint),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 11.5,
                                height: 1.3,
                                decoration: TextDecoration.none,
                              ),
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

      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Keep this $surfaceLabel draft?',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "You're closing with unfinished details. Nothing was sent — "
              'this is just your input.',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 12.5,
                height: 1.4,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 10),
            choice(
              value: LauncherExitChoice.keep,
              icon: Icons.schedule_outlined,
              title: 'Keep for 5 minutes',
              subtitle:
                  'Resume exactly where you left off, from Notifications.',
              tint: c.accent,
              emphasize: true,
            ),
            const SizedBox(height: 8),
            choice(
              value: LauncherExitChoice.discard,
              icon: Icons.delete_outline,
              title: 'Discard draft',
              subtitle: 'Close and clear what you typed.',
              tint: c.danger,
            ),
            const SizedBox(height: 8),
            choice(
              value: LauncherExitChoice.stay,
              icon: Icons.close,
              title: 'Stay here',
              subtitle: 'Keep editing — nothing changes.',
              tint: c.textSecondary,
            ),
          ],
        ),
      );
    },
  );
}

/// The single close-guard every launcher surface funnels through.
///
/// Call from the surface's close handler (`_closeSurface`) — it owns the
/// entire decision:
///
///   • genuinely empty form → [doClose] immediately, and any previously
///     kept draft for this surface is discarded (the empty form supersedes
///     it; a stale card must not outlive the form it claims to hold).
///   • meaningful form → the shared prompt. Keep persists via
///     [launcherDraftsProvider] with the stable (user, surface) identity;
///     Discard drops the draft; Stay is a no-op.
///
/// [userId] scoping: the draft authority must know the authenticated user.
/// When null (unauthenticated), Keep degrades to a plain close — drafts
/// are user-scoped by contract and never persist anonymously.
Future<void> guardLauncherClose({
  required BuildContext context,
  required WidgetRef ref,
  required String? userId,
  required LauncherSurface surface,
  required bool hasMeaningfulInput,
  required Map<String, dynamic> Function() capture,
  required VoidCallback doClose,
}) async {
  final controller = ref.read(launcherDraftsProvider.notifier);
  final existingId =
      userId == null ? null : LauncherDraftsController.draftId(userId, surface);

  if (!hasMeaningfulInput) {
    // Empty form: no prompt ever. A stale kept draft for this surface is
    // superseded by the empty close — discard it so the notification
    // centre cannot offer a resume into a form the user just emptied.
    if (existingId != null) await controller.discardDraft(existingId);
    doClose();
    return;
  }

  final c = ref.read(themeProvider).colors;
  final choice = await showLauncherExitPrompt(
    context,
    surfaceLabel: surface.label.toLowerCase(),
    c: c,
  );
  switch (choice) {
    case LauncherExitChoice.keep:
      if (userId == null || !context.mounted) {
        doClose();
        return;
      }
      await controller.keepDraft(LauncherDraft(
        id: LauncherDraftsController.draftId(userId, surface),
        surface: surface,
        savedAtMs: DateTime.now().millisecondsSinceEpoch,
        payload: capture(),
      ));
      doClose();
    case LauncherExitChoice.discard:
      if (existingId != null) await controller.discardDraft(existingId);
      doClose();
    case LauncherExitChoice.stay:
    case null:
      break; // backdrop tap or Stay: the form is untouched
  }
}
