import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/widgets/liquid/liquid_placement.dart';

const _small = Size(320, 640); // smallest phone we support
final _safe = LiquidSafeArea(screen: _small, padding: const EdgeInsets.only(top: 24, bottom: 16));

// A "+" pinned bottom-left, like the chat composer.
final _leftAnchor = const Rect.fromLTWH(14, 560, 44, 44);
// A category pill on the marketplace list.
final _pillAnchor = const Rect.fromLTWH(32, 300, 120, 44);

void expectInside(Rect r, LiquidSafeArea s, {String? because}) {
  expect(r.left, greaterThanOrEqualTo(s.left - 0.01), reason: because);
  expect(r.right, lessThanOrEqualTo(s.right + 0.01), reason: because);
  expect(r.top, greaterThanOrEqualTo(s.top - 0.01), reason: because);
  expect(r.bottom, lessThanOrEqualTo(s.bottom + 0.01), reason: because);
}

void main() {
  group('solvePanel', () {
    test('grows right from a left anchor and stays on screen at 320 dp', () {
      final p = solvePanel(anchor: _leftAnchor, panel: const Size(200, 240), safe: _safe);
      expectInside(p.rect, _safe);
      expect(p.above, isTrue);
      expect(p.rect.left, greaterThanOrEqualTo(_safe.left));
    });

    test('flips below when there is no room above', () {
      final top = const Rect.fromLTWH(14, 40, 44, 44);
      final p = solvePanel(anchor: top, panel: const Size(200, 400), safe: _safe);
      expect(p.above, isFalse);
      expectInside(p.rect, _safe);
    });

    test('clamps a panel wider than the screen', () {
      final p = solvePanel(anchor: _leftAnchor, panel: const Size(900, 240), safe: _safe);
      expectInside(p.rect, _safe);
    });

    test('followerOffset reproduces the solved rect', () {
      final p = solvePanel(anchor: _leftAnchor, panel: const Size(200, 240), safe: _safe);
      expect(_leftAnchor.topLeft + p.followerOffset(_leftAnchor), p.rect.topLeft);
    });
  });

  group('solveArc', () {
    List<Size> sizes(double scale) =>
        List.generate(6, (i) => Size((110 + i * 14) * scale, 44));

    test('all six pills stay inside the safe area at 1.0x', () {
      final slots = solveArc(anchor: _pillAnchor, sizes: sizes(1.0), safe: _safe);
      expect(slots.length, 6);
      for (final s in slots) {
        expectInside(s.rect, _safe, because: 'slot ${s.index}');
      }
    });

    test('and at 1.3x text scale on a 320 dp phone', () {
      final slots = solveArc(anchor: _pillAnchor, sizes: sizes(1.3), safe: _safe);
      for (final s in slots) {
        expectInside(s.rect, _safe, because: 'slot ${s.index} @1.3x');
      }
    });

    test('no pill overlaps the trigger at 1.0x', () {
      final slots = solveArc(anchor: _pillAnchor, sizes: sizes(1.0), safe: _safe);
      for (var i = 0; i < slots.length; i++) {
        expect(slots[i].rect.overlaps(_pillAnchor), isFalse, reason: 'slot $i over trigger');
      }
    });

    test('neighbouring pills do not overlap at 1.0x', () {
      final slots = solveArc(anchor: _pillAnchor, sizes: sizes(1.0), safe: _safe);
      for (var i = 0; i < slots.length; i++) {
        for (var j = i + 1; j < slots.length; j++) {
          if ((i - j).abs() == 1) {
            expect(slots[i].rect.overlaps(slots[j].rect.deflate(1)), isFalse, reason: 'adjacent $i vs $j');
          }
        }
      }
    });

    test('RTL mirrors the sector for a right-anchored trigger', () {
      final rightAnchor = const Rect.fromLTWH(180, 300, 110, 44);
      final rtl = solveArc(
        anchor: rightAnchor,
        sizes: sizes(1.0),
        safe: _safe,
        direction: TextDirection.rtl,
      );
      for (final s in rtl) {
        expectInside(s.rect, _safe, because: 'rtl slot ${s.index}');
      }
    });
  });
}
