// =============================================================================
// AZAMAN — STORY VIEWER: SCREEN + SHELL
//
// Replaces the single-controller viewer (Overhaul 05 §5). The public opener
// keeps the exact existing signature — callers (friends hub, messages hub,
// marketplace) are untouched. The shell owns: horizontal creator paging
// (PageView under the gesture arbiter), vertical dismiss, and the details
// sheet gate. Per-creator playback lives in StoryGroupPage.
//
// Motion: page slides use MotionTokens.spatial, dismiss spring-back uses
// MotionTokens.exit; under reduced motion every duration collapses to zero
// via AzMotion and Heroes are skipped entirely.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/experience/gateways/story_gateway.dart';
import 'package:azaman/models/story_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/widgets/azaman_sheet.dart';
import 'package:azaman/widgets/stories/viewer/story_details_sheet.dart';
import 'package:azaman/widgets/stories/viewer/story_gesture_arbiter.dart';
import 'package:azaman/widgets/stories/viewer/story_group_page.dart';

class StoryViewerScreen extends ConsumerStatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.groups,
    this.initialGroupIndex = 0,
    this.heroTag,
  });

  final List<StoryGroup> groups;
  final int initialGroupIndex;
  final String? heroTag;

  /// Same container-transform open as the legacy viewer (fade + scale-up),
  /// collapsing to an instant switch under reduced motion.
  static Future<void> open(
    BuildContext context, {
    required List<StoryGroup> groups,
    int initialGroupIndex = 0,
    String? heroTag,
  }) {
    final duration = AzMotion.duration(context, MotionTokens.emphasized);
    return Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      opaque: true,
      pageBuilder: (_, __, ___) => StoryViewerScreen(
        groups: groups,
        initialGroupIndex: initialGroupIndex,
        heroTag: heroTag,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: MotionTokens.enter);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    ));
  }

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pages =
      PageController(initialPage: widget.initialGroupIndex);
  final ValueNotifier<int> _active = ValueNotifier(0);
  final ValueNotifier<double> _dismiss = ValueNotifier(0); // 0..1
  final Map<int, StoryPageHandle> _pageHandles = {};
  late final AnimationController _dismissAnim;

  @override
  void initState() {
    super.initState();
    _active.value = widget.initialGroupIndex;
    _dismissAnim = AnimationController(
      vsync: this,
      duration: MotionTokens.standard,
    )..addListener(() => _dismiss.value = _dismissAnim.value);
    _pages.addListener(_onPageScroll);
  }

  void _onPageScroll() {
    final page = _pages.page;
    if (page == null) return;
    final rounded = page.round();
    // The active creator flips at the drag midpoint, not on release, so the
    // outgoing page's playback stops while it is still partially visible.
    if (rounded != _active.value && (page - rounded).abs() < 0.5) {
      _active.value = rounded;
    }
  }

  void _goToGroup(int i) {
    if (i < 0 || i >= widget.groups.length) {
      Navigator.of(context).maybePop();
      return;
    }
    final travel = AzMotion.of(context).travel;
    travel
        ? _pages.animateToPage(
            i,
            duration: MotionTokens.spatial,
            curve: MotionTokens.enter,
          )
        : _pages.jumpToPage(i);
  }

  void _verticalUpdate(double dy) {
    final h = MediaQuery.sizeOf(context).height;
    if (dy > 0 || _dismiss.value > 0) {
      // Pull down (or already dismissing) → grow dismiss progress.
      _dismiss.value = (_dismiss.value + dy / (h * 0.5)).clamp(0.0, 1.0);
    } else if (dy < -12 && _dismiss.value == 0) {
      _openDetails();
    }
  }

  void _verticalEnd(double velocity) {
    if (_dismiss.value == 0) return;
    final commit = _dismiss.value >= 0.35 || velocity > 900;
    if (commit) {
      Navigator.of(context).maybePop();
      return;
    }
    if (!AzMotion.of(context).travel) {
      _dismiss.value = 0; // reduced motion: settle instantly
      return;
    }
    _dismissAnim.value = _dismiss.value;
    _dismissAnim.animateTo(0, curve: MotionTokens.exit);
  }

  void _openDetails() {
    final handle = _pageHandles[_active.value];
    if (handle == null) return;
    final capabilities = ref.read(storyGatewayProvider).capabilities;
    // The sheet offers only capability-gated affordances; with the real
    // gateway neither viewers nor reactions exist, so the swipe-up is a
    // deliberate no-op rather than an empty sheet.
    if (!capabilities.contains(StoryCapability.viewers) &&
        !capabilities.contains(StoryCapability.react)) {
      return;
    }
    final group = widget.groups[_active.value];
    final user = ref.read(currentUserProvider).value;
    final currentUserId = int.tryParse(user?.id ?? '');
    handle.sheetPause();
    AzamanSheet.showPanel<void>(
      context,
      builder: (ctx, sc) => StoryDetailsSheet(
        story: handle.currentStory(),
        authorId: group.authorId,
        currentUserId: currentUserId ?? -1,
      ),
    ).whenComplete(() => handle.sheetResume());
  }

  @override
  void dispose() {
    _pages.removeListener(_onPageScroll);
    _pages.dispose();
    _active.dispose();
    _dismiss.dispose();
    _dismissAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<double>(
        valueListenable: _dismiss,
        builder: (context, dismiss, child) => Container(
          color: Colors.black.withValues(alpha: 1 - 0.6 * dismiss),
          child: child,
        ),
        child: StoryGestureArbiter(
          pageController: _pages,
          callbacks: StoryGestureCallbacks(
            onTap: (right) => _pageHandles[_active.value]?.tap(right),
            onHoldStart: () => _pageHandles[_active.value]?.holdStart(),
            onHoldEnd: () => _pageHandles[_active.value]?.holdEnd(),
            onVerticalUpdate: _verticalUpdate,
            onVerticalEnd: _verticalEnd,
            onPinchScale: (scale) =>
                _pageHandles[_active.value]?.pinch(scale),
            onPinchEnd: () => _pageHandles[_active.value]?.pinchEnd(),
          ),
          child: PageView.builder(
            controller: _pages,
            // NeverScrollable: the arbiter owns horizontal gestures and
            // forwards them through position.drag; the PageScrollPhysics
            // parent keeps the page snap on release.
            physics: const NeverScrollableScrollPhysics(
              parent: PageScrollPhysics(),
            ),
            itemCount: widget.groups.length,
            itemBuilder: (context, i) => StoryGroupPage(
              group: widget.groups[i],
              myIndex: i,
              activeIndex: _active,
              dismissProgress: _dismiss,
              initialItem: _firstUnseen(widget.groups[i]),
              onComplete: () => _goToGroup(i + 1),
              onRewindPast: () => _goToGroup(i - 1),
              onHandleReady: (index, handle) => _pageHandles[index] = handle,
              onHandleRemoved: (index) => _pageHandles.remove(index),
              heroTag: i == widget.initialGroupIndex ? widget.heroTag : null,
            ),
          ),
        ),
      ),
    );
  }

  int _firstUnseen(StoryGroup group) {
    final i = group.stories.indexWhere((s) => !s.seen);
    return i < 0 ? 0 : i;
  }
}
