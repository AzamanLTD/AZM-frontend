// =============================================================================
// AZAMAN — STORY VIEWER: PLAYBACK CONTROLLER
//
// Owns WHICH story in a creator's group is showing and its progress. Plain
// ChangeNotifier + AnimationController: no Timer anywhere (Overhaul 05 §3.1).
// Pause reasons are OR-ed bits so overlapping causes (hold + zoom + sheet)
// resume deterministically only when every cause is released.
// =============================================================================

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import 'package:azaman/models/story_model.dart';

/// Independent pause causes; `hold(reason)` ORs the bit, `release` clears it.
enum PauseReason {
  hold(1),
  zoom(2),
  sheet(4),
  inactive(8),
  buffering(16);

  const PauseReason(this.bit);
  final int bit;
}

class StoryPlaybackController extends ChangeNotifier {
  StoryPlaybackController({
    required TickerProvider vsync,
    required this.group,
    required this.onGroupComplete,
    required this.onGroupRewindPast,
  }) : _progress = AnimationController(vsync: vsync) {
    _progress.addStatusListener((status) {
      if (status == AnimationStatus.completed) next();
    });
  }

  final StoryGroup group;

  /// Last item finished → shell goes to the NEXT creator (or pops).
  final VoidCallback onGroupComplete;

  /// Rewound before the first item → shell goes to the PREVIOUS creator.
  final VoidCallback onGroupRewindPast;

  final AnimationController _progress;

  int _index = 0;
  int _holds = 0;
  bool _active = false;

  int get index => _index;
  StoryItem get item => group.stories[_index];
  // AnimationController (not just Animation) so tests and the page can inspect
  // isAnimating and set duration; it stays a Listenable to consumers.
  AnimationController get progress => _progress;

  /// True while any pause reason is held.
  bool get isPaused => _holds != 0;

  bool get isActive => _active;

  /// Restarts the current item from zero at [initialIndex].
  void start({required int initialIndex}) {
    _index = initialIndex.clamp(0, group.stories.length - 1);
    _restart();
  }

  /// The shell flips this when the page becomes the active creator. An
  /// inactive page never advances on its own.
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    active ? release(PauseReason.inactive) : hold(PauseReason.inactive);
  }

  /// Sets the item duration (image seconds from the feed when supplied, or
  /// the video's real duration once the media controller knows it). Keeps the
  /// current progress value; playback resumes if nothing is holding it.
  void setDuration(Duration d) {
    if (d <= Duration.zero) return;
    final wasRunning = _progress.isAnimating;
    _progress.stop();
    _progress.duration = d;
    if (wasRunning || (!isPaused && _active && _progress.value > 0)) {
      _progress.forward(from: _progress.value);
    }
    notifyListeners();
  }

  /// Nominal duration for [item].
  ///
  /// Images: the feed sends no `durationSeconds` (services/storyService.js),
  /// so [StoryItem.durationSeconds] is the 5s image fallback; the model
  /// records whether the server actually supplied it
  /// ([StoryItem.durationSecondsProvided]) so nothing mistakes the fallback
  /// for a server claim. Videos: the real duration arrives from the media
  /// controller via [setDuration].
  static Duration durationFor(StoryItem item) =>
      Duration(seconds: item.durationSeconds.clamp(1, 60));

  void _restart() {
    _progress.stop();
    _progress.value = 0;
    _progress.duration = durationFor(item);
    notifyListeners();
    if (!isPaused && _active) _progress.forward();
  }

  void next() {
    if (_index < group.stories.length - 1) {
      _index++;
      _restart();
    } else {
      onGroupComplete();
    }
  }

  void previous() {
    if (_index > 0) {
      _index--;
      _restart();
    } else {
      onGroupRewindPast();
    }
  }

  void hold(PauseReason reason) {
    _holds |= reason.bit;
    _progress.stop();
    notifyListeners();
  }

  void release(PauseReason reason) {
    _holds &= ~reason.bit;
    // No duration yet means start() has not run: it will begin playback with
    // the item's duration. Guards release-before-start orderings (a page
    // becoming active before its first item is loaded).
    if (_progress.duration == null) {
      notifyListeners();
      return;
    }
    if (!isPaused && _active && _progress.status != AnimationStatus.completed) {
      _progress.forward(from: _progress.value);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }
}
