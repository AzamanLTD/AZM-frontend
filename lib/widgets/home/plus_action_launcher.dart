// =============================================================================
// AZAMAN — FLOATING PLUS ACTION LAUNCHER  (NEW-HOME §8)
//
// A visually stronger, more vibrant + button beside the bottom nav. When
// tapped the Home content de-emphasizes (dims + blurs out of focus) and the
// action choices appear DIRECTLY on the screen — not inside a large
// rectangular modal/card. The composition reads as the interface opening
// around the +; the + itself becomes the close affordance while open.
//
// Semantic distinction (brief §8): the + launcher means THINGS I CAN DO;
// Recent Activity means THINGS THAT HAPPENED. Keep that clean.
//
// Reusable component: the launcher owns no Home-specific logic. Hosts pass
// [PlusLauncherAction]s; motion/haptics come from the existing system and
// reduced motion is honoured (actions appear immediately, no springs).
// =============================================================================

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class PlusLauncherAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const PlusLauncherAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// The launcher layer. Render it as the topmost Stack child of a host that
/// owns the full screen (the shell does — body extends behind the nav).
///
/// Closed: only the vibrant + trigger is visible, positioned to sit beside
/// the bottom nav pill. Open: the trigger stays put (rotating into its
/// close role) while the actions appear directly over the de-emphasized
/// content.
class PlusActionLauncher extends ConsumerStatefulWidget {
  const PlusActionLauncher({super.key, required this.actions});

  final List<PlusLauncherAction> actions;

  @override
  ConsumerState<PlusActionLauncher> createState() =>
      _PlusActionLauncherState();
}

class _PlusActionLauncherState extends ConsumerState<PlusActionLauncher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: MotionTokens.standard,
    reverseDuration: MotionTokens.control,
    value: 0,
  );
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    // When a closing animation reaches dismissed, the open stack must be
    // UNMOUNTED (not merely faded to opacity 0) — build's closed-at-rest
    // branch only re-evaluates on a state change, so the controller has to
    // hand one over at completion.
    _open.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() {});
    }
  }

  bool get _reduceMotion => !AzMotion.of(context).travel;

  void _setOpen(bool open) {
    setState(() => _isOpen = open);
    if (_reduceMotion) {
      // Reduced motion: direct state transition — the actions are simply
      // there, no traversal.
      _open.value = open ? 1.0 : 0.0;
    } else {
      open ? _open.forward() : _open.reverse();
    }
  }

  void _toggle() {
    if (_isOpen) {
      // Dismissal is silent (the liquid-launcher haptic convention).
      _setOpen(false);
    } else {
      AzamanHaptics.nav();
      _setOpen(true);
    }
  }

  void _pick(PlusLauncherAction action) {
    // EXACTLY one confirm per pick — the double-haptic class this codebase
    // already removed elsewhere.
    AzamanHaptics.confirm();
    _setOpen(false);
    action.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final bottom = MediaQuery.of(context).padding.bottom;
    // The trigger floats beside/above the nav pill: far enough up to clear
    // the 62px pill + gutter, matching AzSpace.navClearance's intent.
    final triggerBottom = bottom + 84.0;

    final trigger = Positioned(
      right: AzSpace.lg,
      bottom: triggerBottom,
      child: _TriggerButton(
        open: _open,
        isOpen: _isOpen,
        reduceMotion: _reduceMotion,
        onTap: _toggle,
      ),
    );

    if (!_isOpen && _open.isDismissed) {
      // Closed at rest: only the trigger is alive.
      return Stack(children: [trigger]);
    }

    return AnimatedBuilder(
      animation: _open,
      builder: (context, _) {
        final t = _open.value;
        return Stack(children: [
          // De-emphasis: dim + blur the content behind the launcher. The
          // scrim fades in with the launcher, so the background reads as
          // going out of focus, not as a modal box.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _isOpen ? _toggle : null,
              child: FadeTransition(
                opacity: Tween(begin: 0.0, end: 1.0).animate(
                  CurvedAnimation(parent: _open, curve: MotionTokens.enter),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8 * t, sigmaY: 8 * t),
                  child: Container(
                    color: colors.background.withValues(alpha: 0.55 * t),
                  ),
                ),
              ),
            ),
          ),
          // The actions: appear directly on the screen as a generous
          // vertical column rising toward the trigger — no boxed modal,
          // staggered with MotionTokens.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: t < 0.5,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AzSpace.huge),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    for (var i = 0; i < widget.actions.length; i++)
                      _LauncherRow(
                        action: widget.actions[i],
                        index: i,
                        progress: _open,
                        reduceMotion: _reduceMotion,
                        onPick: _pick,
                      ),
                    SizedBox(height: triggerBottom + 56),
                  ],
                ),
              ),
            ),
          ),
          trigger,
        ]);
      },
    );
  }
}

class _TriggerButton extends StatelessWidget {
  final Animation<double> open;
  final bool isOpen;
  final bool reduceMotion;
  final VoidCallback onTap;

  const _TriggerButton({
    required this.open,
    required this.isOpen,
    required this.reduceMotion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // The + rotates 45° into its close (×) role while open.
    final turns =
        reduceMotion ? (isOpen ? 0.125 : 0.0) : open.value * 0.125;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7C5CFF), Color(0xFF3AD1B0)],
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x667C5CFF),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Transform.rotate(
          angle: turns * 2 * 3.141592653589793,
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class _LauncherRow extends ConsumerWidget {
  final PlusLauncherAction action;
  final int index;
  final Animation<double> progress;
  final bool reduceMotion;
  final ValueChanged<PlusLauncherAction> onPick;

  const _LauncherRow({
    required this.action,
    required this.index,
    required this.progress,
    required this.reduceMotion,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final t = progress.value;
    final delayMs = MotionTokens.staggerDelay(index + 2).inMilliseconds;
    final spanMs = MotionTokens.spatial.inMilliseconds;
    final appear = reduceMotion
        ? 1.0
        : Interval((delayMs / spanMs).clamp(0.0, 0.8), 1.0,
                curve: MotionTokens.enter)
            .transform(t);

    return Opacity(
      opacity: appear,
      child: Transform.translate(
        offset: Offset(0, (1 - appear) * 18),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onPick(action),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AzSpace.sm),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.accent.withValues(alpha: 0.16),
                    border:
                        Border.all(color: colors.accent.withValues(alpha: 0.45)),
                  ),
                  child: Icon(action.icon, size: 20, color: colors.accent),
                ),
                const SizedBox(width: AzSpace.md),
                Text(
                  action.label,
                  style: AzText.titleXl.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
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

// ── RECEIVE (things I can DO) ─────────────────────────────────────────────

/// The Receive action's target: shows the user's public AZM ID + a QR so
/// anyone can pay them. No invented amounts, no fake activity — the only
/// data is the user's real public ID.
Future<void> showReceiveSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _ReceiveSheet(),
  );
}

class _ReceiveSheet extends ConsumerWidget {
  const _ReceiveSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final user = ref.watch(authProvider).user;
    final azmId = user?.azamanId ?? user?.username ?? '';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AzSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Receive money',
              style: AzText.titleXl.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AzSpace.md),
            Text(
              'Share your AZM ID — anyone can send to it.',
              style: AzText.bodyL.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AzSpace.lg),
            Container(
              padding: const EdgeInsets.all(AzSpace.md),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: azmId,
                version: QrVersions.auto,
                size: 180,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: colors.textPrimary,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: AzSpace.lg),
            SelectableText(
              azmId,
              style: AzText.title.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
