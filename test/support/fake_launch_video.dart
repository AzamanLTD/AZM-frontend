import 'package:azaman/experience/launch/azaman_intro.dart';
import 'dart:async';

import 'package:flutter/widgets.dart';

/// A controllable stand-in for the platform player.
///
/// The launch contract is about SEQUENCE, not about wall-clock video decoding:
/// it starts once, it does not report the end early, it holds its last frame,
/// and a failure never masquerades as a play. All of that is assertable with a
/// player whose position is advanced by hand.
class FakeLaunchVideo implements LaunchVideo {
  FakeLaunchVideo({
    this.clipDuration = AzamanIntro.total,
    this.failInitialize = false,
    this.aspectRatioValue = kLaunchAspectRatio,
    this.failMidPlayback = false,
    this.gateInitialize = false,
  });

  final Duration clipDuration;
  final bool failInitialize;
  final bool failMidPlayback;

  /// When true, [initialize] stays pending until [releaseInitialize] runs, so
  /// a test can observe what is painted before the first decoded frame.
  final bool gateInitialize;
  final Completer<void> _initGate = Completer<void>();

  void releaseInitialize() {
    if (!_initGate.isCompleted) _initGate.complete();
  }

  final double aspectRatioValue;

  final List<VoidCallback> _listeners = <VoidCallback>[];

  bool _initialized = false;
  bool _playing = false;
  bool _error = false;
  Duration _position = Duration.zero;

  int playCalls = 0;
  int seekCalls = 0;
  double? volume;
  bool disposed = false;

  @override
  bool get isInitialized => _initialized;
  @override
  bool get isPlaying => _playing;
  @override
  bool get hasError => _error;
  @override
  Duration get position => _position;
  @override
  Duration get duration => clipDuration;
  @override
  double get aspectRatio => aspectRatioValue;

  @override
  Future<void> initialize() async {
    if (failInitialize) {
      _error = true;
      throw StateError('no decoder');
    }
    if (gateInitialize) await _initGate.future;
    _initialized = true;
  }

  @override
  Future<void> setVolume(double value) async => volume = value;

  @override
  Future<void> play() async {
    playCalls++;
    _playing = true;
  }

  @override
  Future<void> seekTo(Duration position) async {
    seekCalls++;
    _position = position;
  }

  @override
  Future<void> dispose() async => disposed = true;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  Widget buildSurface() => const SizedBox.expand(key: ValueKey('clip-surface'));

  /// Moves playback forward the way the decoder would, notifying the widget.
  void advance(Duration delta) {
    _position += delta;
    if (_position >= clipDuration) {
      _position = clipDuration;
      _playing = false;
    }
    if (failMidPlayback && _position > Duration.zero) {
      _error = true;
    }
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }
}
