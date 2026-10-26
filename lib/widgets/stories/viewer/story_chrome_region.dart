// =============================================================================
// AZAMAN — STORY VIEWER: CHROME REGION MARKER
//
// WORKSTREAM F2. The gesture arbiter is a raw Listener with
// HitTestBehavior.opaque that sees EVERY pointer over the viewer — taps,
// drags, everything. Without an exclusion, a tap on ANY interactive chrome
// (a caption affordance, the store CTA, the reply field) ALSO fires the
// arbiter's tap navigation ("left third = previous story", "rest = next"),
// and a vertical drag over the caption's scrollable ALSO drags the viewer
// toward dismissal. Buttons must never double as story navigation.
//
// [StoryChromeRegion] marks a subtree as CHROME: the arbiter hit-tests the
// pointer down and, when the hit chain contains this marker, hands the
// pointer to the chrome entirely (no tap zones, no hold, no vertical
// dismissal, no pinch from within the region). Media outside every chrome
// region keeps the full gesture grammar untouched.
// =============================================================================

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Marks a subtree as interactive chrome for the story gesture arbiter.
class StoryChromeRegion extends SingleChildRenderObjectWidget {
  const StoryChromeRegion({super.key, super.child});

  @override
  RenderStoryChromeRegion createRenderObject(BuildContext context) =>
      RenderStoryChromeRegion();
}

/// The render marker the arbiter's hit test looks for.
class RenderStoryChromeRegion extends RenderProxyBox {
  RenderStoryChromeRegion();
}
