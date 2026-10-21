// =============================================================================
// SETTINGS REDESIGN — visual evidence suite (2026-10-16).
//
// Captures PNG previews of the redesigned settings surfaces for the PR
// review record (the owner reviews from the PR, not the sandbox):
//
//   dark/drawer.png    — drawer: pinned hero, quick actions, chips, groups
//   light/drawer.png   — same composition in light glass
//   dark/settings.png  — settings page: account header card + new IA
//   light/settings.png — same page in light mode
//
// The captures land in .screenshots/ (untracked, ephemeral). Each capture
// also asserts the redesigned contract so the file doubles as a visual
// regression guard.
// =============================================================================

import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/worker_provider.dart';
import 'package:azaman/screens/settings_screen.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/widgets/settings_drawer.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

User _demoUser() => User(
  id: 'u1',
  username: 'kofi',
  email: 'kofi@example.com',
  token: 't',
  role: 'USER',
  azamanId: 'AZM-8273941',
  kycStatus: KycStatus.verified,
);

/// Idle stub so the drawer's business-prefetch never starts network work.
class _IdleBusinessNotifier extends MyBusinessNotifier {
  _IdleBusinessNotifier() : super(BusinessService());

  @override
  Future<void> load() async {}
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ThemeProvider> seedTheme(AzamanTheme theme) async {
    // Same persisted index the real app boots from:
    // 0 = light, 1 = dark (see ThemeProvider._loadSavedTheme).
    SharedPreferences.setMockInitialValues({
      'azaman_theme': theme == AzamanTheme.dark ? 1 : 0,
      'biometric_lock_enabled': true,
    });
    final p = ThemeProvider();
    int guard = 0;
    while (!p.isLoaded && guard++ < 100) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(p.isLoaded, isTrue);
    return p;
  }

  for (final theme in AzamanTheme.values) {
    final mode = theme == AzamanTheme.dark ? 'dark' : 'light';

    testWidgets('drawer preview — $mode', (tester) async {
      tester.view.physicalSize = _surfaceSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tp = (await tester.runAsync(() => seedTheme(theme)))!;
      await tester.binding.setSurfaceSize(_surfaceSize);
      await tester.runAsync(_loadFonts);

      final container = ProviderContainer(
        overrides: [
          themeProvider.overrideWith((ref) => tp),
          currentUserProvider.overrideWith((ref) => Stream.value(_demoUser())),
          myEmployeeProvider.overrideWith((ref) => Future.value(null)),
          myBusinessProvider.overrideWith((ref) => _IdleBusinessNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final scaffoldKey = GlobalKey<ScaffoldState>();
      // Scene behind the glass: a plausible home backdrop so the frosted
      // drawer has real scenery to blur in the preview.
      final colors = ThemeProvider.getColors(theme);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeProvider.getThemeData(theme),
            home: RepaintBoundary(
              key: _rootKey,
              child: Scaffold(
                key: scaffoldKey,
                backgroundColor: colors.background,
                endDrawer: const SettingsDrawer(),
                body: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      scaffoldKey.currentState!.openEndDrawer();
      await tester.pump();
      // Entrance staggers (groups) + the async biometric chip settle.
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 1500));

      // The redesigned contract is on screen before the capture ships.
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Withdraw'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Biometrics on'), findsOneWidget);
      expect(find.text('All settings'), findsOneWidget);

      await _capture(tester, '${mode}_drawer');

      // STAGE 2 evidence: the threshold-triggered COLLAPSED hero. The
      // slimmed-down drawer fits the 900px preview without scrolling, so
      // the collapsed bar is exercised on a shorter, real-phone viewport.
      await tester.binding.setSurfaceSize(const Size(400, 650));
      await tester.pump();
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(const ValueKey('profile_hero_qr_icon')),
        findsOneWidget,
        reason: 'the collapsed capture must show the compact bar',
      );
      await _capture(tester, '${mode}_drawer_collapsed');
    });

    testWidgets('settings page preview — $mode', (tester) async {
      tester.view.physicalSize = _surfaceSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tp = (await tester.runAsync(() => seedTheme(theme)))!;
      await tester.binding.setSurfaceSize(_surfaceSize);
      await tester.runAsync(_loadFonts);

      final container = ProviderContainer(
        overrides: [
          themeProvider.overrideWith((ref) => tp),
          currentUserProvider.overrideWith((ref) => Stream.value(_demoUser())),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeProvider.getThemeData(theme),
            home: const Scaffold(
              backgroundColor: Colors.transparent,
              body: RepaintBoundary(key: _rootKey, child: SettingsScreen()),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 1500));

      // Identity moment + new IA before the capture ships. The Security
      // group sits below the fold at this viewport — its real-state chip
      // is pinned by the IA suite; here we assert the visible contract.
      expect(find.text('@kofi'), findsOneWidget);
      expect(find.text('AZM-8273941'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Accounts'), findsOneWidget);

      await _capture(tester, '${mode}_settings');
    });
  }
}
