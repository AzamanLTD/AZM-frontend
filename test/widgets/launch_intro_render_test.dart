// Renders the launch intro at the reference clip's own timestamps so the
// rebuilt motion can be compared frame-for-frame with the approved video.
//
// This is a measurement tool, not a golden test: it writes to the system temp
// directory. The golden captures that guard the shipped look live in
// test/widgets/launch_intro_test.dart.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/launch/azaman_intro.dart';

const _captureKey = ValueKey('intro-capture-root');
bool _fonts = false;

Future<void> _loadFonts() async {
  if (_fonts) return;
  final inter = await rootBundle.load('assets/fonts/Inter-Variable.ttf');
  await (FontLoader('Inter')..addFont(Future.value(inter))).load();
  _fonts = true;
}

void main() {
  testWidgets('render the intro at the reference timestamps', (tester) async {
    await tester.runAsync(_loadFonts);
    // The clip is 656 x 848.
    await tester.binding.setSurfaceSize(const Size(656, 848));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dir = Directory('${Directory.systemTemp.path}/launch_frames');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);

    late AnimationController controller;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: RepaintBoundary(
          key: _captureKey,
          child: Builder(
            builder: (context) {
              controller = AnimationController(
                vsync: tester,
                duration: AzamanIntro.total,
              );
              return AzamanIntroPlayer(
                controllerOverride: controller,
                onCompleted: () {},
                chrome: IntroChrome.dark,
              );
            },
          ),
        ),
      ),
    );

    const stamps = <int>[
      0,
      100,
      200,
      400,
      600,
      800,
      1000,
      1100,
      1200,
      1300,
      1340,
      1400,
      1450,
      1500,
      1550,
      1600,
      1700,
      1800,
      1900,
      2000,
      2100,
      2200,
      2400,
      2600,
      3000,
      3400,
      3800,
    ];
    for (final ms in stamps) {
      controller.value = ms / AzamanIntro.total.inMilliseconds;
      await tester.pump();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_captureKey),
      );
      final bytes = await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1);
        final bd = await img.toByteData(format: ui.ImageByteFormat.png);
        return bd!.buffer.asUint8List();
      });
      File(
        '${dir.path}/t${ms.toString().padLeft(4, '0')}.png',
      ).writeAsBytesSync(bytes as Uint8List);
    }
    // ignore: avoid_print
    print('CAPTURE_DIR=${dir.path}');
    expect(dir.listSync().length, stamps.length);
  });
}
