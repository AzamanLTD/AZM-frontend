// =============================================================================
// COMPACT BOTTOM NAV — visual evidence suite (2026-10-16).
//
// Captures PNG previews of the compact nav surfaces for the PR #157
// review record (the owner reviews from the PR, not the sandbox):
//
//   light/nav_home.png    / dark/nav_home.png
//     — rest pill: Home selected, its label expanded, + launcher beside
//   light/nav_market.png  / dark/nav_market.png
//     — focused Marketplace composition: Market label + search field
//   light/band_tabs.png   / dark/band_tabs.png
//     — the contextual band on a PUSHED route: the explicit Tabs control
//
// The captures land in .screenshots/ (untracked, ephemeral). Each capture
// also asserts the compact-nav contract on screen, so the file doubles as
// a visual regression guard: the pill wraps to content, the selected tab
// shows its measured label, and pushed routes offer a real Tabs control.
// =============================================================================

import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/providers/chat_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/sensory_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/router/route_depth.dart';
import 'package:azaman/router/top_route_observer.dart';
import 'package:azaman/widgets/contextual_nav_band.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:ui' show ImageByteFormat;

const _surfaceSize = Size(400, 900);
const _rootKey = Key('shot-root');

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final inter = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final interLoader = FontLoader('Inter')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(inter).buffer)),
    );
  await interLoader.load();
  final regular =
      await File('assets/fonts/ComicNeue-Regular.ttf').readAsBytes();
  final bold = await File('assets/fonts/ComicNeue-Bold.ttf').readAsBytes();
  final comicLoader = FontLoader('ComicNeue')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(regular).buffer)),
    )
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bold).buffer)),
    );
  await comicLoader.load();
  _fontsLoaded = true;
}

/// Captures the RepaintBoundary at the harness root to a PNG on disk.
/// `toImage`/file IO need REAL async, so the capture runs inside
/// `tester.runAsync`.
Future<void> _capture(WidgetTester tester, String name) async {
  var ok = false;
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_rootKey));
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = (await image.toByteData(format: ImageByteFormat.png))!;
    Directory('.screenshots').createSync(recursive: true);
    File('.screenshots/$name.png').writeAsBytesSync(data.buffer.asUint8List());
    ok = true;
  });
  expect(ok, isTrue, reason: 'capture $name wrote a PNG');
}

Future<ThemeProvider> _seedTheme(AzamanTheme theme) async {
  SharedPreferences.setMockInitialValues({
    'azaman_theme': theme == AzamanTheme.dark ? 1 : 0,
  });
  final p = ThemeProvider();
  int guard = 0;
  while (!p.isLoaded && guard++ < 100) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(p.isLoaded, isTrue);
  return p;
}

/// The + launcher stand-in the golden gate uses: a neutral square of the
/// real launcher's footprint, so the preview pins the NAV band's own
/// composition without baking the launcher's providers into the raster.
const _plusStandIn = SizedBox(
  key: ValueKey('plus-stand-in'),
  width: 54,
  height: 54,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final theme in AzamanTheme.values) {
    final mode = theme == AzamanTheme.dark ? 'dark' : 'light';

    testWidgets('nav rest pill preview — $mode', (tester) async {
      tester.view.physicalSize = _surfaceSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // ignore: unused_local_variable
      final tp = (await tester.runAsync(() => _seedTheme(theme)))!;
      await tester.binding.setSurfaceSize(_surfaceSize);
      await tester.runAsync(_loadFonts);
      AzSensory.apply(const SensoryPreferences());

      final container = ProviderContainer(
        overrides: [
          totalUnreadChatCountProvider.overrideWith((ref) async => 0),
          activeTradeCountProvider.overrideWith((ref) async => 0),
          unreadCountProvider.overrideWith((ref) => 0),
        ],
      );
      addTearDown(container.dispose);

      final colors = ThemeProvider.getColors(theme);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeProvider.getThemeData(theme),
            home: RepaintBoundary(
              key: _rootKey,
              // Plausible home scenery so the floating pill previews
              // against a real backdrop, not a void.
              child: Scaffold(
                backgroundColor: colors.background,
                body: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Azaman',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                bottomNavigationBar: PremiumBottomNav(
                  selectedIndex: 0,
                  onItemSelected: (_) {},
                  leading: _plusStandIn,
                ),
              ),
            ),
          ),
        ),
      );
      // Label tween settles to its expanded width.
      await tester.pumpAndSettle();

      // The compact contract is on screen before the capture ships.
      expect(find.text('Home'), findsOneWidget,
          reason: 'the selected tab shows its label');
      // Inactive tabs stay compact icon controls: their label text lives
      // in-tree at ZERO width (the widthFactor tween), never rendered.
      final chatOpacity = tester.widget<Opacity>(
        find.ancestor(of: find.text('Chat'), matching: find.byType(Opacity)).first,
      ).opacity;
      expect(chatOpacity, 0.0,
          reason: 'inactive tabs keep no visible label');
      expect(find.byKey(const ValueKey('plus-stand-in')), findsOneWidget);
      // The pill wraps to content, it never spans the band.
      final pillWidth = tester.getSize(
        find
            .descendant(
              of: find.byType(PremiumBottomNav),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      ).width;
      expect(pillWidth, lessThan(_surfaceSize.width - 54));

      await _capture(tester, '${mode}_nav_home');
    });

    testWidgets('nav focused market preview — $mode', (tester) async {
      tester.view.physicalSize = _surfaceSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // ignore: unused_local_variable
      final tp = (await tester.runAsync(() => _seedTheme(theme)))!;
      await tester.binding.setSurfaceSize(_surfaceSize);
      await tester.runAsync(_loadFonts);
      AzSensory.apply(const SensoryPreferences());

      final container = ProviderContainer(
        overrides: [
          totalUnreadChatCountProvider.overrideWith((ref) async => 0),
          activeTradeCountProvider.overrideWith((ref) async => 0),
          unreadCountProvider.overrideWith((ref) => 0),
        ],
      );
      addTearDown(container.dispose);

      final colors = ThemeProvider.getColors(theme);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeProvider.getThemeData(theme),
            home: RepaintBoundary(
              key: _rootKey,
              child: Scaffold(
                backgroundColor: colors.background,
                body: const SizedBox.expand(),
                bottomNavigationBar: PremiumBottomNav(
                  selectedIndex: 2,
                  onItemSelected: (_) {},
                  leading: _plusStandIn,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Market'), findsOneWidget,
          reason: 'Market announces its short identity');

      await _capture(tester, '${mode}_nav_market');
    });

    testWidgets('pushed-route band preview — $mode', (tester) async {
      tester.view.physicalSize = _surfaceSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // ignore: unused_local_variable
      final tp = (await tester.runAsync(() => _seedTheme(theme)))!;
      await tester.binding.setSurfaceSize(_surfaceSize);
      await tester.runAsync(_loadFonts);
      AzSensory.apply(const SensoryPreferences());

      // The band's visibility gate requires an engaged shell bus: the
      // same seam the real shell uses when it hosts the band.
      appShellBus.engage(onTabRequest: (_) {}, initialTab: 0);
      addTearDown(appShellBus.debugReset);

      final router = GoRouter(
        observers: [topRouteObserver],
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: SizedBox()),
          ),
          GoRoute(
            path: '/transactions',
            builder: (_, __) => Scaffold(
              backgroundColor: ThemeProvider.getColors(theme).background,
              body: const SizedBox.expand(),
            ),
          ),
        ],
      );
      final tracker = RouteDepthTracker(router);
      addTearDown(tracker.dispose);

      final container = ProviderContainer(
        overrides: [
          totalUnreadChatCountProvider.overrideWith((ref) async => 0),
          activeTradeCountProvider.overrideWith((ref) async => 0),
          unreadCountProvider.overrideWith((ref) => 0),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            theme: ThemeProvider.getThemeData(theme),
            builder: (context, child) => RepaintBoundary(
              key: _rootKey,
              child: RouteDepthTrackerHost(
                tracker: tracker,
                child: Stack(
                  children: [
                    child ?? const SizedBox.shrink(),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ContextualNavBand(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      router.push('/transactions');
      await tester.pumpAndSettle();

      // The pushed-route contract: an explicit Tabs control — never an
      // ellipsis.
      expect(find.text('Tabs'), findsOneWidget);
      expect(find.bySemanticsLabel('Switch tabs'), findsOneWidget);

      await _capture(tester, '${mode}_band_tabs');
    });
  }
}
