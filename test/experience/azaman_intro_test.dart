import 'dart:io';

import 'package:azaman/experience/launch/azaman_intro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_launch_video.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(backgroundColor: Colors.black, body: child),
);

Future<void> _settle(WidgetTester tester) async {
  // The init chain is a sequence of immediately-resolved futures; a couple of
  // pumps drains them without depending on real time.
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(resetLaunchPlayGuard);

  test('the launch clip is packaged as a real asset', () {
    final clip = File(kLaunchVideoAsset);
    expect(clip.existsSync(), isTrue, reason: kLaunchVideoAsset);
    // A few KB would mean a truncated or placeholder file.
    expect(clip.lengthSync(), greaterThan(50000));
  });

  testWidgets('plays the clip once, silently, and reports only at the end', (
    tester,
  ) async {
    final video = FakeLaunchVideo();
    var completed = 0;

    await tester.pumpWidget(
      _host(AzamanIntroPlayer(onCompleted: () => completed++, video: video)),
    );
    await _settle(tester);

    expect(video.playCalls, 1);
    expect(video.seekCalls, 1, reason: 'playback starts at the top');
    expect(video.volume, 0, reason: 'a launch must never make a sound');
    expect(completed, 0, reason: 'initialising is not finishing');

    video.advance(const Duration(milliseconds: 3000));
    await tester.pump();
    expect(completed, 0, reason: '3 s of a 3.83 s clip is not the end');

    video.advance(const Duration(milliseconds: 900));
    await tester.pump();
    expect(completed, 1);
  });

  testWidgets('the end of the clip is reported exactly once', (tester) async {
    final video = FakeLaunchVideo();
    var completed = 0;
    await tester.pumpWidget(
      _host(AzamanIntroPlayer(onCompleted: () => completed++, video: video)),
    );
    await _settle(tester);

    video.advance(AzamanIntro.total);
    await tester.pump();
    video.advance(const Duration(milliseconds: 200));
    await tester.pump();

    expect(completed, 1, reason: 'completion must not fire twice');
  });

  testWidgets('a second launch surface never replays the entrance', (
    tester,
  ) async {
    final first = FakeLaunchVideo();
    var completedFirst = 0;
    await tester.pumpWidget(
      _host(
        AzamanIntroPlayer(
          key: const ValueKey('first'),
          onCompleted: () => completedFirst++,
          video: first,
        ),
      ),
    );
    await _settle(tester);
    first.advance(AzamanIntro.total);
    await tester.pump();
    expect(completedFirst, 1);

    // A rebuild or an internal navigation mounts a new player in the same
    // process. It must move straight on, with no second performance.
    final second = FakeLaunchVideo();
    var completedSecond = 0;
    await tester.pumpWidget(
      _host(
        AzamanIntroPlayer(
          key: const ValueKey('second'),
          onCompleted: () => completedSecond++,
          video: second,
        ),
      ),
    );
    await _settle(tester);

    expect(second.playCalls, 0, reason: 'the entrance is once per process');
    expect(completedSecond, 1, reason: 'and it must not strand the caller');
  });

  testWidgets('a player that cannot start holds the settled lockup', (
    tester,
  ) async {
    final video = FakeLaunchVideo(failInitialize: true);
    var completed = 0;
    var failed = 0;

    await tester.pumpWidget(
      _host(
        AzamanIntroPlayer(
          onCompleted: () => completed++,
          onFailed: () => failed++,
          video: video,
        ),
      ),
    );
    await _settle(tester);

    expect(failed, 1);
    expect(completed, 0, reason: 'never claim the clip played');
    expect(find.byType(AzamanIntroStatic), findsOneWidget);
  });

  testWidgets('a failure mid-playback does not claim completion', (
    tester,
  ) async {
    final video = FakeLaunchVideo(failMidPlayback: true);
    var completed = 0;
    var failed = 0;
    await tester.pumpWidget(
      _host(
        AzamanIntroPlayer(
          onCompleted: () => completed++,
          onFailed: () => failed++,
          video: video,
        ),
      ),
    );
    await _settle(tester);

    video.advance(const Duration(milliseconds: 900));
    await tester.pump();

    expect(failed, 1);
    expect(completed, 0);
    expect(find.byType(AzamanIntroStatic), findsOneWidget);
  });

  testWidgets('before the first frame it holds the clip composition, not a '
      'second logo', (tester) async {
    final video = FakeLaunchVideo(gateInitialize: true);
    await tester.pumpWidget(
      _host(AzamanIntroPlayer(onCompleted: () {}, video: video)),
    );
    await tester.pump();

    // The decoder has not produced a frame yet. What is on screen is the
    // clip's own opening composition (the mark alone), never a second logo
    // and never an empty black canvas.
    expect(find.byKey(const ValueKey('launch-frame-zero')), findsOneWidget);
    expect(find.byKey(const ValueKey('clip-surface')), findsNothing);

    video.releaseInitialize();
    await _settle(tester);

    expect(find.byKey(const ValueKey('launch-frame-zero')), findsNothing);
    expect(find.byKey(const ValueKey('clip-surface')), findsOneWidget);
  });

  testWidgets('the settled state is readable in both brightnesses', (
    tester,
  ) async {
    for (final chrome in <IntroChrome>[IntroChrome.dark, IntroChrome.light]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AzamanIntroStatic(chrome: chrome)),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
    }
  });
}
