// =============================================================================
// AZAMAN — CONVERT DIRECTION DISC HIT-TEST SUITE (PR #202)
//
// The From/To card pair renders the direction switch as a seam disc in an
// OverflowBox slot that is EXACTLY the cards' 16dp gap. The disc PAINTS
// over both cards' inner edges; its centre — the tap point — stays inside
// the slot. That is the audit contract this suite pins:
//
//   1. HONEST HIT-TESTABILITY — the disc paints outside its layout slot
//      (over both cards) but the tap that reverses direction lands at the
//      painted centre. No phantom button painted out of reach.
//   2. BEHAVIOUR — a tap reverses the direction and clears the amount
//      (a stale amount must never silently convert in the new direction);
//      a second tap restores the original direction.
//   3. STATE AFFORDANCE — the icon's rotation and the panels' asset pills
//      both reflect the live direction, so the seam disc can never
//      disagree with the panels it sits between.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/currency_model.dart';
import 'package:azaman/providers/currency_provider.dart'
    show FxRateSnapshot, fxRateProvider;
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/wallet/convert_screen.dart';

const _storageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

FxRateSnapshot _pinnedRate() {
  final now = DateTime.now().toUtc();
  return FxRateSnapshot(
    ghsPerUsdc: 12.50,
    source: 'KOTANI',
    lastSync: now,
    fetchedAt: now,
    serverFresh: true,
    lastExternalSync: now,
    externalRateAgeSeconds: 0,
    rateFreshnessMaxAgeSeconds: 60,
  );
}

Future<void> _pumpSubject(WidgetTester tester) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
        if (call.method == 'read') return 'mock-token';
        return null;
      });
  SharedPreferences.setMockInitialValues({'azaman_theme': 0});
  tester.view
    ..physicalSize = const Size(390, 844) * 3.0
    ..devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [fxRateProvider.overrideWith((ref) async => _pinnedRate())],
  );
  addTearDown(container.dispose);
  container.read(currencyProvider.notifier).state = DisplayCurrency.ghs;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: const ConvertScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('the seam disc paints over both cards while its tap point stays '
      'inside the slot — honestly hit-testable', (tester) async {
    await _pumpSubject(tester);

    final disc = find.byKey(const Key('convert_direction_switch'));
    final fromRect = tester.getRect(
      find.byKey(const Key('convert_from_panel')),
    );
    final toTopLeft = tester.getTopLeft(
      find.byKey(const Key('convert_to_panel')),
    );

    // The disc's ink band: a 44dp-tall band centred on the cards' seam.
    // The OverflowBox slot is the 16dp gap; the band paints over both
    // cards' inner edges while staying inside the viewport.
    final discRect = tester.getRect(
      find.descendant(of: disc, matching: find.byType(InkWell)),
    );

    // The slot is the From/To gap: the disc PAINTS beyond it on both
    // sides — over both cards' inner edges.
    expect(
      discRect.top,
      lessThan(fromRect.bottom),
      reason: 'the disc must paint over the From card bottom edge',
    );
    expect(
      discRect.bottom,
      greaterThan(toTopLeft.dy),
      reason: 'the disc must paint over the To card top edge',
    );
    // ...while the disc's CENTRE — the tap point — sits inside the slot
    // (between the cards) and inside the viewport: no phantom control.
    final centre = discRect.center;
    expect(centre.dy, greaterThan(fromRect.bottom - 1));
    expect(centre.dy, lessThan(toTopLeft.dy + 1));
    expect(centre.dx, inInclusiveRange(0, 390));
    expect(centre.dy, inInclusiveRange(0, 844));
    // The band is 44dp tall — the minimum touch target.
    expect(discRect.height, 44);
    // The behavioural proof of hit honesty: a tap AT THE PAINTED CENTRE
    // must land (the OverflowBox must not swallow the hit).
    await tester.tapAt(centre);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedRotation>(
            find.descendant(
              of: find.byKey(const Key('convert_direction_switch')),
              matching: find.byType(AnimatedRotation),
            ),
          )
          .turns,
      0.5,
      reason: 'a landed tap must have reversed the direction',
    );
  });

  testWidgets('a tap reverses direction and clears the amount; a second tap '
      'restores it', (tester) async {
    await _pumpSubject(tester);

    // Seed a meaningful amount, then reverse — the stale amount must not
    // survive the direction change.
    await tester.enterText(
      find.byKey(const Key('convert_amount_field')),
      '12.5',
    );
    await tester.pump();
    expect(
      find.text('USDC'),
      findsWidgets,
      reason: 'precondition: the unreversed From pill reads USDC',
    );

    await tester.tap(
      find.byKey(const Key('convert_direction_switch')),
      warnIfMissed: true,
    );
    await tester.pumpAndSettle();

    // Direction reversed: the amount field was cleared by
    // _switchDirection — a stale amount must never silently re-target
    // the new direction.
    final field = tester.widget<TextField>(
      find.byKey(const Key('convert_amount_field')),
    );
    expect(field.controller!.text, isEmpty);

    // The From pill now reads GHS — the panels agree with the disc.
    expect(find.text('GHS'), findsWidgets);

    await tester.tap(
      find.byKey(const Key('convert_direction_switch')),
      warnIfMissed: true,
    );
    await tester.pumpAndSettle();

    // Back to the original direction.
    expect(
      tester
          .widget<AnimatedRotation>(
            find.descendant(
              of: find.byKey(const Key('convert_direction_switch')),
              matching: find.byType(AnimatedRotation),
            ),
          )
          .turns,
      0.0,
    );
  });

  testWidgets('the disc declares itself a button with the honest tooltip', (
    tester,
  ) async {
    await _pumpSubject(tester);
    final disc = find.byKey(const Key('convert_direction_switch'));
    final semantics = tester.widget<Semantics>(disc);
    expect(semantics.properties.button, isTrue);
    expect(
      semantics.properties.tooltip,
      'Switch conversion direction. Display only — nothing converts.',
      reason: 'the disc must never imply a conversion that does not exist',
    );
  });
}
