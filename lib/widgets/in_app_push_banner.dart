import 'dart:async';
import 'package:flutter/material.dart';
import 'package:azaman/theme/motion_tokens.dart';

/// Lightweight in-app notification banner for foreground FCM messages.
/// Slides down from the top, auto-dismisses after 4 seconds.
/// Tapping the banner fires onTap (typically navigates to the deep-link).
class InAppPushBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  const InAppPushBanner({
    super.key,
    required this.title,
    required this.body,
    this.onTap,
    required this.onDismiss,
  });

  /// Shows a transient banner overlay at the top of the screen.
  static void show(
    BuildContext context, {
    required String title,
    required String body,
    VoidCallback? onTap,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => InAppPushBanner(
        title: title,
        body: body,
        onTap: onTap,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  @override
  State<InAppPushBanner> createState() => _InAppPushBannerState();
}

class _InAppPushBannerState extends State<InAppPushBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: MotionTokens.standard,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: MotionTokens.enter));

    _ctrl.forward();

    _autoDismiss = Timer(const Duration(seconds: 4), () => _dismiss());
  }

  void _dismiss() {
    _autoDismiss?.cancel();
    _ctrl.reverse().then((_) => widget.onDismiss());
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topPad = MediaQuery.of(context).padding.top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () {
              _dismiss();
              widget.onTap?.call();
            },
            child: Container(
              margin: EdgeInsets.fromLTRB(12, topPad + 8, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.notifications_active_rounded,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: _dismiss,
                        child: Icon(Icons.close_rounded,
                            size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                      ),
                    ],
                  ),
                  if (widget.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
