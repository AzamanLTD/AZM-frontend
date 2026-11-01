// =============================================================================
// SHOW-LESS CONFIRMATION — the mandatory explicit confirmation for the
// joystick's left direction (Workstream A, 2026-10-26).
//
// "Show less like this" is a persistent, user-scoped recommendation
// change (AZM-backend PR #373). The joystick NEVER applies it on release:
// the release opens THIS dialog, and only an explicit confirm runs the
// real RecommendationFeedbackService — once.
//
// Honesty (the same contract the action panel already encodes):
//   * The current state is CHECKED first. While unknown (in flight), no
//     action is available or claimed — the confirm button is disabled.
//   * Not applied -> confirm applies once (alreadyApplied:true is SUCCESS).
//   * Already applied -> the dialog offers UNDO, and the undo is ALSO
//     confirmed — the user's stored preference is never silently
//     reversed just because the same direction was used again.
//   * A failed check shows an honest error and offers no pretend
//     action. A failed apply/undo shows the durable state never moved.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/recommendation_feedback_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';

/// Shows the confirmation dialog for "show less like this [business]".
/// No feedback request happens before an explicit confirm.
Future<void> showJoystickShowLessConfirm(
  BuildContext context,
  WidgetRef ref,
  BusinessProfile business,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false, // explicit confirm or cancel, nothing else
    builder: (_) => _ShowLessConfirmDialog(business: business),
  );
}

class _ShowLessConfirmDialog extends ConsumerStatefulWidget {
  const _ShowLessConfirmDialog({required this.business});

  final BusinessProfile business;

  @override
  ConsumerState<_ShowLessConfirmDialog> createState() =>
      _ShowLessConfirmDialogState();
}

class _ShowLessConfirmDialogState
    extends ConsumerState<_ShowLessConfirmDialog> {
  // null = unknown (check in flight); true = SHOW_LESS applied.
  bool? _applied;
  bool _checkFailed = false;
  bool _busy = false;

  /// Canonical BusinessProfile.id — the ONLY key the contract accepts.
  String get _canonicalId => widget.business.id;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _checkFailed = false;
      _busy = true;
    });
    try {
      final applied = await ref
          .read(recommendationFeedbackServiceProvider)
          .check(_canonicalId);
      if (!mounted) return;
      setState(() {
        _applied = applied;
        _busy = false;
      });
    } catch (_) {
      // Honest failure: unknown state — no pretend availability.
      if (!mounted) return;
      setState(() {
        _checkFailed = true;
        _busy = false;
      });
    }
  }

  Future<void> _apply() async {
    if (_busy) return;
    AzamanHaptics.confirm();
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(recommendationFeedbackServiceProvider)
          .apply(_canonicalId);
      if (!mounted) return;
      // alreadyApplied:true is SUCCESS — the durable state is SHOW_LESS
      // either way.
      if (result.showLess) {
        setState(() => _applied = true);
        Navigator.of(context).pop();
      } else {
        _rejected('Could not apply. Nothing changed.');
      }
    } catch (_) {
      _rejected('Could not apply. Nothing changed.');
    }
  }

  Future<void> _undo() async {
    if (_busy) return;
    AzamanHaptics.confirm();
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(recommendationFeedbackServiceProvider)
          .undo(_canonicalId);
      if (!mounted) return;
      // ANY 200 means NONE — removed:false is idempotent success.
      if (result.none) {
        setState(() => _applied = false);
        Navigator.of(context).pop();
      } else {
        _rejected('Could not undo. Still showing less.');
      }
    } catch (_) {
      _rejected('Could not undo. Still showing less.');
    }
  }

  void _rejected(String message) {
    if (!mounted) return;
    setState(() => _busy = false); // durable state unchanged
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final name = widget.business.businessName;
    final applied = _applied;
    return AlertDialog(
      key: const ValueKey('joystick-show-less-confirm'),
      icon: Icon(
        Icons.visibility_off_outlined,
        color: colors.textSecondary,
        size: 28,
      ),
      title: Text(
        applied == true
            ? 'Stop showing less like "$name"?'
            : 'Show less like "$name"?',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: colors.textPrimary,
        ),
      ),
      content: Text(
        _checkFailed
            ? 'Could not reach your preferences right now. Nothing has '
                  'changed — try again later.'
            : applied == true
            ? 'You already show fewer recommendations like this '
                  'business. Undoing restores it in your results.'
            : 'You\'ll see fewer recommendations like this business. '
                  'You can undo this anytime.',
        style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
      ),
      actions: [
        TextButton(
          key: const ValueKey('joystick-show-less-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_checkFailed)
          TextButton(
            key: const ValueKey('joystick-show-less-retry'),
            onPressed: _busy ? null : _check,
            child: const Text('Retry'),
          )
        else if (applied == null)
          // Unknown state: nothing to confirm yet — checking spinner.
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          FilledButton(
            key: ValueKey(
              applied
                  ? 'joystick-show-less-undo'
                  : 'joystick-show-less-confirm-apply',
            ),
            onPressed: _busy ? null : (applied ? _undo : _apply),
            child: Text(applied ? 'Undo' : 'Show less'),
          ),
      ],
    );
  }
}
