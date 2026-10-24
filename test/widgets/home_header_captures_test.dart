// WORKSTREAM A — capture evidence for the Home persistent header and the
// pull-down notification centre.
//
// The delivery contract for every frontend PR: 320/360/390dp widths ×
// light/dark themes × the surface's relevant states. For this surface:
//
//   header_top      — Home at rest: the pinned band paints NOTHING over
//                     the content (transparent at the top of Home).
//   header_frosted  — scrolled: the same band frosts (tint + blur over
//                     the content moving behind it), driven by the real
//                     scroll offset.
//   centre_open     — the in-app notification centre fully open (bell
//                     tap), seeded with the same committed-state list
//                     the behaviour battery uses.
//
// Pixel-truth checks (same harness discipline as the Quiet Depth capture
// suite): every captured pixel must be OPAQUE — the boundary must wrap an
// opaque surface (a clear buffer reads as white pills on GitHub's review
// background), and the frosted band must DIFFER from the resting band in
// the same capture set (the frost is a real scroll response, not a
// permanent paint).

import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/models/notification_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/widgets/notification_bell.dart';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _rootKey = ValueKey('home-header-capture-root');
const _height = 780.0;
const _widths = [320.0, 360.0, 390.0];

bool _fontsLoaded = false;
Future<void> _loadFace(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
  await loader.load();
}

Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  await _loadFace('Inter', 'assets/fonts/Inter-Variable.ttf');
  // Package icons resolve under the package-qualified family key —
  // the bare family name leaves tofu squares in the captures.
  await _loadFace('packages/hugeicons_pro/HugeIconsSolid',
      'test/goldens/fonts/hugeicons-solid.ttf');
  await _loadFace('packages/hugeicons_pro/HugeIconsStroke',
      'test/goldens/fonts/hugeicons-stroke.ttf');
  await _loadFace(
      'MaterialIcons', 'test/goldens/fonts/MaterialIcons-Regular.otf');
  _fontsLoaded = true;
}

class _SeededNotifications extends NotificationNotifier {
  _SeededNotifications(super.ref, List<AppNotification> seed) {
    state = seed;
  }
}

List<AppNotification> _manyNotifications() {
  return List<AppNotification>.generate(
    30,
    (i) => AppNotification(
      id: 'n$i',
      title: 'Notification $i',
      body: 'Committed body $i',
      category: NotificationCategory.general,
      createdAt: DateTime(2026, 10, 24, 12 - (i ~/ 5)),
    ),
  );
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required AzamanTheme theme,
  required double width,
}) async {
  final surface = Size(width, _height);
  SharedPreferences.setMockInitialValues({
    'has_seen_flippable_card_hint': true,
    'azaman_theme': theme == AzamanTheme.dark ? 1 : 0,
  });
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(surface);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
        (ref) => const BalanceData(availableBalance: 100),
      ),
      oracleRateProvider.overrideWith((ref) => 1.0),
      notificationProvider.overrideWith(
        (ref) => _SeededNotifications(ref, _manyNotifications()),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) {
          final bg = ref.watch(themeProvider.select((t) => t.colors.surface));
          // The capture boundary wraps the WHOLE app: the notification
          // centre mounts in the root overlay (an ancestor of Home's
          // Scaffold), so a Home-only boundary would crop it. The
          // opaque themed surface sits INSIDE the boundary — toImage()
          // rasterises only this subtree.
          return RepaintBoundary(
            key: _rootKey,
            child: ColoredBox(
              color: bg,
              child: MaterialApp(
                theme: ThemeProvider.getThemeData(theme),
                // The notification centre mounts in the ROOT overlay
                // (above home's own MediaQuery wrapper) — override the
                // window there too, exactly as production does with one
                // real window.
                builder: (context, child) => MediaQuery(
                  data: MediaQueryData(size: surface),
                  child: child!,
                ),
                home: Scaffold(
                  body: AzamanHomePage(onOpenSettings: () {}),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  // Entrance choreography drains (bounded — no repeating controllers
  // are waited on).
  for (var t = 0; t < 600; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Captures the WHOLE window (the notification centre lives in the root
/// overlay, an ancestor of Home's Scaffold — a Home-only boundary would
/// crop it). The opaque themed surface sits INSIDE the boundary.
Future<Uint8List> _capture(
  WidgetTester tester,
  String name, {
  required AzamanTheme theme,
  required int imgW,
  required int imgH,
}) async {
  late Uint8List rgba;
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_rootKey));
    final image = await boundary.toImage(pixelRatio: 2.0);
    final png = (await image.toByteData(format: ImageByteFormat.png))!;
    final dir = Directory('.screenshots/home_header')..createSync(recursive: true);
    await File('${dir.path}/$name.png').writeAsBytes(png.buffer.asUint8List());
    rgba = (await image.toByteData(format: ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
  });
  // Every pixel opaque: the capture must never composite over a clear
  // buffer.
  for (var i = 3; i < rgba.length; i += 4) {
    expect(rgba[i], 255,
        reason: '$name: capture must be fully opaque (pixel ${(i - 3) ~/ 4})');
  }
  expect(rgba.length, imgW * 2 * imgH * 2 * 4,
      reason: '$name: unexpected raster dimensions');
  return rgba;
}

/// Mean absolute per-channel difference between two captures over a
/// horizontal band strip (logical [yFrom, yTo], full width inset by 12
/// to avoid the notch's rounded corners).
double _bandDelta(
  Uint8List a,
  Uint8List b,
  double width, {
  required int yFrom,
  required int yTo,
}) {
  final px = (width * 2).round();
  var sum = 0.0;
  var count = 0;
  for (var y = yFrom * 2; y < yTo * 2; y++) {
    for (var x = 24; x < px - 24; x++) {
      final i = (y * px + x) * 4;
      sum += ((a[i] - b[i]).abs() +
              (a[i + 1] - b[i + 1]).abs() +
              (a[i + 2] - b[i + 2]).abs()) /
          3;
      count++;
    }
  }
  return sum / count;
}

void main() {
  for (final theme in AzamanTheme.values) {
    for (final w in _widths) {
      final themeName = theme.name;
      testWidgets(
          'captures the header surface at ${w.round()}dp $themeName',
          (tester) async {
        await _pumpHome(tester, theme: theme, width: w);

        // 1. At rest: the band is transparent — nothing frosted.
        final top = await _capture(
          tester,
          'header_top_${w.round()}_$themeName',
          theme: theme,
          imgW: w.round(),
          imgH: _height.round(),
        );

        // 2. Scrolled: the band frosts over the moving content.
        final scrollable = find.byType(Scrollable).first;
        final position =
            tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(position.maxScrollExtent.clamp(0, 420));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('home-header-surface')),
            findsOneWidget,
            reason: 'scrolled, the frost surface must be mounted');
        final frosted = await _capture(
          tester,
          'header_frosted_${w.round()}_$themeName',
          theme: theme,
          imgW: w.round(),
          imgH: _height.round(),
        );

        // Scroll back so the frost leaves before opening the centre.
        position.jumpTo(0);
        await tester.pump(const Duration(milliseconds: 100));

        // 3. The notification centre, fully open, seeded.
        await tester.tap(find.byType(NotificationBell));
        for (var t = 0; t < 2400; t += 50) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.text('Notifications'), findsOneWidget);
        await _capture(
          tester,
          'centre_open_${w.round()}_$themeName',
          theme: theme,
          imgW: w.round(),
          imgH: _height.round(),
        );

        // The frost is a REAL scroll response: the band strip must
        // visibly differ between rest and scroll in both themes.
        // (The strip avoids the notch: 8..40 logical px, within the
        // band's controls region.)
        final delta =
            _bandDelta(top, frosted, w, yFrom: 8, yTo: 40);
        expect(delta, greaterThan(2.0),
            reason:
                '$themeName ${w.round()}dp: the frosted band must differ '
                'visibly from the resting band (mean channel delta $delta)');
      });
    }
  }
}
