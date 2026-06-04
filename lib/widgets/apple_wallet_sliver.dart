import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class AppleWalletSliver extends SliverMultiBoxAdaptorWidget {
  final double collapsedHeight;
  final double expandedHeight;

  const AppleWalletSliver({
    super.key,
    required super.delegate,
    this.collapsedHeight = 64.0,
    this.expandedHeight = 184.0,
  });

  @override
  _RenderAppleWalletSliver createRenderObject(BuildContext context) {
    return _RenderAppleWalletSliver(
      childManager: context as RenderSliverBoxChildManager,
      collapsedHeight: collapsedHeight,
      expandedHeight: expandedHeight,
    );
  }

  @override
  _AppleWalletSliverElement createElement() => _AppleWalletSliverElement(this);
}

class _AppleWalletSliverElement extends SliverMultiBoxAdaptorElement {
  _AppleWalletSliverElement(super.widget);
}

class _RenderAppleWalletSliver extends RenderSliverMultiBoxAdaptor {
  double collapsedHeight;
  double expandedHeight;

  _RenderAppleWalletSliver({
    required super.childManager,
    required this.collapsedHeight,
    required this.expandedHeight,
  });

  double _compression(int index, double scrollOffset, double compressible) {
    final double threshold = index * compressible;
    if (scrollOffset <= threshold) return 0;
    if (scrollOffset >= threshold + compressible) return compressible;
    return scrollOffset - threshold;
  }

  @override
  void performLayout() {
    final int count = childCount;
    if (count == 0) {
      geometry = SliverGeometry.zero;
      return;
    }

    final double scrollOffset = constraints.scrollOffset;
    final double remainingPaintExtent = constraints.remainingPaintExtent;
    final double compressible = expandedHeight - collapsedHeight;
    final double totalScrollExtent = count * expandedHeight;

    childManager.didStartLayout();
    childManager.setDidUnderflow(false);

    RenderBox? child = firstChild;
    int index = 0;
    double lastBottom = 0;

    while (child != null) {
      final parentData =
          child.parentData as SliverMultiBoxAdaptorParentData;

      double totalCompressionBefore = 0;
      for (int j = 0; j < index; j++) {
        totalCompressionBefore += _compression(j, scrollOffset, compressible);
      }

      final double cardCompression =
          _compression(index, scrollOffset, compressible);
      final double cardHeight = expandedHeight - cardCompression;
      final double cardTop =
          index * expandedHeight - totalCompressionBefore;

      parentData.layoutOffset = cardTop;

      child.layout(
        BoxConstraints(
          maxWidth: constraints.crossAxisExtent,
          maxHeight: cardHeight,
        ),
        parentUsesSize: true,
      );

      lastBottom = cardTop + cardHeight;

      index++;
      child = childAfter(child);
    }

    childManager.didFinishLayout();

    final double paintExtent =
        (lastBottom - scrollOffset).clamp(0.0, remainingPaintExtent);
    final double maxPaintExtent =
        expandedHeight + (count - 1) * collapsedHeight;

    geometry = SliverGeometry(
      scrollExtent: totalScrollExtent,
      paintExtent: paintExtent,
      maxPaintExtent: maxPaintExtent,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    RenderBox? child = firstChild;
    while (child != null) {
      final parentData =
          child.parentData as SliverMultiBoxAdaptorParentData;
      final double top = parentData.layoutOffset ?? 0;
      final double h = child.size.height;

      if (top + h > 0 && top < constraints.remainingPaintExtent) {
        final RenderBox paintChild = child;
        context.pushClipRect(
          needsCompositing,
          offset + Offset(0, top),
          Rect.fromLTWH(0, 0, constraints.crossAxisExtent, h),
          (PaintingContext innerContext, Offset innerOffset) {
            innerContext.paintChild(paintChild, innerOffset);
          },
        );
      }

      child = childAfter(child);
    }
  }
}
