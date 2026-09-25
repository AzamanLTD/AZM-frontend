import 'dart:async';
import 'package:flutter/material.dart';
import 'package:azaman/theme/motion_tokens.dart';

/// Lightweight in-app notification banner for foreground FCM messages.
///
/// The banner is intentionally actionable rather than merely decorative:
/// when an onTap callback is supplied, the user gets an explicit action cue.
/// Motion is removed when the platform requests reduced animation, while the
/// semantic live-region announcement remains available to assistive tech.
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

    _autoDismiss = Timer(const Duration(seconds: 4), _dismiss);
  }

  void _dismiss() {
    _autoDismiss?.cancel();
    if (!mounted) return;
    if (MediaQuery.of(context).disableAnimations) {
      widget.onDismiss();
      return;
    }
    _ctrl.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  void _activate() {
    _autoDismiss?.cancel();
    widget.onTap?.call();
    if (mounted) {
      if (MediaQuery.of(context).disableAnimations) {
        widget.onDismiss();
      } else {
        _ctrl.reverse().then((_) {
          if (mounted) widget.onDismiss();
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: MotionTokens.enter));
    if (disableAnimations) {
      _ctrl.value = 1;
    } else if (!_ctrl.isAnimating && _ctrl.value == 0) {
      _ctrl.forward();
    }
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
    final media = MediaQuery.of(context);
    final topPad = media.padding.top;
    final reducedMotion = media.disableAnimations;
    final hasAction = widget.onTap != null;

    final banner = Material(
      color: Colors.transparent,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: '${widget.title}. ${widget.body}',
        hint: hasAction ? 'Double tap to open. Dismiss is also available.' : 'Dismiss is available.',
        button: hasAction,
        child: InkWell(
          onTap: hasAction ? _activate : null,
          borderRadius: BorderRadius.circular(14),
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notifications_active_rounded,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                      if (hasAction) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'View',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(Icons.arrow_forward_rounded,
                                size: 14, color: theme.colorScheme.primary),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: 'Dismiss notification',
                  child: IconButton(
                    onPressed: _dismiss,
                    tooltip: 'Dismiss notification',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: reducedMotion ? banner : SlideTransition(position: _slide, child: banner),
    );
  }
}
