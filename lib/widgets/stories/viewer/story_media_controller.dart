// =============================================================================
// AZAMAN — STORY VIEWER: MEDIA CONTROLLER
//
// Loads ONE story's media. The feed does not send `mediaType` or
// `durationSeconds` (backend services/storyService.js), so the controller
// does not trust the model's defaults for kind decisions: it sniffs the URL
// extension. Videos play muted (existing viewer behaviour) and report their
// real duration and buffering state to the caller via onVideoReady /
// onBuffering.
// =============================================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'package:azaman/models/story_model.dart';

/// Kind sniffing for a feed that does not send `mediaType`.
enum StoryMediaKind { image, video }

abstract final class StoryMediaKindSniffer {
  static const _videoExtensions = {'.mp4', '.mov', '.webm', '.m4v', '.mkv'};

  static StoryMediaKind sniff(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return _videoExtensions.any(path.endsWith)
        ? StoryMediaKind.video
        : StoryMediaKind.image;
  }
}

class StoryMediaController extends ChangeNotifier {
  StoryMediaController(this.item, {this.onVideoReady, this.onBuffering});

  final StoryItem item;

  /// Called once a video's real [Duration] is known (never for images).
  final ValueChanged<Duration>? onVideoReady;

  /// Called on every buffering transition (true = stalling).
  final ValueChanged<bool>? onBuffering;

  VideoPlayerController? video;
  bool ready = false;
  bool _error = false;
  bool get hasError => _error;

  /// Media-kind truth: the model's `mediaType` only when the feed actually
  /// sent one, else the sniffed extension. The backend feed sends NEITHER
  /// today, so the sniff decides in practice; the model default ('IMAGE')
  /// is never trusted on its own.
  bool get isVideo {
    final sniffed = StoryMediaKindSniffer.sniff(item.mediaUrl);
    if (item.mediaType == 'VIDEO' || sniffed == StoryMediaKind.video) return true;
    return false;
  }

  bool get isBuffering => video?.value.isBuffering ?? false;

  /// Never plays audio from the viewer (existing behaviour; a story should
  /// not blast sound the moment it appears).
  Future<void> prepare() async {
    if (ready || _error) return;
    try {
      if (isVideo) {
        final controller = VideoPlayerController.networkUrl(Uri.parse(item.mediaUrl));
        video = controller;
        await controller.initialize();
        await controller.setLooping(false);
        await controller.setVolume(0.0);
        controller.addListener(_onVideoTick);
        onVideoReady?.call(controller.value.duration);
      }
      ready = true;
    } catch (_) {
      _error = true;
      video?.dispose();
      video = null;
    }
    notifyListeners();
  }

  bool _wasBuffering = false;
  void _onVideoTick() {
    final buffering = isBuffering;
    if (buffering != _wasBuffering) {
      _wasBuffering = buffering;
      onBuffering?.call(buffering);
    }
  }

  Future<void> play() async {
    if (ready && isVideo && video != null) await video!.play();
  }

  Future<void> pause() async {
    if (isVideo && video != null) await video!.pause();
  }

  /// Image provider handed to the cache widget; a single construction point
  /// so tests can observe what the page will paint.
  CachedNetworkImageProvider get imageProvider =>
      CachedNetworkImageProvider(item.mediaUrl);

  @override
  void dispose() {
    video?.removeListener(_onVideoTick);
    video?.dispose();
    video = null;
    super.dispose();
  }
}
