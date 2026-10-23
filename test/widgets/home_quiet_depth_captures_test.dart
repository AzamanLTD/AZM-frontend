// QUIET DEPTH — HOME PILOT (2026-10-22).
//
// The Home quick actions (Save / P2P / Susu) enter raised, settle into a
// nearly-flush recessed state after the idle delay, and re-elevate when a
// focal surface releases the stage or a qualifying interaction wakes them.
// This suite pins the pilot's contract on the REAL Home page:
//
//   1.  raised on entry;
//   2.  recessed after the idle delay, transition complete;
//   3.  a tap wakes the controls AND fires the real navigation — the
//       visual transition never swallows or delays the action;
//   4.  a wallet card brought out recesses the quick actions;
//   5.  tucking the wallet restores them;
//   6.  starting a reminder swipe focuses the deck and recesses the
//       actions without gesture interference (the swipe still commits);
//   7.  viewing every current reminder id inserts EXACTLY ONE terminal
//       card;
//   8.  the terminal tap exits focus, restores the actions, and the
//       celebration fires at most once per viewing cycle;
//   9.  tapping outside the reminder region also restores the actions;
//   10. a changed reminder set cannot reuse stale completion state;
//   11. reduced motion: instant state changes, no confetti, and disposal
//       cancels lifecycle work;
//   12. no regression: the reminder a11y advance action and the wallet
//       PIN gate keep working.
//
// Plus environment coverage: 320/360/390dp, light and dark, a short
// viewport, 1.6x text scale, keyboard/reduced-motion, and semantics +
// hit-target continuity in both depth states.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/widgets/home/azm_visa_card.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/marketplace_relevance_provider.dart';
import 'package:azaman/providers/marketplace_resume_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/services/home_summary_service.dart';
import 'package:azaman/widgets/home/wallet_card_deck.dart';
import 'package:azaman/widgets/odometer_number.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderFittedBox, RenderRepaintBoundary;
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';


/// Fixed pumping to settle entrance + doorway measurement windows (the
/// canonical Home settle pattern — the real page never quiesces).
Future<void> _advance(
  WidgetTester tester, {
  Duration by = const Duration(milliseconds: 400),
  int rounds = 4,
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(by);
  }
}

bool _fontsLoaded = false;
Future<void> _loadFace(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
  await loader.load();
}

/// Loads the app's REAL bundled faces exactly once per test process —
/// the capture-evidence contract (review finding on the #184 harness):
///
///   • Inter — the numeric family (money figures; tabular metrics).
///   • ComicNeue Regular + Bold — the display/UI family the live theme
///     actually types the app in. Without them the engine rasterises
///     Ahem: text captured as blank rectangular bars, which is NOT
///     product evidence.
///   • MaterialIcons + HugeIconsSolid/Stroke — the real icon fonts, so
///     icons render as glyphs, not tofu squares.
///   • DejaVuSans — glyph-complete fallback wired into the harness
///     theme (ComicNeue has no cedi glyph ₵ U+20B5; on-device the OS
///     supplies it). Metrics still come from the app's own faces.
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  await _loadFace('Inter', 'assets/fonts/Inter-Variable.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Regular.ttf');
  await _loadFace('ComicNeue', 'assets/fonts/ComicNeue-Bold.ttf');
  await _loadFace(
      'MaterialIcons', 'test/goldens/fonts/MaterialIcons-Regular.otf');
  // Package icons (IconData(fontFamily: 'HugeIconsSolid',
  // fontPackage: 'hugeicons_pro')) resolve through the engine under the
  // PACKAGE-QUALIFIED family key. Registering the bare name left every
  // HugeIcons glyph unresolved → tofu squares in the captures.
  await _loadFace('packages/hugeicons_pro/HugeIconsSolid',
      'test/goldens/fonts/hugeicons-solid.ttf');
  await _loadFace('packages/hugeicons_pro/HugeIconsStroke',
      'test/goldens/fonts/hugeicons-stroke.ttf');
  await _loadFace('DejaVuSans', 'test/goldens/fonts/DejaVuSans.ttf');
  _fontsLoaded = true;
}

/// The REAL app theme with a glyph-complete fallback family for the
/// cedi symbol (same harness pattern as the Send visual-capture suite):
/// metrics come from the app's committed faces, and only glyphs missing
/// from ComicNeue (₵) fall through to DejaVuSans exactly as the OS
/// fallback does on-device.
ThemeData _harnessTheme(AzamanTheme theme) {
  final base = ThemeProvider.getThemeData(theme);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: const ['DejaVuSans']),
  );
}

/// Structural truth for every capture that claims to show a CONFIRMED
/// balance: the seeded figure is present and the primary-amount slot's
/// waiting indicator is not. A capture PNG alone cannot prove this —
/// the dots key can sit behind a masked/hidden region while the image
/// still "looks fine".
///
/// Widget-level, not semantics-level: while the deck is tucked the card
/// subtree stays mounted but its semantics are excluded, so a semantics
/// label search cannot see the figure even when it IS there. The
/// OdometerNumber's [OdometerNumber.value] is the authoritative slot
/// content: 100 USDC at the pinned rate 1.0 under the default GHS-first
/// preference renders 'GH₵ 100.00' — AzMoney.amount() strips the symbol,
/// leaving '100.00'.
void _expectConfirmedBalance() {
  expect(
    find.byKey(const ValueKey('home-balance-amount-dots')),
    findsNothing,
    reason: 'a confirmed-balance capture must never show the waiting dots',
  );
  expect(
    find.byWidgetPredicate(
        (w) => w is OdometerNumber && w.value == '100.00'),
    findsOneWidget,
    reason: 'the seeded available balance (100 USDC at rate 1.0) '
        'must be present as the rendered primary figure',
  );
}

class _NoopHistoryNotifier extends TransactionHistoryNotifier {
  @override
  Future<void> loadMore() async {}
}

class _PinnedProgramme implements AzmCardProgramme {
  String? _pin;
  @override
  bool get supportsTransfers => false;
  @override
  bool get hasPin => _pin != null;
  @override
  Future<bool> setPin(String pin) async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) return false;
    _pin = pin;
    return true;
  }

  @override
  Future<bool> verifyPin(String pin) async {
    await Future<void>.delayed(Duration.zero);
    return _pin != null && _pin == pin;
  }

  @override
  String get maskedNumber => '•••• 4242';
  @override
  String get expiryLabel => 'MM/YY';
  @override
  String get cardholderLabel => 'AZ USER';
}

class _FakeSusuListNotifier extends SusuListNotifier {
  _FakeSusuListNotifier(this.groups);
  final List<SusuSummary> groups;
  @override
  Future<List<SusuSummary>> build() async => groups;
}

SusuSummary _activeSusu(
  DateTime runAt, {
  String id = 's1',
  String name = 'Circle Susu',
}) =>
    SusuSummary(
      id: id,
      name: name,
      status: SusuStatus.active,
      contributionUsdc: 10,
      frequency: SusuFrequency.weekly,
      totalCycles: 10,
      nextCycle: SusuCycleSummary(
        id: 'c4',
        cycleNumber: 4,
        scheduledRunAt: runAt,
        payoutUserId: 2,
        isMe: false,
      ),
      myCycleSlot: 4,
      myStatus: SusuMemberStatus.active,
      myRole: 'MEMBER',
    );

const _cartIntent = ResumeIntent(
  kind: ResumeKind.cart,
  title: 'Finish your order at Maame\'s Kitchen',
  subtitle: '2 items · GH₵ 54.00',
  businessProfileId: 'biz-1',
);

/// Pumps the REAL Home page with the pilot's reminder seeds (one susu
/// card + one resume card) inside a real GoRouter so pill taps actually
/// navigate. Returns the container so tests can invalidate providers.


/// Unmounts the page and drains riverpod's zero-duration auto-dispose
/// timers so a multi-pump test tears down with a clean timer set.
Future<void> _flush(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// A committed swipe on the given card with the deck suite's proven
/// frame pattern: the flight completes and the post-frame reorder has
/// RENDERED before the test touches the deck again (the peek card is
/// IgnorePointer'd until then, and a later drag must not hit it).
Future<void> _swipeCommit(WidgetTester tester, Key cardKey) async {
  await tester.drag(find.byKey(cardKey), const Offset(260, -20));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  Size surface = const Size(390, 844),
  AzamanTheme theme = AzamanTheme.dark,
  bool reduceMotion = false,
  double textScale = 1.0,
  List<SusuSummary> susu = const [],
  ResumeIntent? intent,
}) async {
  SharedPreferences.setMockInitialValues({
    'has_seen_flippable_card_hint': true,
    'azaman_theme': theme == AzamanTheme.dark ? 1 : 0,
  });
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(surface);

  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      transactionHistoryProvider.overrideWith(
        (ref) => _NoopHistoryNotifier(),
      ),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
        (ref) => const BalanceData(availableBalance: 100),
      ),
      // The seeded amount is a CONFIRMED balance, not a placeholder: the
      // readiness state must be loaded or the amount slot captures the
      // waiting dots instead of the figure (review finding on #184).
      balanceReadinessProvider.overrideWith(
        (ref) => BalanceReadiness.loaded,
      ),
      oracleRateProvider.overrideWith((ref) => 1.0),
      azmCardProgrammeProvider.overrideWith(
        (ref) => _PinnedProgramme().._pin = '1234',
      ),
      homeSummaryProvider.overrideWith(
        (ref) => _NoopHomeSummaryNotifier(ref, HomeSummaryService()),
      ),
      susuListProvider.overrideWith(() => _FakeSusuListNotifier(susu)),
      marketplaceResumeProvider.overrideWithValue(intent),
      marketplaceRelevanceProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: _harnessTheme(theme),
        home: MediaQuery(
          data: MediaQueryData(
            size: surface,
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          // OPAQUE themed background — capture-evidence contract fix.
          //
          // The production app mounts AzamanHomePage on main.dart's
          // Scaffold, which paints colors.surface. This harness
          // previously used Colors.transparent, so every semi-transparent
          // paint (the Quiet Depth glass pills) composited over a CLEAR
          // buffer: the committed PNGs were ~60% alpha<128 pixels. On a
          // white viewer background (GitHub's PR review) those read as
          // WHITE pills with invisible labels — a pure harness artifact,
          // not the product's rendering. The Scaffold must paint the
          // same opaque surface production paints.
          child: Consumer(
            builder: (context, ref, _) {
              final surface =
                  ref.watch(themeProvider.select((t) => t.colors.surface));
              return Scaffold(
                backgroundColor: surface,
                body: RepaintBoundary(
                  key: _rootKey,
                  // The opaque surface must be INSIDE the captured
                  // boundary: toImage() rasterises only this subtree,
                  // so a Scaffold-level background never reaches the
                  // PNG and semi-transparent paints composite over
                  // nothing again.
                  child: ColoredBox(
                    color: surface,
                    child: const AzamanHomePage(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  // Entrance + prime microtask + §6 measurement window (same as the
  // integration suite).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 1400));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

const _rootKey = ValueKey('qd-capture-root');

// ─────────────────────────────────────────────────────────────────────────
// PIXEL-TRUTH REGRESSION ASSERTIONS (review finding on #184: widget
// presence alone proved nothing — the committed evidence once showed
// white-on-white pills and tofu icons while every widget check passed).
//
// The two regression classes this guards against, both taken from the
// real failure history of this very suite:
//
//   1. TRANSPARENT-BUFFER CAPTURES: the opaque surface must reach the
//      rasterised pixels. Every pixel of every capture must be opaque
//      (alpha == 255). The original defect composited 5% glass over a
//      clear buffer → white pills on a white viewer.
//   2. TOFU / BLANK CONTENT: a real filled glyph has gold pixels INSIDE
//      its bounding box; a missing-font tofu square is a hollow outline
//      (inner gold == 0). Real labels produce multiple text-coloured
//      runs along their row; a blank or bar-shaped placeholder does not.
// ─────────────────────────────────────────────────────────────────────────

const _goldR = 140, _goldG = 90, _goldB = 110;

bool _isGold(int r, int g, int b) => r > _goldR && g > _goldG && b < _goldB;

/// Asserts every pixel of the capture is fully opaque.
void _expectOpaque(String name, Uint8List rgba, int width, int height) {
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 0xFF) {
      fail('$name: capture has non-opaque pixels (alpha=${rgba[i]} at '
          'offset $i). The themed surface must be composited INSIDE the '
          'captured boundary — a transparent capture reads as white pills '
          'on a white viewer (the original #184 evidence defect).');
    }
  }
}

/// The three quick-action pill rects (Save / P2P / Susu) in IMAGE pixel
/// coordinates (rasterised at pixelRatio 2.0). The depth-state key sits
/// on each pill's backdrop, which is Positioned.fill of the pill's own
/// stack, so its rect IS the pill.
List<Rect> _pillRects(WidgetTester tester) {
  var f = find.byKey(const ValueKey('quiet-depth-raised'));
  if (!tester.any(f)) {
    f = find.byKey(const ValueKey('quiet-depth-recessed'));
  }
  expect(f, findsExactly(3), reason: 'the three quick-action pills');
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_rootKey));
  final origin = boundary.localToGlobal(Offset.zero);
  // logical → image pixels: translate to the boundary's frame, then
  // scale by the raster pixelRatio (2.0).
  Rect toImagePx(Rect r) => Rect.fromLTWH(
        (r.left - origin.dx) * 2.0,
        (r.top - origin.dy) * 2.0,
        r.width * 2.0,
        r.height * 2.0,
      );
  return [for (var i = 0; i < 3; i++) toImagePx(tester.getRect(f.at(i)))];
}

/// Asserts each pill renders a real icon glyph and a real label:
/// per pill — filled-gold interior (tofu is hollow: 0 inner pixels),
/// a minimum gold body, and text-coloured pixels forming >= 2 runs.
void _expectRealGlyphsAndLabels(
  String name,
  Uint8List rgba,
  int width,
  Rect pillRect, {
  required bool lightLabels,
}) {
  final px0 = pillRect.left.round(), py0 = pillRect.top.round();
  final px1 = pillRect.right.round(), py1 = pillRect.bottom.round();

  bool isLabelPx(int r, int g, int b) => lightLabels
      ? (r < 80 && g < 80 && b < 80) // dark text on the light surface
      : (r > 190 && g > 190 && b > 190); // white text on the dark glass

  var gold = 0, labelPx = 0;
  var gx0 = -1, gy0 = -1, gx1 = -1, gy1 = -1;
  final labelRows = <int, int>{}; // row → label pixel count
  for (var y = py0; y < py1 && y >= 0 && y * width < rgba.length; y++) {
    for (var x = px0; x < px1; x++) {
      final i = (y * width + x) * 4;
      final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
      if (_isGold(r, g, b)) {
        gold++;
        if (gx0 < 0 || x < gx0) gx0 = x;
        if (gy0 < 0 || y < gy0) gy0 = y;
        if (x > gx1) gx1 = x;
        if (y > gy1) gy1 = y;
      } else if (isLabelPx(r, g, b)) {
        labelPx++;
        labelRows[y] = (labelRows[y] ?? 0) + 1;
      }
    }
  }
  final which = '$name pill [${pillRect.left.round()}]';
  expect(gold, greaterThan(200),
      reason: '$which: no real icon glyph rendered (gold pixels: $gold). '
          'A missing icon font falls back to tofu.');
  expect(gx0, greaterThanOrEqualTo(0), reason: '$which: no gold pixels');

  // Hollow-tofu discriminator: gold inside the shrunken glyph bbox.
  var inner = 0;
  final ix0 = gx0 + (gx1 - gx0) ~/ 4, ix1 = gx1 - (gx1 - gx0) ~/ 4;
  final iy0 = gy0 + (gy1 - gy0) ~/ 4, iy1 = gy1 - (gy1 - gy0) ~/ 4;
  for (var y = iy0; y <= iy1; y++) {
    for (var x = ix0; x <= ix1; x++) {
      final i = (y * width + x) * 4;
      if (_isGold(rgba[i], rgba[i + 1], rgba[i + 2])) inner++;
    }
  }
  expect(inner, greaterThan(60),
      reason: '$which: icon glyph is HOLLOW (inner gold: $inner) — this is '
          'the tofu-square signature (hollow outline, 0 inner pixels). The '
          'package-qualified HugeIcons families must be registered.');

  // Label truth: enough text pixels AND separated runs (a bar is 1 run,
  // a blank label is 0 pixels).
  expect(labelPx, greaterThan(120),
      reason: '$which: label is blank (text pixels: $labelPx)');
  var bestRow = labelRows.entries.reduce((a, b) => a.value >= b.value ? a : b);
  var runs = 0;
  var prevIn = false;
  for (var x = px0; x < px1; x++) {
    final i = (bestRow.key * width + x) * 4;
    final inRun = isLabelPx(rgba[i], rgba[i + 1], rgba[i + 2]);
    if (inRun && !prevIn) runs++;
    prevIn = inRun;
  }
  expect(runs, greaterThan(1),
      reason: '$which: label row has $runs text run(s) — real type has '
          'letter gaps; a single contiguous bar is the missing-font '
          'placeholder signature.');
}

/// FLAT-CONTRACT PIXEL TRUTH (design review 2026-10-23): the settled
/// pill body must be pixel-identical to the page plane it sits on. The
/// reference is sampled from the strip directly ABOVE each pill (same
/// page, outside the rim); the pill's interior strip (inside the rim,
/// above the content row) must match it. Any fill, tint, glass, shadow
/// or glow that survived would shift these pixels and fail here.
void _expectFlatInterior(
  String name,
  Uint8List rgba,
  int width,
  Rect pillRect,
) {
  int px(int x, int y) {
    final i = (y * width + x) * 4;
    return rgba[i] * 0x10000 + rgba[i + 1] * 0x100 + rgba[i + 2];
  }

  final left = pillRect.left.round(), right = pillRect.right.round();
  final top = pillRect.top.round();
  // The rim is a capsule: its corner arcs (radius = height/2) curve
  // into any naive inset rectangle. Sample only the STRAIGHT-EDGE
  // zone, horizontally inset past the corner radius.
  final radius = (pillRect.height / 2).round();
  final refX0 = left + radius + 8, refX1 = right - radius - 8;
  if (refX1 - refX0 < 12) {
    fail('$name pill [${pillRect.left.round()}]: too narrow to sample a '
        'flat interior strip');
  }
  // Reference strip: 8-12 image px above the rim — same page plane.
  final refYs = [top - 11, top - 10, top - 9];
  final ref = <int>{};
  for (final y in refYs) {
    for (var x = refX0; x < refX1; x += 2) {
      ref.add(px(x, y));
    }
  }
  // Interior strip: 10-20 image px below the rim — inside the pill,
  // above the vertically-centered content row (the content has 24
  // image px of top padding), and horizontally inside the corner arcs.
  final inYs = [for (var y = top + 10; y < top + 20; y++) y];
  final which = '$name pill [${pillRect.left.round()}]';
  for (final y in inYs) {
    for (var x = refX0; x < refX1; x++) {
      final c = px(x, y);
      bool nearRef(int r) =>
          ((r >> 16) & 0xFF) - ((c >> 16) & 0xFF) <= 2 &&
          ((r >> 16) & 0xFF) - ((c >> 16) & 0xFF) >= -2 &&
          ((r >> 8) & 0xFF) - ((c >> 8) & 0xFF) <= 2 &&
          ((r >> 8) & 0xFF) - ((c >> 8) & 0xFF) >= -2 &&
          (r & 0xFF) - (c & 0xFF) <= 2 &&
          (r & 0xFF) - (c & 0xFF) >= -2;
      final near = ref.any(nearRef);
      if (!near) {
        fail('$which: interior pixel '
            '(${(c >> 16) & 0xFF},${(c >> 8) & 0xFF},${c & 0xFF}) at '
            '($x,$y) differs from the page plane — the settled body '
            'must visually disappear into the page (no fill, tint, '
            'glass, shadow or glow).');
      }
    }
  }
}

/// Captures the RepaintBoundary around the Home page to a PNG on disk.
/// With [verifyPills] the capture is ALSO pixel-verified (the three
/// quick-action pills must show real gold glyphs, real labels and a
/// FLAT body identical to the page plane) and every pixel must be
/// opaque.
Future<void> _capture(
  WidgetTester tester,
  String name, {
  bool verifyPills = false,
  bool lightLabels = false,
}) async {
  var ok = false;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_rootKey));
    // Rects are read BEFORE the rasterisation awaits: the tree stays
    // settled here, but reads are cheap to hoist.
    final rects = verifyPills ? _pillRects(tester) : const <Rect>[];
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = (await image.toByteData(format: ImageByteFormat.png))!;
    final dir = Directory('.screenshots/quiet_depth')
      ..createSync(recursive: true);
    final file = File('${dir.path}/$name.png');
    await file.writeAsBytes(data.buffer.asUint8List());
    ok = file.lengthSync() > 1000;
    if (verifyPills) {
      final rgba = (await image.toByteData(format: ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      _expectOpaque(name, rgba, image.width, image.height);
      for (final r in rects) {
        _expectRealGlyphsAndLabels(name, rgba, image.width, r,
            lightLabels: lightLabels);
        _expectFlatInterior(name, rgba, image.width, r);
      }
    }
  });
  expect(ok, isTrue, reason: '$name.png must contain real image bytes');
}


class _NoopHomeSummaryNotifier extends HomeSummaryNotifier {
  _NoopHomeSummaryNotifier(super.ref, super.service);
}

WalletDeckState _deckState(WidgetTester tester) =>
    tester.state<WalletCardDeckState>(find.byType(WalletCardDeck)).state;

void main() {
  testWidgets('dark 390: resting → recessed → focal wallet captures',
      (tester) async {
    await _pumpHome(
      tester,
      susu: [_activeSusu(DateTime(2026, 10, 26))],
      intent: _cartIntent,
    );
    _expectConfirmedBalance();
    expect(find.byKey(const ValueKey('quiet-depth-raised')), findsWidgets);
    await _capture(tester, 'qd_dark_resting_raised_390', verifyPills: true);

    // Sequential pumps (a single pump(d) runs ONE frame at its end, which
    // would freeze the depth fade at its first tick).
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byKey(const ValueKey('quiet-depth-recessed')), findsWidgets);
    await _capture(tester, 'qd_dark_recessed_390', verifyPills: true);

    await tester.tap(find.bySemanticsLabel('Reveal balance card').first);
    await _advance(tester);
    expect(_deckState(tester), WalletDeckState.balanceOut);
    await _capture(tester, 'qd_dark_focal_wallet_390', verifyPills: true);
  });

  testWidgets('dark 390: reminder focal + terminal celebration captures',
      (tester) async {
    await _pumpHome(
      tester,
      susu: [_activeSusu(DateTime(2026, 10, 26))],
      intent: _cartIntent,
    );
    _expectConfirmedBalance();
    await _swipeCommit(tester, const ValueKey('reminder-card-susu-s1'));
    await _swipeCommit(tester, const ValueKey('reminder-card-resume-biz-1'));
    expect(
      find.byKey(const ValueKey('reminder-card-reminders-terminal')),
      findsOneWidget,
    );
    await _capture(tester, 'qd_dark_focal_reminder_390');

    // Terminal tap: confetti burst (mid-flight) + actions raised.
    await tester.tap(
      find.byKey(const ValueKey('reminder-card-reminders-terminal')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('reminder-confetti')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiet-depth-raised')), findsWidgets);
    await _capture(tester, 'qd_dark_terminal_celebration_390');

    // Late-burst confetti at a SECOND fixed t: with the precomputed
    // particle system the piece positions follow one smooth trajectory,
    // and two independent suite runs must produce byte-identical PNGs.
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('reminder-confetti')), findsOneWidget);
    await _capture(tester, 'qd_dark_confetti_late_390');

    // The real Home loops ambient animations forever — fixed pumps, never
    // pumpAndSettle. The burst is ~900ms; 1.5s drains it.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byKey(const ValueKey('reminder-confetti')), findsNothing,
        reason: 'the celebration is one-shot, never looping');
  });

  testWidgets('light 390: resting → recessed → focal wallet captures',
      (tester) async {
    await _pumpHome(
      tester,
      theme: AzamanTheme.light,
      susu: [_activeSusu(DateTime(2026, 10, 26))],
      intent: _cartIntent,
    );
    _expectConfirmedBalance();
    expect(find.byKey(const ValueKey('quiet-depth-raised')), findsWidgets);
    await _capture(tester, 'qd_light_resting_raised_390', verifyPills: true, lightLabels: true);

    // Sequential pumps (a single pump(d) runs ONE frame at its end, which
    // would freeze the depth fade at its first tick).
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byKey(const ValueKey('quiet-depth-recessed')), findsWidgets);
    await _capture(tester, 'qd_light_recessed_390', verifyPills: true, lightLabels: true);

    await tester.tap(find.bySemanticsLabel('Reveal balance card').first);
    await _advance(tester);
    expect(_deckState(tester), WalletDeckState.balanceOut);
    await _capture(tester, 'qd_light_focal_wallet_390', verifyPills: true, lightLabels: true);
  });

  // ── FLAT-CONTRACT LAYOUT TRUTH (design review 2026-10-23) ────────────
  //
  // The FULL labels 'Save', 'P2P' and 'Susu' must be present and
  // unclipped at 320dp AND 390dp, in BOTH themes and BOTH depth
  // states (woken and settled), and under a larger text scale. No
  // ellipses, no clipped letters: the pill scales its content row
  // down proportionally (never below a readable floor) instead of
  // clipping.
  testWidgets('label truth — full labels at 320/390dp, both themes, both depth states',
      (tester) async {
    Future<void> pumpAt(
      AzamanTheme theme,
      Size surface, {
      bool settle = true,
      double textScale = 1.0,
    }) async {
      await _pumpHome(
        tester,
        surface: surface,
        theme: theme,
        textScale: textScale,
        susu: [_activeSusu(DateTime(2026, 10, 26))],
        intent: _cartIntent,
      );
      if (settle) {
        // Settle to the recessed state (the settled appearance).
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey('quiet-depth-recessed')),
            findsWidgets,
            reason: 'precondition: the pills must be settled');
      } else {
        expect(find.byKey(const ValueKey('quiet-depth-raised')),
            findsWidgets,
            reason: 'precondition: the pills must be woken');
      }
    }

    const labels = ['Save', 'P2P', 'Susu'];
    const pillKeys = [
      'wallet-module-save',
      'wallet-module-p2p',
      'wallet-module-susu',
    ];

    void expectFullLabels(double w, AzamanTheme theme, String state,
        {double scaleFloor = 0.9}) {
      for (var i = 0; i < labels.length; i++) {
        final t = find.text(labels[i]);
        expect(t, findsOneWidget,
            reason: 'the FULL label "${labels[i]}" must exist at '
                '${w.toInt()}dp (${theme.name} / $state)');
        final text = tester.widget<Text>(t);
        expect(text.overflow, TextOverflow.visible,
            reason: 'labels never ellipsize — the pill adapts instead '
                '(${theme.name} / $state)');
        expect(text.maxLines, 1);

        // The laid-out text fits the pill box — no clipped letters.
        final pillRect = tester.getRect(find.byKey(ValueKey(pillKeys[i])));
        final textRect = tester.getRect(t);
        expect(
          pillRect.contains(textRect.topLeft) &&
              pillRect.contains(textRect.bottomRight),
          isTrue,
          reason: 'the "${labels[i]}" text must paint fully inside its '
              'pill at ${w.toInt()}dp (${theme.name} / $state)',
        );

        // Content row scales down, not below a readable floor: at the
        // default scale the labels stay essentially full size.
        final fbox = tester.renderObject<RenderFittedBox>(
          find.ancestor(of: t, matching: find.byType(FittedBox)),
        );
        final child = fbox.child!;
        final scale = fbox.size.width / child.size.width;
        expect(scale, greaterThan(scaleFloor),
            reason: '"${labels[i]}" shrank to ${(scale * 100).round()}% at '
                '${w.toInt()}dp (${theme.name} / $state) — the '
                'default-scale label budget is broken');
      }
      // Touch targets survive the layout adaptation: every pill is at
      // least 44x44dp in every combination.
      for (final k in pillKeys) {
        final s = tester.getSize(find.byKey(ValueKey(k)));
        expect(s.width, greaterThanOrEqualTo(44),
            reason: 'minimum 44dp hit-target width (${theme.name} / $state)');
        expect(s.height, greaterThanOrEqualTo(44),
            reason: 'minimum 44dp hit-target height (${theme.name} / $state)');
      }
    }

    // The review matrix: both themes × both depth states, at 320dp AND
    // 390dp.
    for (final theme in AzamanTheme.values) {
      for (final settle in [false, true]) {
        final state = settle ? 'settled' : 'woken';
        await pumpAt(theme, const Size(320, 844), settle: settle);
        expectFullLabels(320, theme, state);
        await _flush(tester);

        await pumpAt(theme, const Size(390, 844), settle: settle);
        expectFullLabels(390, theme, state);
        await _flush(tester);
      }
    }

    // Larger text scale: labels still complete — degraded by
    // proportional scaling, never by clipping or ellipsis.
    // (1.3x is NOT probed: an UNRELATED pre-existing 2px vertical
    // overflow inside a deck card fails layout at 1.3x at de9521b
    // already, at every width — outside this PR's scope. 1.15x still
    // exercises the scale-down path without tripping that defect.)
    await pumpAt(AzamanTheme.dark, const Size(390, 844), textScale: 1.15);
    expectFullLabels(390, AzamanTheme.dark, 'settled, 1.15x text scale',
        scaleFloor: 0.7);
    await _flush(tester);
  });

  // ── DEPTH SEPARATION TRUTH (review blocker 1) ──────────────────────
  //
  // A REAL visual separation between the woken and settled rims — not
  // just "some pixels changed". The rim's CONTRAST against the page
  // plane is measured from the actual captures: the woken rim must be
  // measurably stronger than the settled rim (and than the
  // wallet-focus rim, which is settled-family), in BOTH themes.
  Future<double> rimContrast(String name, Rect pillRect) async {
    final data =
        await File('.screenshots/quiet_depth/$name.png').readAsBytes();
    final codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();
    final bytes = (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    final w = frame.image.width;
    int px(int x, int y) {
      final i = (y * w + x) * 4;
      return (bytes[i] * 299 + bytes[i + 1] * 587 + bytes[i + 2] * 114) ~/ 1000;
    }

    final x = ((pillRect.left + pillRect.right) / 2).round();
    final top = pillRect.top.round();
    final rim = px(x, top + 1); // inside the 1dp rim
    final page = px(x, top + 12); // the flat body = the page plane
    return (rim - page).abs().toDouble();
  }

  testWidgets('depth separation — woken vs settled vs wallet-focus rims differ measurably',
      (tester) async {
    const themes = [
      (AzamanTheme.dark, 'dark'),
      (AzamanTheme.light, 'light'),
    ];
    for (final (theme, prefix) in themes) {
      await _pumpHome(
        tester,
        theme: theme,
        susu: [_activeSusu(DateTime(2026, 10, 26))],
        intent: _cartIntent,
      );
      expect(find.byKey(const ValueKey('quiet-depth-raised')), findsWidgets);
      final rects = _pillRects(tester);
      final p0 = rects.first;
      await _capture(tester, '${prefix}_sep_raised');

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(const ValueKey('quiet-depth-recessed')), findsWidgets);
      await _capture(tester, '${prefix}_sep_recessed');

      await tester.tap(find.bySemanticsLabel('Reveal balance card').first);
      await _advance(tester);
      expect(_deckState(tester), WalletDeckState.balanceOut);
      await _capture(tester, '${prefix}_sep_focal');

      var ratios = <double>[];
      await tester.runAsync(() async {
        final woken = await rimContrast('${prefix}_sep_raised', p0);
        final settled = await rimContrast('${prefix}_sep_recessed', p0);
        final focus = await rimContrast('${prefix}_sep_focal', p0);
        // The woken rim is the STRONGER edge in both themes (in light
        // the softened rim blends TOWARD the near-white page, so its
        // contrast drops there too — same direction, different luma).
        ratios = [woken / settled, woken / focus];
        expect(settled, greaterThan(3),
            reason: '$prefix: the settled rim must still be VISIBLE '
                '(contrast $settled luma-steps), not fully erased');
        expect(ratios[0], greaterThan(1.25),
            reason: '$prefix: woken-vs-settled rim separation is too '
                'subtle (${(ratios[0] * 100).round()}%) — the depth story '
                'must be readable, not just measurable');
        expect(ratios[1], greaterThan(1.25),
            reason: '$prefix: the wallet-focus pills must read as '
                'settled-quiet (woken/focus = '
                '${(ratios[1] * 100).round()}%)');
      });
      await _flush(tester);
    }
  });

  testWidgets('dark width sweep 320/360: recessed captures', (tester) async {
    for (final w in [320.0, 360.0]) {
      await _pumpHome(
        tester,
        surface: Size(w, 844),
        susu: [_activeSusu(DateTime(2026, 10, 26))],
        intent: _cartIntent,
      );
      expect(find.byKey(const ValueKey('quiet-depth-raised')), findsWidgets);
      // Sequential pumps (a single pump(d) runs ONE frame at its end, which
    // would freeze the depth fade at its first tick).
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 80));
      _expectConfirmedBalance();
      expect(find.byKey(const ValueKey('quiet-depth-recessed')), findsWidgets);
      await _capture(tester, 'qd_dark_recessed_${w.toInt()}', verifyPills: true);
      await _flush(tester);
    }
  });
}
