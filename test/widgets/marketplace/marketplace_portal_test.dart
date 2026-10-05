import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/models/business_models.dart';

/// Marketplace ONE-SCREEN guards (experience pass §11 + §12):
///   1. The bare marketplace tab is the ONE result screen — the category
///      SPEED DIAL (the radial-fan grammar) is THE category system, with
///      All as a real selectable state, and Near You as the ONLY control
///      outside the selector.
///   2. The portal machinery (world deck, "choose your world", resume card,
///      explore-all, back-to-portal bar) is GONE — no duplicated interaction
///      path exists.
///   3. Picking a category from the fan IMMEDIATELY changes the result
///      surface; picking All clears back to all results.
///   4. The star/featured surface is GONE — no "Featured picks near you",
///      no Featured wording, no star shortcut.
///   5. A launcher `initialCategory` still seeds the category filter
///      (TASK-010b entry contract, unchanged).

class _RecordingSearchNotifier extends BusinessSearchNotifier {
  _RecordingSearchNotifier() : super(BusinessService());

  final List<String?> searchedCategories = [];

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {
    searchedCategories.add(category);
    // Recorded, not fired — no network in this guard.
  }
}

Future<_RecordingSearchNotifier> _pumpHome(
  WidgetTester tester, {
  String? initialCategory,
}) async {
  final notifier = _RecordingSearchNotifier();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [businessSearchProvider.overrideWith((ref) => notifier)],
      child: MaterialApp(
        home: MarketplaceHomeScreen(initialCategory: initialCategory),
      ),
    ),
  );
  // Post-frame seeding search + one-shot child timers.
  await tester.pump(const Duration(milliseconds: 600));
  return notifier;
}

/// The dial anchor pill (the GestureDetector inside CategorySpeedDial)
/// — the ValueKey sits on the speed dial itself, whose slot spans the row.
Finder _dialAnchor() => find
    .descendant(
      of: find.byKey(const ValueKey('marketplace-category-dial')),
      matching: find.byType(GestureDetector),
    )
    .first;

void main() {
  testWidgets('the bare tab opens the ONE result screen', (tester) async {
    await _pumpHome(tester);

    // The category SPEED DIAL is the selector (§11): at rest the anchor
    // shows the current category — All, a REAL selectable state.
    expect(find.byKey(const ValueKey('marketplace-category-dial')),
        findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    // Near You is the ONLY additional control.
    expect(find.byKey(const ValueKey('marketplace-near-you')),
        findsOneWidget);
    // No flat row of standalone category buttons.
    for (final label in ['Eat', 'Shop', 'Ride', 'Stay']) {
      expect(find.byKey(ValueKey('marketplace-category-$label')),
          findsNothing);
    }

    // The portal machinery is GONE — every old duplicated interaction path.
    expect(find.text('Discover'), findsNothing);
    expect(find.text('Choose your world'), findsNothing);
    expect(find.byKey(const ValueKey('marketplace_explore_all')),
        findsNothing);
    expect(find.byKey(const ValueKey('marketplace_back_to_portal')),
        findsNothing);
    for (final wire in [
      'LOGISTICS',
      'FOOD_BEVERAGE',
      'HOSPITALITY',
      'RETAIL',
    ]) {
      expect(find.byKey(ValueKey('marketplace_world_$wire')), findsNothing);
    }

    // The old world-dial labels are gone (the fan's arms use the
    // four-word vertical language: Eat / Shop / Ride / Stay).
    expect(find.text('Restaurants'), findsNothing);
    expect(find.text('Hotels'), findsNothing);
    expect(find.text('Transit'), findsNothing);
    expect(find.text('Retail'), findsNothing);
  });

  testWidgets('picking Eat from the fan immediately changes the result '
      'surface; picking All clears back', (tester) async {
    final notifier = await _pumpHome(tester);
    final baseline = notifier.searchedCategories.length;

    // Open the radial fan, then pick the Eat satellite.
    await tester.tap(_dialAnchor());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eat'));
    await tester.pumpAndSettle();

    // The category fires a real search through the existing plumbing —
    // no second screen, no portal hop.
    expect(notifier.searchedCategories.length, baseline + 1);
    expect(notifier.searchedCategories.last, 'FOOD_BEVERAGE');
    // The dial anchor now announces Eat as the active category (the other
    // 'Eat' text is the legitimate discovery intent rail).
    expect(find.bySemanticsLabel(RegExp('Category: Eat')), findsOneWidget);

    // Picking All (a real selectable state) clears the filter.
    await tester.tap(_dialAnchor());
    await tester.pumpAndSettle();
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(notifier.searchedCategories.last, isNull);
    expect(find.text('All'), findsOneWidget);
  });

  testWidgets('the star/featured surface is gone entirely (§12)',
      (tester) async {
    await _pumpHome(tester);
    expect(find.text('Featured picks near you'), findsNothing);
    expect(find.textContaining('Featured'), findsNothing);
    // No star shortcut on the composition.
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  testWidgets('initialCategory still seeds the category filter',
      (tester) async {
    final notifier =
        await _pumpHome(tester, initialCategory: 'retail');
    // TASK-010b entry contract: the seeding search fires with the
    // normalised wire — unchanged by the one-screen correction.
    expect(notifier.searchedCategories.first, 'RETAIL');
    // The dial anchor renders Shop (RETAIL) as the active category.
    expect(find.text('Shop'), findsOneWidget);
  });

  testWidgets('results render on the one screen — no second marketplace '
      'screen before them', (tester) async {
    final notifier = _RecordingSearchNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [businessSearchProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: MarketplaceHomeScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // The list/map area exists immediately on the bare tab.
    expect(find.byType(ListView), findsWidgets);
  });

  group('UX-CORRECTION §1 — compact category dial geometry', () {
    Future<void> openFan(WidgetTester tester) async {
      await _pumpHome(tester);
      await tester.tap(_dialAnchor());
      await tester.pumpAndSettle();
    }

    testWidgets('the fan is the EXACT five-category set — Services and '
        'Wellness satellites do not exist', (tester) async {
      await openFan(tester);
      // 'All' renders twice while the fan is open (the real anchor pill
      // plus the goo trigger-ghost on top of it) — that duplication is the
      // existing ghost mechanism, not a second category control.
      expect(find.text('All'), findsWidgets);
      for (final label in ['Eat', 'Shop', 'Ride', 'Stay']) {
        expect(find.text(label), findsOneWidget,
            reason: 'category set is exactly All/Shop/Ride/Stay/Eat');
      }
      expect(find.text('Services'), findsNothing);
      expect(find.text('Wellness'), findsNothing);
    });

    testWidgets('right-oriented fan — first two satellites on the '
        'horizontal line through the anchor, rest in 45° steps '
        '(PR #142 final pass §1)', (tester) async {
      await openFan(tester);
      final anchor = tester.getRect(_dialAnchor());
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      // The pill rect (the satellite's own GestureDetector), not the text
      // rect — the icon left of the label offsets the text center.
      Offset pillCentre(String label) => tester
          .getRect(find.ancestor(
              of: find.text(label), matching: find.byType(GestureDetector)).first)
          .center;
      // The dial list order minus the selected "All": Eat, Shop, Ride, Stay.
      final eat = pillCentre('Eat');
      final shop = pillCentre('Shop');
      final ride = pillCentre('Ride');
      final stay = pillCentre('Stay');

      // The first two satellite positions establish a straight horizontal
      // line through the selected category.
      expect(eat.dy, closeTo(anchor.center.dy, 1.5));
      expect(shop.dy, closeTo(anchor.center.dy, 1.5));
      // The line reaches into the available right-side space, past the
      // anchor's edge (the old 132° arc hugged instead of lining up).
      expect(eat.dx, greaterThan(anchor.right));
      expect(shop.dx, greaterThan(eat.dx));
      // The remaining satellites step 45° from that baseline: Ride at the
      // down-right diagonal, Stay straight below the anchor center.
      expect(ride.dx, greaterThan(anchor.center.dx));
      expect(ride.dy, greaterThan(anchor.center.dy));
      expect(stay.dx, closeTo(anchor.center.dx, 1.5));
      expect(stay.dy, greaterThan(anchor.bottom));

      // NOT a wide burst: no satellite wraps around the anchor's dead
      // (left) side. Stay sits ~1px inside the 90° slot at settle — the
      // damped launch spring parks at ~97% travel by design, so the bound
      // is the anchor's own left edge, not its center.
      for (final c in [eat, shop, ride, stay]) {
        expect(c.dx, greaterThan(anchor.left));
      }
      // Every pill stays comfortably inside the viewport.
      for (final label in ['Eat', 'Shop', 'Ride', 'Stay']) {
        final r = tester.getRect(find.text(label));
        expect(r.left, greaterThan(0));
        expect(r.right, lessThan(size.width));
        expect(r.top, greaterThan(0));
        expect(r.bottom, lessThan(size.height));
      }
      // NOT a tall semicircle: the whole fan fits inside a compact band.
      final topMost = tester
          .getRect(find.text('Eat'))
          .top; // eat and shop share the line — same band
      final bottomMost = tester.getRect(find.text('Stay')).bottom;
      expect(bottomMost - topMost, lessThan(220));
    });

    testWidgets('neighbouring satellites never overlap (collision safety '
        'in the compact arc)', (tester) async {
      await openFan(tester);
      final rects = [
        for (final label in ['Eat', 'Shop', 'Ride', 'Stay'])
          tester.getRect(find.text(label)).inflate(4)
      ];
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse,
              reason: 'satellites $i and $j overlap');
        }
        expect(rects[i].overlaps(anchorShrink(_dialAnchor(), tester)),
            isFalse, reason: 'satellite $i overlaps the anchor pill');
      }
    });
  });

  group('UX-CORRECTION §2 — satellite labels always fully readable', () {
    testWidgets('all five labels paint complete when the fan is open — no '
        'clipping, no fade, no truncation', (tester) async {
      await _pumpHome(tester);
      await tester.tap(_dialAnchor());
      await tester.pumpAndSettle();

      const satStyle = TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      );
      for (final label in ['Eat', 'Shop', 'Ride', 'Stay']) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: satStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final rendered = tester.renderObject<RenderParagraph>(find.text(label));
        // The pill has no width constraint on its label: the paragraph is
        // exactly the full intrinsic text size. Any clip/fade workaround
        // would shrink it below the painter's full width.
        expect(rendered.size.width, greaterThanOrEqualTo(painter.width),
            reason: 'label "$label" is clipped');
        expect(rendered.size.height, greaterThanOrEqualTo(painter.height));
      }
      // The anchor pill keeps the selected category fully visible too.
      final painter = TextPainter(
        text: const TextSpan(
            text: 'All',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      final anchor = tester.renderObject<RenderParagraph>(
          find.text('All').first);
      expect(anchor.size.width, greaterThanOrEqualTo(painter.width));
    });
  });
}

Rect anchorShrink(Finder f, WidgetTester tester) =>
    tester.getRect(f).deflate(8);

