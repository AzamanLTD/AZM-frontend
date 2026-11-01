// =============================================================================
// AZAMAN — CURRENCY WHEEL ALIGNMENT CONTRACT (BOTH AXES)
//
// The horizontal roller (Card Transfer's entry wheel, the home balance
// card's display wheel) inherited a half-crop defect from its first
// geometry: the whole strip was centre-aligned in the wheel's box with a
// chip+2*peek pitch, so the SELECTED chip sat on the box EDGE — half of
// it cropped by the wheel's own peek gutter, the accent border and the
// cedi glyph clipped. The neighbour sat a full pitch away, past the
// gutter, so nothing ever actually peeked either: the affordance the
// wheel exists for was invisible.
//
// This suite pins the corrected geometry on BOTH axes:
//   • the selected chip is DEAD-CENTRE in the wheel's box — its full
//     74dp width (44dp height vertical) inside the live clip, one peek
//     gutter on each side — at ANY option count: one chip, two, or more
//   • the immediate neighbour peeks EXACTLY the 14dp peek into the
//     trailing gutter; the chip beyond it is fully clipped
//   • the same contract holds after a deliberate roll (the new unit
//     recentres; the old one peeks through the leading gutter) — a graze
//     or an arena-cancelled drag changes nothing and re-centres
//   • the vertical roller (Send) is byte-identical to the geometry its
//     send suite already pinned at two options — regression-guarded here
//     at one and three options too, which the old centre-the-strip
//     geometry would have failed
//
// Measured from the painted widget tree (wheel box, chip containers,
// symbol Texts) — never assumed from layout constants.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/currency_catalog.dart';
import 'package:azaman/widgets/currency_wheel_toggle.dart';

const _wheelKey = ValueKey('test-currency-wheel');

const _peek = 14.0; // the component's published peek gutter
const _chipW = 74.0; // chip width, dp
const _chipH = 44.0; // chip height, dp — also the touch target floor

Widget _wrap(Widget child, {bool reduceMotion = false}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: (context, navigatorChild) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: navigatorChild ?? const SizedBox.shrink(),
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

Future<void> _pumpWheel(
  WidgetTester tester, {
  required List<AzCurrency> options,
  int selected = 0,
  bool vertical = false,
  bool reduceMotion = false,
  Size surface = const Size(400, 890),
  void Function(int)? onChanged,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _wrap(
        CurrencyWheelToggle(
          key: _wheelKey,
          options: options,
          selectedIndex: selected,
          axis: vertical
              ? CurrencyWheelAxis.vertical
              : CurrencyWheelAxis.horizontal,
          onChanged: onChanged ?? (_) {},
        ),
        reduceMotion: reduceMotion,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

Rect _wheelRect(WidgetTester tester) => tester.getRect(find.byKey(_wheelKey));

/// The chip Containers painted inside the wheel, in strip order.
List<Rect> _chipRects(WidgetTester tester) {
  final chips = find
      .descendant(
        of: find.byKey(_wheelKey),
        matching: find.byWidgetPredicate(
          // The chips are the only decorated Containers inside the
          // wheel; Container's size fields are not public getters, so
          // the decoration identifies them and the RECT is measured.
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
      )
      .evaluate();
  return [for (final e in chips) tester.getRect(find.byWidget(e.widget))];
}

/// The symbol Text whose centre is nearest the wheel's centre: the
/// readable label of the SELECTED chip.
String _selectedSymbol(WidgetTester tester) {
  final center = _wheelRect(tester).center;
  var best = '';
  var bestDistance = double.infinity;
  final texts = find
      .descendant(of: find.byKey(_wheelKey), matching: find.byType(Text))
      .evaluate();
  for (final e in texts) {
    final rect = tester.getRect(find.byWidget(e.widget));
    final d = (rect.center - center).distance;
    if (d < bestDistance) {
      bestDistance = d;
      best = (e.widget as Text).data ?? '';
    }
  }
  return bestDistance < _peek + 12 ? best : '';
}

/// The selected chip's expected rect: dead-centre in the wheel's box.
Rect _centredChip(Rect wheel, {required bool vertical}) => vertical
    ? Rect.fromLTWH(wheel.left, wheel.top + _peek, _chipW, _chipH)
    : Rect.fromLTWH(wheel.left + _peek, wheel.top, _chipW, _chipH);

void expectSelectedChipCentred(WidgetTester tester, {required bool vertical}) {
  final wheel = _wheelRect(tester);
  expect(
    wheel.width,
    vertical ? _chipW : _chipW + 2 * _peek,
    reason: 'the wheel box is one chip plus the two peek gutters',
  );
  expect(
    wheel.height,
    vertical ? _chipH + 2 * _peek : _chipH,
    reason: 'the wheel box is one chip plus the two peek gutters',
  );

  final chips = _chipRects(tester);
  expect(chips, isNotEmpty, reason: 'the strip paints its chips');

  final centred = _centredChip(wheel, vertical: vertical);
  // Whichever unit is selected rides the centred slot — the strip order
  // is fixed (GHS, USDC, …), so after a roll the centred chip is NOT
  // strip index 0.
  final onCentre = chips.indexWhere(
    (c) =>
        (c.left - centred.left).abs() <= 0.5 &&
        (c.top - centred.top).abs() <= 0.5,
  );
  expect(
    onCentre != -1,
    isTrue,
    reason:
        'the SELECTED chip sits dead-centre in the wheel box (chips '
        '$chips, expected the selected one at $centred) — never cropped '
        'by the peek gutters',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // ThemeProvider reads SharedPreferences at construction.
    SharedPreferences.setMockInitialValues({});
  });

  group('horizontal — the selected chip is never cropped', () {
    for (final size in const [(320.0, 568.0), (360.0, 740.0), (390.0, 844.0)]) {
      testWidgets('centred and fully visible at ${size.$1.truncate()}dp '
          '(surface ${size.$1.truncate()}×${size.$2.truncate()})', (
        tester,
      ) async {
        await _pumpWheel(
          tester,
          options: CurrencyCatalog.sendEntryUnits,
          surface: Size(size.$1, size.$2),
        );
        expectSelectedChipCentred(tester, vertical: false);
        expect(
          _selectedSymbol(tester),
          'GH₵',
          reason: 'the GHS-first entry label is fully readable',
        );
      });
    }

    testWidgets('the immediate neighbour peeks exactly the gutter — '
        'nothing beyond it', (tester) async {
      await _pumpWheel(
        tester,
        options: [CurrencyCatalog.ghs, CurrencyCatalog.usdc],
      );
      final wheel = _wheelRect(tester);
      final chips = _chipRects(tester);
      expect(chips.length, 2);

      // The neighbour's leading edge is exactly one peek inside the box:
      // visible portion == 14dp, the fade's whole territory.
      expect(
        chips[1].left >= wheel.right - _peek - 0.5 &&
            chips[1].left <= wheel.right - _peek + 0.5,
        isTrue,
        reason:
            'the USDC neighbour peeks exactly ${_peek}dp through the '
            'trailing gutter (got left ${chips[1].left}, wheel right '
            '${wheel.right}) — the roll affordance is visible',
      );
      // Its full rectangle extends past the clip: the label is NOT
      // readable — only the selected chip carries the money meaning.
      expect(chips[1].right > wheel.right, isTrue);
    });

    testWidgets('a single option still centres — option count never '
        'decides visibility', (tester) async {
      await _pumpWheel(tester, options: [CurrencyCatalog.ghs]);
      expectSelectedChipCentred(tester, vertical: false);
      expect(_selectedSymbol(tester), 'GH₵');
    });

    testWidgets('three options: the second peeks, the third is fully '
        'clipped', (tester) async {
      await _pumpWheel(
        tester,
        options: [
          CurrencyCatalog.ghs,
          CurrencyCatalog.usdc,
          CurrencyCatalog.ghs,
        ],
      );
      final wheel = _wheelRect(tester);
      final chips = _chipRects(tester);
      expect(chips.length, 3);
      expectSelectedChipCentred(tester, vertical: false);
      expect(chips[1].left, closeTo(wheel.right - _peek, 0.5));
      expect(
        chips[2].left >= wheel.right - 0.5,
        isTrue,
        reason:
            'the chip beyond the neighbour is fully outside the '
            'live clip',
      );
    });

    testWidgets('a deliberate roll recentres the NEW unit; the old one '
        'peeks through the leading gutter', (tester) async {
      var changedTo = -1;
      await _pumpWheel(
        tester,
        options: CurrencyCatalog.sendEntryUnits,
        onChanged: (i) => changedTo = i,
      );

      // Left swipe WELL past the 24dp deliberate threshold (tester.drag
      // consumes ~18dp of touch slop before the recognizer claims the
      // gesture, so -40dp only delivers ~22dp of travel: the send
      // suite's -60dp keeps the test honest for the same reason).
      await tester.drag(find.byKey(_wheelKey), const Offset(-60, 0));
      await tester.pumpAndSettle();

      expect(changedTo, 1, reason: 'the deliberate roll advanced the unit');
      expectSelectedChipCentred(tester, vertical: false);
      expect(
        _selectedSymbol(tester),
        'USDC',
        reason: 'the newly selected label is the readable one',
      );

      final wheel = _wheelRect(tester);
      final chips = _chipRects(tester);
      expect(
        chips[0].right,
        closeTo(wheel.left + _peek, 0.5),
        reason:
            'the GHS chip now peeks exactly the gutter on the '
            'leading side',
      );
    });

    testWidgets('a graze below the deliberate threshold never changes the '
        'unit', (tester) async {
      await _pumpWheel(tester, options: CurrencyCatalog.sendEntryUnits);
      final before = _selectedSymbol(tester);

      final gesture = await tester.startGesture(_wheelRect(tester).center);
      await gesture.moveBy(const Offset(-10, 0)); // below the 24dp floor
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        _selectedSymbol(tester),
        before,
        reason: 'a graze never rolls money denominations',
      );
      expectSelectedChipCentred(tester, vertical: false);
    });

    testWidgets('reduced motion lands the new unit instantly, centred', (
      tester,
    ) async {
      await _pumpWheel(
        tester,
        options: CurrencyCatalog.sendEntryUnits,
        reduceMotion: true,
      );
      await tester.drag(find.byKey(_wheelKey), const Offset(-60, 0));
      await tester.pump(const Duration(milliseconds: 16));

      expect(_selectedSymbol(tester), 'USDC');
      expectSelectedChipCentred(tester, vertical: false);
    });
  });

  group("vertical — regression: Send's proven geometry holds", () {
    testWidgets('the two-option wheel keeps its pinned geometry', (
      tester,
    ) async {
      await _pumpWheel(
        tester,
        options: CurrencyCatalog.sendEntryUnits,
        vertical: true,
      );
      expectSelectedChipCentred(tester, vertical: true);
      expect(_selectedSymbol(tester), 'GH₵');

      final wheel = _wheelRect(tester);
      final chips = _chipRects(tester);
      expect(
        chips[1].top,
        closeTo(wheel.bottom - _peek, 0.5),
        reason: 'the neighbour still peeks exactly ${_peek}dp below',
      );
    });

    testWidgets('a single option centres (new coverage)', (tester) async {
      await _pumpWheel(tester, options: [CurrencyCatalog.ghs], vertical: true);
      expectSelectedChipCentred(tester, vertical: true);
    });

    testWidgets('three options: the selected chip stays centred, the '
        'third is clipped (new coverage)', (tester) async {
      await _pumpWheel(
        tester,
        options: [
          CurrencyCatalog.ghs,
          CurrencyCatalog.usdc,
          CurrencyCatalog.ghs,
        ],
        vertical: true,
      );
      final wheel = _wheelRect(tester);
      final chips = _chipRects(tester);
      expectSelectedChipCentred(tester, vertical: true);
      expect(chips[1].top, closeTo(wheel.bottom - _peek, 0.5));
      expect(
        chips[2].top >= wheel.bottom - 0.5,
        isTrue,
        reason: 'the chip beyond the neighbour is fully clipped',
      );
    });
  });
}
