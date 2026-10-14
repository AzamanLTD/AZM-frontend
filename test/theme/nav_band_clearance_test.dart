// NAV BAND CLEARANCE — contract tests (persistent-nav occlusion fix).
//
// The whole fix rests on ONE platform fact: a Scaffold with
// `extendBody: true` publishes the bottom widget's height into the body's
// MediaQuery padding.bottom. These tests pin that contract so the
// abstraction can never silently drift from the framework behaviour.

import 'package:azaman/theme/nav_band_clearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in band of a fixed height — PremiumBottomNav's exact pixel
/// math is covered by the nav suites; here only the Scaffold contract
/// matters.
class _FixedBand extends StatelessWidget implements PreferredSizeWidget {
  const _FixedBand({required this.height});

  final double height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}

Widget _probe(Widget? band, WidgetBuilder page) {
  return MaterialApp(
    home: Scaffold(
      extendBody: band != null,
      bottomNavigationBar: band,
      body: Builder(builder: page),
    ),
  );
}

void main() {
  testWidgets('under the shell, navBandClearance equals the band height',
      (tester) async {
    late double read;
    await tester.pumpWidget(_probe(
      const _FixedBand(height: 92),
      (context) {
        read = navBandClearance(context);
        return const SizedBox.shrink();
      },
    ));

    // extendBody publishes max(safe-area bottom, band height); the test
    // surface has no system inset, so this must be exactly the band.
    expect(read, 92);
  });

  testWidgets('band height wins when larger than the safe-area inset',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding =
        const FakeViewPadding(bottom: 40); // 40px system inset
    addTearDown(tester.view.reset);

    late double read;
    await tester.pumpWidget(_probe(
      const _FixedBand(height: 92),
      (context) {
        read = navBandClearance(context);
        return const SizedBox.shrink();
      },
    ));

    expect(read, 92); // max(40, 92)
  });

  testWidgets('without a band, clearance degrades to the safe area only',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding =
        const FakeViewPadding(bottom: 40);
    addTearDown(tester.view.reset);

    late double read;
    await tester.pumpWidget(_probe(
      null,
      (context) {
        read = navBandClearance(context);
        return const SizedBox.shrink();
      },
    ));

    // Pushed screens (no persistent band) must never inherit the shell's
    // band height — they only ever see the system safe area.
    expect(read, 40);
  });

  testWidgets('clearance tracks a band whose height changes between frames',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    double bandHeight = 92;
    late double read;
    Widget buildHarness() => _probe(
          _FixedBand(height: bandHeight),
          (context) {
            read = navBandClearance(context);
            return const SizedBox.shrink();
          },
        );

    await tester.pumpWidget(buildHarness());
    expect(read, 92);

    // The pill compresses while the page scrolls — the published inset
    // must follow within a frame, so surfaces anchored to the clearance
    // (e.g. the map recenter button) rise with it instead of waiting
    // under the old footprint.
    bandHeight = 64;
    await tester.pumpWidget(buildHarness());
    await tester.pump();
    expect(read, 64);
  });

  test('kNavBandGap keeps breathing room between content and the band', () {
    // Reachable must not mean "kissing the pill": the gap is part of the
    // occlusion contract, pinned so it cannot be quietly removed.
    expect(kNavBandGap, 16);
  });
}
