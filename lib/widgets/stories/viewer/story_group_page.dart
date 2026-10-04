// =============================================================================
// AZAMAN — STORY VIEWER: GROUP PAGE
//
// ONE creator's stories inside the viewer's PageView (Overhaul 05 §4).
// Owns its playback controller and a bounded media map (index ± 1). Only the
// ACTIVE page advances and marks views; inactive pages pause their media and
// stop progressing. The shell forwards gesture outcomes through
// [StoryPageHandle]; no GlobalKeys, no cross-page state.
// =============================================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import 'package:azaman/experience/gateways/story_gateway.dart';
import 'package:azaman/experience/motion/az_identity_morph.dart';
import 'package:azaman/models/story_model.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/widgets/story_ring.dart';
import 'package:azaman/widgets/stories/viewer/story_business_tray.dart';
import 'package:azaman/widgets/stories/viewer/story_interaction_bar.dart';
import 'package:azaman/widgets/stories/viewer/story_media_controller.dart';
import 'package:azaman/widgets/stories/viewer/story_playback_controller.dart';
import 'package:azaman/widgets/stories/viewer/story_progress_bar.dart';

/// Gesture outcomes the shell forwards to the ACTIVE page. Implemented by
/// the page state; registered through [StoryGroupPage.onHandleReady].
abstract interface class StoryPageHandle {
  /// The story this page is currently showing (used by the details sheet).
  StoryItem currentStory();

  void tap(bool rightSide);
  void holdStart();
  void holdEnd();
  void pinch(double scale);
  void pinchEnd();

  /// Pause/resume for modal layers above the viewer (details sheet, profile
  /// route) — a distinct reason from finger-hold so they never cancel out.
  void sheetPause();
  void sheetResume();
}

class StoryGroupPage extends ConsumerStatefulWidget {
  const StoryGroupPage({
    super.key,
    required this.group,
    required this.myIndex,
    required this.activeIndex,
    required this.dismissProgress,
    required this.initialItem,
    required this.onComplete,
    required this.onRewindPast,
    required this.onHandleReady,
    required this.onHandleRemoved,
    this.heroTag,
  });

  final StoryGroup group;
  final int myIndex;

  /// The shell's active-creator index; this page is live iff it matches
  /// [myIndex].
  final ValueListenable<int> activeIndex;

  /// Shell dismiss drag progress 0..1 for the shrink-away effect.
  final ValueListenable<double> dismissProgress;

  final int initialItem;
  final VoidCallback onComplete;
  final VoidCallback onRewindPast;

  /// Handle registration so the shell can forward arbiter outcomes without
  /// GlobalKey reach-in.
  final void Function(int index, StoryPageHandle handle) onHandleReady;
  final void Function(int index) onHandleRemoved;

  /// Legacy Hero tag (marketplace passes its ring tag); otherwise the
  /// canonical story identity tag is used.
  final String? heroTag;

  @override
  ConsumerState<StoryGroupPage> createState() => _StoryGroupPageState();
}

class _StoryGroupPageState extends ConsumerState<StoryGroupPage>
    with SingleTickerProviderStateMixin
    implements StoryPageHandle {
  late final StoryPlaybackController _playback;
  final Map<int, StoryMediaController> _media = {};
  double _zoom = 1;

  bool get _isActive => widget.activeIndex.value == widget.myIndex;

  @override
  void initState() {
    super.initState();
    _playback = StoryPlaybackController(
      vsync: this,
      group: widget.group,
      onGroupComplete: widget.onComplete,
      onGroupRewindPast: widget.onRewindPast,
    )..addListener(_onPlaybackChanged);
    widget.activeIndex.addListener(_onActiveChanged);
    widget.onHandleReady(widget.myIndex, this);
    // start() notifies the playback listener synchronously, whose
    // _ensureMedia precaches images (a MediaQuery dependency) — that must
    // not happen inside initState. Same for the initial activation pass:
    // both are deferred to the first frame, which is also when the media
    // actually becomes visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _playback.start(initialIndex: widget.initialItem);
      _onActiveChanged();
    });
  }

  @override
  void dispose() {
    widget.onHandleRemoved(widget.myIndex);
    widget.activeIndex.removeListener(_onActiveChanged);
    _playback.dispose();
    for (final m in _media.values) {
      m.dispose();
    }
    _media.clear();
    super.dispose();
  }

  void _onActiveChanged() {
    _playback.setActive(_isActive);
    if (_isActive) {
      _ensureMedia(_playback.index);
      _media[_playback.index]?.play();
      _markViewed();
    } else {
      for (final m in _media.values) {
        m.pause();
      }
    }
  }

  void _onPlaybackChanged() {
    final i = _playback.index;
    _ensureMedia(i);
    _ensureMedia(i + 1);
    _ensureMedia(i - 1);
    for (final e in _media.entries.toList()) {
      if ((e.key - i).abs() > 1) {
        e.value.dispose();
        _media.remove(e.key);
      }
    }
    if (_isActive) {
      _media[i]?.play();
      _markViewed();
    }
    setState(() {}); // page-local rebuild: media/caption/header swap only
  }

  void _markViewed() {
    // Deduped inside the gateway; the POST is fire-and-forget (existing
    // notifier swallows errors) and never blocks playback.
    ref.read(storyGatewayProvider).markViewed(_playback.item.id);
  }

  void _ensureMedia(int i) {
    if (i < 0 || i >= widget.group.stories.length || _media.containsKey(i)) {
      return;
    }
    final controller = StoryMediaController(
      widget.group.stories[i],
      onVideoReady: (duration) {
        if (i == _playback.index) _playback.setDuration(duration);
      },
      onBuffering: (buffering) {
        if (i != _playback.index) return;
        buffering
            ? _playback.hold(PauseReason.buffering)
            : _playback.release(PauseReason.buffering);
      },
    );
    _media[i] = controller;
    controller.prepare().then((_) {
      if (!mounted) return;
      if (i == _playback.index && controller.isVideo && controller.video != null) {
        if (_isActive) controller.play();
      }
    });
    if (!controller.isVideo && mounted) {
      // Neighbour prefetch without a context-dependent controller API.
      precacheImage(controller.imageProvider, context).catchError((_) {});
    }
  }

  // ── StoryPageHandle: forwarded by the shell's arbiter ─────────────────────

  @override
  StoryItem currentStory() => _playback.item;

  @override
  void tap(bool rightSide) =>
      rightSide ? _playback.next() : _playback.previous();

  @override
  void holdStart() => _playback.hold(PauseReason.hold);

  @override
  void holdEnd() => _playback.release(PauseReason.hold);

  @override
  void pinch(double scale) {
    // Images only — video zoom would desync from playback geometry.
    if (_media[_playback.index]?.isVideo ?? true) return;
    _playback.hold(PauseReason.zoom);
    setState(() => _zoom = scale.clamp(1.0, 3.0));
  }

  @override
  void pinchEnd() {
    if (!_playback.isPaused && _zoom == 1) return;
    setState(() => _zoom = 1);
    _playback.release(PauseReason.zoom);
  }

  @override
  void sheetPause() => _playback.hold(PauseReason.sheet);

  @override
  void sheetResume() => _playback.release(PauseReason.sheet);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final item = _playback.item;
    final media = _media[_playback.index];
    final travel = AzMotion.of(context).travel;

    return ValueListenableBuilder<double>(
      valueListenable: widget.dismissProgress,
      builder: (context, dismiss, child) =>
          Transform.scale(scale: 1 - 0.15 * dismiss, child: child),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: Center(
              child: media == null
                  ? const _MediaLoadingState()
                  : media.hasError
                      ? const _MediaErrorState()
                      : !media.ready
                          ? const _MediaLoadingState()
                          // AnimatedScale tracks the pinch and springs back
                          // to 1x on release; reduced motion collapses the
                          // duration to zero (AzMotion.duration).
                          : AnimatedScale(
                              scale: _zoom,
                              duration:
                                  AzMotion.duration(context, MotionTokens.standard),
                              curve: MotionTokens.enter,
                              child: media.isVideo && media.video != null
                                  ? AspectRatio(
                                      aspectRatio:
                                          media.video!.value.aspectRatio,
                                      child: VideoPlayer(media.video!),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: item.mediaUrl,
                                      fit: BoxFit.contain,
                                      placeholder: (_, __) =>
                                          Container(color: Colors.black),
                                      errorWidget: (_, __, ___) =>
                                          const _MediaErrorState(),
                                    ),
                            ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black54,
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black54
                ],
                stops: [0.0, 0.2, 0.7, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                StoryProgressBar(
                  count: widget.group.stories.length,
                  index: _playback.index,
                  progress: _playback.progress,
                  boosted: item.boosted,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AzSpace.lg, vertical: AzSpace.sm),
                  child: Row(
                    children: [
                      travel
                          ? Hero(
                              tag: widget.heroTag ??
                                  AzIdentityTag.story(widget.group.authorId),
                              child: _ring(),
                            )
                          : _ring(),
                      const SizedBox(width: AzSpace.sm),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.group.authorUsername,
                            style: AzText.label.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${_playback.index + 1} of '
                            '${widget.group.stories.length}',
                            style: AzText.caption.copyWith(
                                color: Colors.white.withValues(alpha: 0.5)),
                          ),
                        ],
                      ),
                      if (item.boosted) ...[
                        const SizedBox(width: AzSpace.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amberAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bolt,
                                  color: Colors.amberAccent, size: 12),
                              SizedBox(width: 2),
                              Text('BOOSTED',
                                  style: TextStyle(
                                      color: Colors.amberAccent,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 22),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (item.caption?.isNotEmpty ?? false)
            Positioned(
              left: AzSpace.xl,
              right: AzSpace.xl,
              bottom: 140,
              child: Text(
                item.caption!,
                style: AzText.bodyL.copyWith(
                  color: Colors.white,
                  shadows: const [
                    Shadow(blurRadius: 8, color: Colors.black54),
                  ],
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (item.linkedBizId != null)
            Positioned(
              left: AzSpace.xl,
              right: AzSpace.xl,
              bottom: 88,
              child: StoryBusinessTray(
                bizId: item.linkedBizId!,
                onPause: () => _playback.hold(PauseReason.sheet),
                onResume: () => _playback.release(PauseReason.sheet),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: StoryInteractionBar(
              story: item,
              authorId: widget.group.authorId,
              onFocusChanged: (focused) => focused
                  ? _playback.hold(PauseReason.sheet)
                  : _playback.release(PauseReason.sheet),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring() => StoryRing(
        avatarUrl: widget.group.authorAvatarUrl,
        hasUnseenStory: false,
        isBoosted: false,
        size: 36,
      );
}

class _MediaLoadingState extends StatelessWidget {
  const _MediaLoadingState();

  @override
  Widget build(BuildContext context) => const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
}

class _MediaErrorState extends StatelessWidget {
  const _MediaErrorState();

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black12,
        child: const Center(
          child: Icon(Icons.broken_image, color: Colors.white30, size: 48),
        ),
      );
}
