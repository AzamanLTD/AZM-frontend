// =============================================================================
// Storefront Visibility Detector
//
// Wraps a child widget and triggers a 'widget_view' tracking event when the
// widget enters the screen's viewport. Uses ancestor Scrollable context to
// listen for scroll events.
// =============================================================================

import 'package:flutter/material.dart';
import '../services/storefront_tracking_service.dart';

class StorefrontVisibilityDetector extends StatefulWidget {
  final Widget child;
  final String businessProfileId;
  final String widgetType;
  final int widgetIndex;

  const StorefrontVisibilityDetector({
    super.key,
    required this.child,
    required this.businessProfileId,
    required this.widgetType,
    required this.widgetIndex,
  });

  @override
  State<StorefrontVisibilityDetector> createState() => _StorefrontVisibilityDetectorState();
}

class _StorefrontVisibilityDetectorState extends State<StorefrontVisibilityDetector> {
  bool _isVisible = false;
  ScrollableState? _scrollable;

  @override
  void initState() {
    super.initState();
    // Schedule initial visibility check after the first frame layout is completed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVisibility();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Dynamically look up the nearest ancestor Scrollable context.
    // If the scrollable changes or mounts/unmounts, we update our listener.
    final newScrollable = Scrollable.maybeOf(context);
    if (newScrollable != _scrollable) {
      _scrollable?.position.removeListener(_checkVisibility);
      _scrollable = newScrollable;
      _scrollable?.position.addListener(_checkVisibility);
    }
  }

  @override
  void didUpdateWidget(covariant StorefrontVisibilityDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-check visibility if widget key or bounds change
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVisibility();
    });
  }

  @override
  void dispose() {
    _scrollable?.position.removeListener(_checkVisibility);
    super.dispose();
  }

  /// Calculates whether the widget intersects with the visible screen area.
  void _checkVisibility() {
    if (!mounted) return;

    try {
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) return;

      // Find the widget's global position and size
      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;

      final screenHeight = MediaQuery.of(context).size.height;
      final screenWidth = MediaQuery.of(context).size.width;

      // Verify intersection with the viewport bounds
      final isVerticallyVisible = position.dy + size.height > 0 && position.dy < screenHeight;
      final isHorizontallyVisible = position.dx + size.width > 0 && position.dx < screenWidth;

      final currentlyVisible = isVerticallyVisible && isHorizontallyVisible;

      if (currentlyVisible && !_isVisible) {
        _isVisible = true;
        _fireViewEvent();
      } else if (!currentlyVisible && _isVisible) {
        _isVisible = false;
      }
    } catch (e) {
      // Gracefully capture layout/geometry exceptions during layout passes
    }
  }

  /// Sends the tracking event for this specific widget view
  void _fireViewEvent() {
    StorefrontTrackingService.instance.trackEvent(
      widget.businessProfileId,
      'widget_view',
      {
        'widgetType': widget.widgetType,
        'widgetIndex': widget.widgetIndex,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
