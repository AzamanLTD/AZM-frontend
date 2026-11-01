// =============================================================================
// AZAMAN — UNIFIED SEND: VISUAL CAPTURES (320 / 360 / 390 dp × LIGHT / DARK)
//
// Deliberate, reviewable goldens for the Send composer journey, in BOTH
// entry modes: GHS-entry (default) and a genuinely wheel-rolled USDC
// entry (the harness drives the LOCAL Send wheel — never the global
// Display Currency preference). 3 widths × 3 stages × 2 brightnesses ×
// 2 entry modes = 36 rasters, plus 2 deliberate-USDC-pref rasters
// (PR #165 review §6).
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

const _storageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

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
  // The seam exists so captures can pin ONE rate and exercise the
  // live GHS↔USDC conversion: 5.00 GHS → 0.33 USDC on the wire.
  fxRateOverride: 15.38,
  recipient: SendRecipient(
    username: 'ama',
    displayName: 'Ama Mensah',
    userId: 101,
    friendshipId: 'fs-1',
    source: SendRecipientSource.friend,
  ),
  sendOverride: (friendshipId, amount, reference, token) async => {
    'success': true,
  },
);

// ── Real fonts (FontLoader pattern; see test/goldens/README.md) ─────────────

bool _fontsLoaded = false;

Future<void> _loadFace(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
  await loader.load();
}

/// Loads the app's real bundled faces exactly once per test process: the
/// display/UI family (ComicNeue 400/700) and Inter. Without this the
/// engine rasterises Ahem and the captures misrepresent the product.
///
/// §6 font truth: ComicNeue has NO cedi glyph (₵, U+20B5), and the test
/// environment has no OS font fallback — so 'GH₵' rasterised as 'GH□'
/// and Material icons as empty squares. Two committed faces fix it:
///   • 'MaterialIcons' — the REAL production icon font (from the
///     Flutter SDK artifacts, see MaterialIcons_LICENSE.txt), so icons
///     render exactly as on-device;
///   • 'DejaVuSans' — a glyph-complete fallback wired into the harness
///     theme via fontFamilyFallback, so ₵ renders while all metrics
///     still come from the app's real faces (license alongside).
/// Placeholder glyphs are never accepted as product evidence.
Future<void> _loadAppFonts() async {
  if (_fontsLoaded) return;
  await _loadFace('Inter', 'assets/fonts/Inter-Variable.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Regular.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Bold.ttf');
  await _loadFace(
    'MaterialIcons',
    'test/goldens/fonts/MaterialIcons-Regular.otf',
  );
  await _loadFace('DejaVuSans', 'test/goldens/fonts/DejaVuSans.ttf');
  _fontsLoaded = true;
}

// ── Stage drives (mirrors the green composer UX suite) ─────────────────────

/// §6: rolls the Send LOCAL entry wheel to USDC through the real picker
/// interaction — the same gesture path a user takes (tap wheel → pick).
/// This is the transaction-local denomination, deliberately NOT the
/// global Display Currency preference.
Future<void> _rollWheelToUsdc(WidgetTester tester) async {
  final wheel = find.byKey(const ValueKey('send-amount-currency'));
  expect(
    wheel,
    findsOneWidget,
    reason: 'the Send amount wheel must be present to roll',
  );
  await tester.tap(wheel, warnIfMissed: false);
  await tester.pumpAndSettle();
  final usdcItem = find.text('USDC — USD Coin');
  expect(
    usdcItem,
    findsOneWidget,
    reason: 'the picker must offer the USDC entry option',
  );
  await tester.tap(usdcItem);
  await tester.pumpAndSettle();
  // The picker has closed and the wheel rolled; the LOCAL entry unit is
  // now USDC. The review stage of each USDC-entry capture pins the
  // postcondition (the GHS-equivalent row exists only under USDC entry).
}

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
  expect(
    slide,
    findsOneWidget,
    reason: 'the money action is a slide-to-confirm surface',
  );
  final topLeft = tester.getTopLeft(slide);
  final gesture = await tester.startGesture(topLeft + const Offset(28, 30));
  // Workstream B: the review stage lives inside
  // PullDownDismissibleSurface whose vertical recognizer joins the
  // arena — drag incrementally (real thumb physics) so the horizontal
  // slide recognizer resolves instead of hitting the one-shot synthetic
  // move's arena tie-break.
  for (var i = 0; i < 24; i++) {
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
}

/// The harness theme: the REAL app theme, with a glyph-complete
/// fallback family so the cedi symbol renders exactly as on-device (where
/// the OS supplies the missing glyph for ComicNeue). Metrics stay the
/// app's own; only missing glyphs fall through.
ThemeData _harnessTheme(bool dark) {
  final base = ThemeProvider.getThemeData(
    dark ? AzamanTheme.dark : AzamanTheme.light,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: const ['DejaVuSans']),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  required bool dark,
  bool usdcPref = false,
}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
        if (call.method == 'read') return 'mock-token';
        return null;
      });
  // azaman_theme: 0 = light, 1 = dark (index stability contract,
  // theme_provider.dart). No biometric_lock_enabled pref → the gate
  // stays off, so the slide alone commits.
  // usdcPref seeds a DELIBERATE saved USDC display preference (the only
  // state in which USDC-primary visuals are legitimate — work order §4D).
  SharedPreferences.setMockInitialValues({
    'azaman_theme': dark ? 1 : 0,
    if (usdcPref) 'display_currency': 'usdc',
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
          theme: _harnessTheme(dark),
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
  bool usdcEntry = false,
  bool usdcPref = false,
}) async {
  final size = _sizes[width]!;
  await _pump(tester, size, dark: dark, usdcPref: usdcPref);

  // §6: the LOCAL entry wheel is rolled to USDC for usdcEntry captures —
  // a genuine transaction-local denomination change, never the global
  // Display Currency preference.
  if (usdcEntry) {
    await _rollWheelToUsdc(tester);
  }

  if (stage != 'compose') {
    await _driveKeypadToReview(tester);
  }

  // Postcondition for USDC entry: the review card's GHS-equivalent row
  // exists ONLY under direct USDC entry (GHS entry has the wire row +
  // derivation-rate row instead). Never trust the wheel tap alone.
  if (usdcEntry && stage == 'review') {
    expect(
      find.byKey(const ValueKey('send-review-ghs-equivalent')),
      findsOneWidget,
      reason: 'USDC-entry review must show the paired GHS equivalent',
    );
  }

  if (stage == 'success') {
    await tester.enterText(
      find.byKey(const ValueKey('send-reference-field')),
      'Jollof money',
    );
    await tester.pump();
    await _slideToConfirm(tester);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('send-success-icon')),
      findsOneWidget,
      reason: 'the capture must show the committed success panel',
    );
  }

  final suffix = usdcEntry ? '_usdcentry' : (usdcPref ? '_usdcpref' : '');
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile(
      '../goldens/send/${width}dp_${dark ? 'dark' : 'light'}_$stage$suffix.png',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final dark in const [false, true]) {
    for (final width in const ['320', '360', '390']) {
      for (final stage in const ['compose', 'review', 'success']) {
        testWidgets('capture $width dp ${dark ? 'dark' : 'light'} — $stage', (
          tester,
        ) async {
          await _capture(tester, width: width, stage: stage, dark: dark);
        });
      }
    }
  }

  // §6: genuine USDC-ENTRY captures — the LOCAL Send wheel rolled to
  // USDC on every width and theme, across the full journey.
  for (final dark in const [false, true]) {
    for (final width in const ['320', '360', '390']) {
      for (final stage in const ['compose', 'review', 'success']) {
        testWidgets(
          'capture $width dp ${dark ? 'dark' : 'light'} — $stage (USDC entry)',
          (tester) async {
            await _capture(
              tester,
              width: width,
              stage: stage,
              dark: dark,
              usdcEntry: true,
            );
          },
        );
      }
    }
  }

  // Deliberate-USDC PREFERENCE captures (clearly named): the GLOBAL
  // display preference is USDC while the entry stays GHS. These pin that
  // USDC-primary appearance of the balance chip is legitimate ONLY under
  // an explicitly saved USDC preference (work order §4D).
  for (final stage in const ['compose', 'review']) {
    testWidgets('capture 360 dp light — $stage (deliberate USDC pref)', (
      tester,
    ) async {
      await _capture(
        tester,
        width: '360',
        stage: stage,
        dark: false,
        usdcPref: true,
      );
    });
  }
}
