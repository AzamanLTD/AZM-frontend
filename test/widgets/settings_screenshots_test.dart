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
import 'package:azaman/widgets/settings/az_reveal_drawer.dart';

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
  // The real production icon font (committed under test/goldens/fonts), so
  // icons render as on-device instead of placeholder boxes.
  final icons = await File('test/goldens/fonts/MaterialIcons-Regular.otf').readAsBytes();
  await (FontLoader('MaterialIcons')
        ..addFont(Future<ByteData>.value(ByteData.view(Uint8List.fromList(icons).buffer))))
      .load();
  final inter = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final interLoader = FontLoader('Inter')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(inter).buffer)),
    );
  await interLoader.load();
  final regular = await File(
    'assets/fonts/ComicNeue-Regular.ttf',
  ).readAsBytes();
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
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_rootKey),
    );
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

      // The reveal: a plausible app page slides aside to show the drawer
      // that lives underneath it (AzRevealDrawer, as in the app shell).
      final colors = ThemeProvider.getColors(theme);
      final drawer = AzRevealDrawerController();
      addTearDown(drawer.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeProvider.getThemeData(theme),
            home: RepaintBoundary(
              key: _rootKey,
              child: ColoredBox(
                color: colors.background,
                child: AzRevealDrawer(
                  controller: drawer,
                  drawer: const SettingsDrawer(),
                  child: Scaffold(
                    backgroundColor: colors.surface,
                    body: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Home', style: TextStyle(color: colors.textPrimary, fontSize: 28, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 20),
                            for (var i = 0; i < 4; i++)
                              Container(
                                height: 96,
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: colors.card,
                                  borderRadius: BorderRadius.circular(22),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      drawer.open();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      // The async biometric chip settles.
      await tester.pump(const Duration(milliseconds: 600));

      // The redesigned contract is on screen before the capture ships.
      expect(drawer.isOpen, isTrue);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Biometrics on'), findsOneWidget);
      expect(find.text('All settings'), findsOneWidget);

      await _capture(tester, '${mode}_drawer');

      // Tapping the visible strip of the slid-away page (its left edge;
      // its centre is off-screen) closes the drawer.
      expect(find.byKey(const ValueKey('reveal-drawer-scrim')), findsOneWidget);
      await tester.tapAt(const Offset(16, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(drawer.isOpen, isFalse);
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
