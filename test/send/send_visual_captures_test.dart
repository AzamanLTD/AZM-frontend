// =============================================================================
// AZAMAN — UNIFIED SEND: VISUAL CAPTURES (320 / 360 / 390 dp × LIGHT / DARK)
//
// Deliberate, reviewable golden ADDITIONS for the Send composer journey.
// Three phone widths × three stages (compose, review, success) × two
// brightnesses = 18 rasters (PR #165 review finding 5).
//
// Two hard rules learned from the old 9-raster set (see
// test/goldens/README.md):
//   1. REAL FONTS — every face is loaded through FontLoader before the
//      first pump, otherwise flutter_test rasterises Ahem boxes and the
//      PNGs lie about the product.
//   2. The money action is a SLIDE (PR #165 finding 1) — the success
//      stage is driven through the intentional SlideToConfirm drag,
//      not a tap on a CTA that no longer exists.
//
// Generated with `flutter test --update-goldens`; any later regeneration
// must be a reviewable diff, never a green-maker.
// =============================================================================

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/send_money_screen.dart';
import 'package:azaman/services/recipient_discovery_service.dart';
import 'package:azaman/widgets/slide_to_confirm.dart';

const _storageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

class _FixedAuth extends AuthProvider {
  _FixedAuth(this.sessionUser);
  final User sessionUser;

  @override
  User? get user => sessionUser;

  @override
  Future<void> fetchUserDetails() async {}
}

class _FakeFriends extends FriendProvider {
  _FakeFriends(super.ref) {
    friends = [];
    isLoading = false;
  }

  @override
  Future<void> refreshAll() async {}
}

User _user() => User(
      id: '7',
      username: 'me',
      email: 'me@example.com',
      token: 'tok',
      role: 'USER',
      azamanId: 'AZM-999999999',
      availableBalance: 50.0,
    );

const _sizes = {
  '320': Size(320, 692),
  '360': Size(360, 800),
  '390': Size(390, 844),
};

SendMoneyScreen _screen() => SendMoneyScreen.toFriend(
      recipient: SendRecipient(
        username: 'ama',
        displayName: 'Ama Mensah',
        userId: 101,
        friendshipId: 'fs-1',
        source: SendRecipientSource.friend,
      ),
      sendOverride: (friendshipId, amount, reference, token) async =>
          {'success': true},
    );

// ── Real fonts (FontLoader pattern; see test/goldens/README.md) ─────────────

bool _fontsLoaded = false;

Future<void> _loadFace(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(
      ByteData.view(Uint8List.fromList(bytes).buffer),
    ));
  await loader.load();
}

/// Loads the app's real bundled faces exactly once per test process: the
/// display/UI family (ComicNeue 400/700) and Inter. Without this the
/// engine rasterises Ahem and the captures misrepresent the product.
Future<void> _loadAppFonts() async {
  if (_fontsLoaded) return;
  await _loadFace('Inter', 'assets/fonts/Inter-Variable.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Regular.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Bold.ttf');
  _fontsLoaded = true;
}

// ── Stage drives (mirrors the green composer UX suite) ─────────────────────

Future<void> _driveKeypadToReview(WidgetTester tester) async {
  for (final key in const ['5', '.', '0', '0']) {
    await tester.tap(find.text(key).first);
    await tester.pump();
  }
  await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
  await tester.pumpAndSettle();
}

/// Drives the money-action slide through its full intentional gesture —
/// thumb dragged far past the 90% threshold. The slide is the ONLY entry
/// into the commit path (PR #165 finding 1); no CTA exists to tap.
Future<void> _slideToConfirm(WidgetTester tester) async {
  final slide = find.byType(SlideToConfirm);
  expect(slide, findsOneWidget,
      reason: 'the money action is a slide-to-confirm surface');
  final topLeft = tester.getTopLeft(slide);
  final gesture = await tester.startGesture(topLeft + const Offset(28, 30));
  await gesture.moveBy(const Offset(1200, 0));
  await gesture.up();
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  required bool dark,
}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
    if (call.method == 'read') return 'mock-token';
    return null;
  });
  // azaman_theme: 0 = light, 1 = dark (index stability contract,
  // theme_provider.dart). No biometric_lock_enabled pref → the gate
  // stays off, so the slide alone commits.
  SharedPreferences.setMockInitialValues({
    'azaman_theme': dark ? 1 : 0,
  });
  final tp = ThemeProvider();
  tester.view
    ..physicalSize = size * 3.0
    ..devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  // Real font bytes are disk I/O — the fake-async zone never completes it.
  await tester.runAsync(_loadAppFonts);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FixedAuth(_user())),
        friendProvider.overrideWith((ref) => _FakeFriends(ref)),
        themeProvider.overrideWith((ref) => tp),
      ],
      child: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider.getThemeData(
            dark ? AzamanTheme.dark : AzamanTheme.light,
          ),
          home: RepaintBoundary(child: _screen()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(
  WidgetTester tester, {
  required String width,
  required String stage,
  required bool dark,
}) async {
  final size = _sizes[width]!;
  await _pump(tester, size, dark: dark);

  if (stage != 'compose') {
    await _driveKeypadToReview(tester);
  }

  if (stage == 'success') {
    await tester.enterText(
        find.byKey(const ValueKey('send-reference-field')), 'Jollof money');
    await tester.pump();
    await _slideToConfirm(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-success-icon')), findsOneWidget,
        reason: 'the capture must show the committed success panel');
  }

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile(
        '../goldens/send/${width}dp_${dark ? 'dark' : 'light'}_$stage.png'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final dark in const [false, true]) {
    for (final width in const ['320', '360', '390']) {
      for (final stage in const ['compose', 'review', 'success']) {
        testWidgets(
            'capture $width dp ${dark ? 'dark' : 'light'} — $stage',
            (tester) async {
          await _capture(tester, width: width, stage: stage, dark: dark);
        });
      }
    }
  }
}
