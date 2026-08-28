// =============================================================================
// Storefront Visibility Detector
//
// Wraps a child widget and triggers a 'widget_view' tracking event when the
// widget enters the screen's viewport. Uses ancestor Scrollable context to
// listen for scroll events.
//
// The tile id is used as the analytics identity instead of the visual index.
// This keeps analytics stable when a business reorders its storefront.
// =============================================================================

import 'package:flutter/material.dart';
import '../services/storefront_tracking_service.dart';

class StorefrontVisibilityDetector extends StatefulWidget {
  final Widget child;
  final String businessProfileId;
  final String tileId;
  final String widgetType;
  final int widgetIndex;

  const StorefrontVisibilityDetector({
    super.key,
    required this.child,
    required this.businessProfileId,
    required this.tileId,
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVisibility();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVisibility();
    });
  }

  @override
  void dispose() {
    _scrollable?.position.removeListener(_checkVisibility);
    super.dispose();
  }

  void _checkVisibility() {
    if (!mounted) return;

    try {
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) return;

      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      final mediaSize = MediaQuery.sizeOf(context);

      final isVerticallyVisible = position.dy + size.height > 0 && position.dy < mediaSize.height;
      final isHorizontallyVisible = position.dx + size.width > 0 && position.dx < mediaSize.width;
      final currentlyVisible = isVerticallyVisible && isHorizontallyVisible;

      if (currentlyVisible && !_isVisible) {
        _isVisible = true;
        _fireViewEvent();
      } else if (!currentlyVisible && _isVisible) {
        _isVisible = false;
      }
    } catch (_) {
      // Geometry can be unavailable during transient layout changes.
    }
  }

  void _fireViewEvent() {
    StorefrontTrackingService.instance.trackEvent(
      widget.businessProfileId,
      'widget_view',
      {
        'tileId': widget.tileId,
        'widgetType': widget.widgetType,
        'widgetIndex': widget.widgetIndex,
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
