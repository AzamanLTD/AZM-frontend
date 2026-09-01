import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

import 'package:azaman/widgets/book/book.dart';

void main() {
  test('generic books keep corner interaction by default', () {
    final controller = FlipBookController();
    controller.updateMetrics(
      pageCount: 3,
      size: const Size(320, 480),
    );

    expect(
      controller.beginDrag(const Offset(300, 40), forward: true),
      isTrue,
    );
    expect(controller.anchor, isNot(FlipAnchor.middleOuter));
    controller.cancelDrag();
  });

  test('edge-anchored turns reject center grabs and fix the turn axis', () {
    final controller = FlipBookController(edgeAnchored: true);
    controller.updateMetrics(
      pageCount: 4,
      size: const Size(320, 480),
    );

    expect(
      controller.beginDrag(const Offset(300, 40), forward: true),
      isTrue,
    );
    expect(controller.anchor, FlipAnchor.middleOuter);
    expect(controller.anchorCorner, const Offset(320, 240));
    expect(controller.touch.dy, 240);
    controller.cancelDrag();

    expect(
      controller.beginDrag(const Offset(160, 240), forward: true),
      isFalse,
    );
    expect(controller.state, FlipState.idle);
  });

  test('backward edge turns start from the left side', () {
    final controller = FlipBookController(
      initialPage: 1,
      edgeAnchored: true,
    );
    controller.updateMetrics(
      pageCount: 4,
      size: const Size(320, 480),
    );

    expect(
      controller.beginDrag(const Offset(16, 430), forward: false),
      isTrue,
    );
    expect(controller.anchor, FlipAnchor.middleOuter);
    expect(controller.anchorCorner, const Offset(320, 240));
    expect(controller.touch.dy, 240);
    controller.cancelDrag();
  });
}
