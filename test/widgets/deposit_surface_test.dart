// =============================================================================
// ADD CASH REDESIGN — WIDGET TESTS: GROUP G (pull-down dismissal) + GROUP H
// (the Crypto panel: Polygon address, QR, explicit network statement).
//
// Demo mode seeds the deposit address (0xDemo…1234), so the whole crypto
// panel is exercised end-to-end without network stubs.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/config.dart';
import 'package:azaman/router/transitions.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/screens/receive_screen.dart';
import 'package:azaman/widgets/animated_qr_dust.dart';
import 'package:azaman/providers/saved_momo_provider.dart';

class _FakeEmptySavedMomo extends SavedMomoNotifier {
  @override
  Future<List<SavedMomoAccount>> build() async => const [];
}

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (c, s) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => GoRouter.of(c).push('/deposit'),
                child: const Text('home-sentinel'),
              ),
              TextButton(
                onPressed: () => GoRouter.of(c).push('/receive'),
                child: const Text('receive-sentinel'),
              ),
            ],
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/deposit',
      name: 'deposit',
      pageBuilder: (c, s) => risePage(
        key: s.pageKey,
        restorationId: s.name,
        child: const DepositScreen(),
      ),
    ),
    GoRoute(
      path: '/receive',
      name: 'receive',
      pageBuilder: (c, s) => risePage(
        key: s.pageKey,
        restorationId: s.name,
        child: const ReceiveScreen(),
      ),
    ),
  ],
);

Widget _app() => ProviderScope(
  overrides: [
    // No accounts: the fiat panel's method row is inert and can never
    // intercept the vertical drag.
    savedMomoProvider.overrideWith(_FakeEmptySavedMomo.new),
  ],
  child: MaterialApp.router(routerConfig: _router()),
);

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openDeposit(WidgetTester tester) async {
  await tester.tap(find.text('home-sentinel'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 1));
  // The header title AND the CTA both say Add Cash.
  expect(find.text('Add Cash'), findsWidgets);
}

Future<void> _openReceive(WidgetTester tester) async {
  await tester.tap(find.text('receive-sentinel'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 1));
  expect(find.text('Receive'), findsOneWidget);
}

/// A neutral spot to start a pull: the panel heading text — never a button,
/// never a scrollable.
Offset _dragOrigin(WidgetTester tester) =>
    tester.getCenter(find.text('Add Cash').first);

void main() {
  AppConfig.enableDemoMode();

  group('G — pull-down dismissal', () {
    testWidgets('a short pull below threshold springs back; the surface '
        'stays', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);

      // Finger travel 100px → visual drag = 100 × 0.55 = 55 < 110.
      final gesture = await tester.startGesture(_dragOrigin(tester));
      await gesture.moveBy(const Offset(0, 100));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump();
      // Spring back (MotionTokens.control) — let it settle.
      await tester.pump(const Duration(milliseconds: 400));

      // Still here (header AND CTA both say Add Cash).
      expect(find.text('Add Cash'), findsWidgets);
      expect(find.text('home-sentinel'), findsNothing);
    });

    testWidgets('a committed pull (past threshold) pops the surface', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);

      // Finger travel 220px → visual drag = 220 × 0.55 = 121 ≥ 110.
      final gesture = await tester.startGesture(_dragOrigin(tester));
      await gesture.moveBy(const Offset(0, 220));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump();

      // Route pop (risePage transition out) — pump it to completion.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Add Cash'), findsNothing);
      expect(find.text('home-sentinel'), findsOneWidget);
    });

    testWidgets('a fast fling commits even when the pull is short', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);

      // Distance stays below threshold (190 × 0.55 = 104.5 < 110) but the
      // gesture is flung fast; the velocity term alone must commit.
      await tester.fling(
        find.text('Add Cash').first,
        const Offset(0, 190),
        2200,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Add Cash'), findsNothing);
      expect(find.text('home-sentinel'), findsOneWidget);
    });

    testWidgets('the header X is the one tap-to-close affordance', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Add Cash'), findsNothing);
      expect(find.text('home-sentinel'), findsOneWidget);
    });
  });

  group('H — crypto panel', () {
    testWidgets('switching to Crypto fetches the address and renders the '
        'complete instrument', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openReceive(tester);

      // Receive opens on Fiat, with its Crypto destination available at the top.
      expect(find.text('Your Azaman ID'), findsOneWidget);

      await tester.tap(find.text('Crypto'));
      await tester.pump(); // anchor the tab animation ticker
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Receive USDC'), findsOneWidget);
      expect(find.text('Polygon'), findsWidgets); // network chip + copy
      // The QR is the main visual.
      expect(find.byType(AnimatedQrDust), findsOneWidget);
      // Shortened visually…
      expect(find.text('0xDemo…1234'), findsOneWidget);
      // …and the explicit network statement is never buried.
      expect(
        find.textContaining('Send only USDC on the Polygon network'),
        findsOneWidget,
      );
    });

    testWidgets('copy puts the FULL address on the clipboard and confirms '
        'with a snackbar', (tester) async {
      final recorder = _ClipboardRecorder();
      // In this SDK the Clipboard utility writes over the shared
      // 'flutter/platform' channel (SystemChannels.platform, see
      // services/clipboard.dart). Other calls on that channel (haptics…)
      // pass through the recorder untouched.
      const platformChannel = MethodChannel(
        'flutter/platform',
        JSONMethodCodec(),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platformChannel, recorder.handler);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(platformChannel, null),
      );

      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openReceive(tester);

      await tester.tap(find.text('Crypto'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Copy address'));
      await tester.pump(); // snackbar route
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Address copied'), findsOneWidget);

      expect(recorder.lastText, '0xDemo1234567890abcdef1234567890abcdef1234');
    });

    testWidgets('semantics expose the FULL address, not the shortened text', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openReceive(tester);

      await tester.tap(find.text('Crypto'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));

      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(
          'Polygon USDC deposit address: '
          '0xDemo1234567890abcdef1234567890abcdef1234',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('I — Receive / Request resting-state interaction', () {
    testWidgets('Request button snaps to the selected header and toggles back',
        (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openReceive(tester);

      final toggle = find.byKey(const ValueKey('receive-request-toggle'));
      expect(find.bySemanticsLabel('Open Request section'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 650));

      expect(
        find.bySemanticsLabel(
          'Request section, selected. Tap to return to Receive.',
        ),
        findsOneWidget,
      );

      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 650));

      expect(find.bySemanticsLabel('Open Request section'), findsOneWidget);
    });

    testWidgets('downward pull from Request returns to Receive before close',
        (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openReceive(tester);

      final toggle = find.byKey(const ValueKey('receive-request-toggle'));
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 650));
      expect(find.text('Request money'), findsOneWidget);

      // Pull from the Request heading, outside the nested contact list. The
      // first committed downward pull returns to Receive; it must not dismiss
      // the full-page route or leave its outer translation displaced.
      final origin = tester.getCenter(find.text('Request money'));
      final gesture = await tester.startGesture(origin);
      await gesture.moveBy(const Offset(0, 240));
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('Receive'), findsOneWidget);
      expect(find.bySemanticsLabel('Open Request section'), findsOneWidget);
      expect(find.text('receive-sentinel'), findsNothing);
    });

    testWidgets('an intentional pull snaps into Request; a short pull returns',
        (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openReceive(tester);

      final toggle = find.byKey(const ValueKey('receive-request-toggle'));
      final center = tester.getCenter(toggle);
      final short = await tester.startGesture(center);
      await short.moveBy(const Offset(0, -70));
      await tester.pump(const Duration(milliseconds: 40));
      await short.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 650));
      expect(find.bySemanticsLabel('Open Request section'), findsOneWidget);

      final origin = tester.getCenter(toggle);
      final committed = await tester.startGesture(origin);
      await committed.moveBy(const Offset(0, -210));
      await tester.pump(const Duration(milliseconds: 60));
      await committed.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 650));
      expect(
        find.bySemanticsLabel(
          'Request section, selected. Tap to return to Receive.',
        ),
        findsOneWidget,
      );
    });
  });
}

/// Captures what the app writes to the system clipboard, via the same
/// platform channel the Clipboard utility uses.
class _ClipboardRecorder {
  String? lastText;
  Future<Object?> handler(MethodCall call) async {
    if (call.method == 'Clipboard.setData') {
      lastText = (call.arguments as Map)['text'] as String?;
    }
    return null;
  }
}
