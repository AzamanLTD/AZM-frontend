// NEW-HOME §8 — the floating + action launcher.
//
// Closed: only the vibrant + trigger. Open: the content de-emphasizes
// behind it and the actions appear DIRECTLY on the screen (no boxed
// modal); the + becomes the close affordance; a pick closes, fires the
// action, and reports exactly once. The launcher is a reusable component:
// these tests pass their own actions, nothing Home-specific is involved.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/plus_action_launcher.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';

/// A fresh controller per pump — the shell owns the controller so it can
/// toggle the launcher from the nav band; the tests own one each.
PlusLauncherController? _lastController;

Future<void> _pumpLauncher(
  WidgetTester tester, {
  bool reducedMotion = false,
  required List<PlusLauncherAction> actions,
}) async {
  final controller = PlusLauncherController();
  _lastController = controller;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 900))
              .copyWith(disableAnimations: reducedMotion),
          child: Scaffold(
            body: PlusActionLauncher(
                controller: controller, actions: actions),
          ),
        ),
      ),
    ),
  );
}


/// CORRECTION G geometry tests mount the TRIGGER too — beside a bottom
/// bar, exactly like the real shell (PremiumBottomNav.trailing) — so the
/// overlay measures a real physical + rect instead of falling back to
/// the no-trigger default. The overlay sits in a full-screen Stack over
/// a body, matching main.dart's Scaffold(extendBody: true) composition.
Future<void> _pumpShell(
  WidgetTester tester, {
  required List<PlusLauncherAction> actions,
  Size size = const Size(400, 900),
}) async {
  final controller = PlusLauncherController();
  _lastController = controller;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: Scaffold(
            extendBody: true,
            bottomNavigationBar: SizedBox(
              height: 70,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: AzSpace.lg),
                    child: PlusLauncherTrigger(controller: controller),
                  ),
                ],
              ),
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: PlusActionLauncher(
                      controller: controller, actions: actions),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('closed at rest: the overlay layer is empty — the trigger '
      'lives in the nav band, not here', (tester) async {
    await _pumpLauncher(
      tester,
      actions: [
        PlusLauncherAction(
            icon: Icons.send, label: 'Send', onTap: () => fail('must not '
                'fire while closed')),
      ],
    );

    expect(find.text('Send'), findsNothing,
        reason: 'no action rows mount while the launcher is closed');
    expect(find.byIcon(Icons.add), findsNothing,
        reason: 'the + trigger is PremiumBottomNav.trailing now — the '
            'launcher owns only the overlay layer');
  });

  testWidgets('tapping + opens the actions directly on screen; picking '
      'closes and reports exactly once', (tester) async {
    final picked = <String>[];
    await _pumpLauncher(
      tester,
      actions: [
        PlusLauncherAction(
            icon: Icons.send, label: 'Send', onTap: () => picked.add('Send')),
        PlusLauncherAction(
            icon: Icons.qr_code,
            label: 'Receive',
            onTap: () => picked.add('Receive')),
        PlusLauncherAction(
            icon: Icons.add_card,
            label: 'Add Cash',
            onTap: () => picked.add('Add Cash')),
        PlusLauncherAction(
            icon: Icons.money_off,
            label: 'Withdraw',
            onTap: () => picked.add('Withdraw')),
      ],
    );

    // The nav band's + calls controller.open() — the exact signal under
    // test.
    _lastController!.open();
    await tester.pumpAndSettle();

    // All four actions visible — Send / Receive / Add Cash / Withdraw.
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);
    expect(find.text('Add Cash'), findsOneWidget);
    expect(find.text('Withdraw'), findsOneWidget);

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(picked, ['Send'], reason: 'exactly one pick, exactly once');
    expect(find.text('Withdraw'), findsNothing,
        reason: 'picking closes the launcher');
  });

  testWidgets('dismissal: tapping the de-emphasized background closes '
      'without picking', (tester) async {
    final picked = <String>[];
    await _pumpLauncher(
      tester,
      actions: [
        PlusLauncherAction(
            icon: Icons.send, label: 'Send', onTap: () => picked.add('Send')),
      ],
    );
    _lastController!.open();
    await tester.pumpAndSettle();

    // Tap the scrim (top of the screen — no action sits there).
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(picked, isEmpty);
    expect(find.text('Send'), findsNothing);
  });

  testWidgets('reduced motion: actions appear immediately, gesture '
      'semantics unchanged', (tester) async {
    final picked = <String>[];
    await _pumpLauncher(
      tester,
      reducedMotion: true,
      actions: [
        PlusLauncherAction(
            icon: Icons.send, label: 'Send', onTap: () => picked.add('Send')),
      ],
    );

    _lastController!.open();
    // ONE pump: reduced motion means no entrance traversal.
    await tester.pump();
    expect(find.text('Send'), findsOneWidget);

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(picked, ['Send']);
  });
  group('CORRECTION G — launcher geometry', () {
    testWidgets('the cluster sits on the plus/right side, not the '
        'opposite edge of the screen', (tester) async {
      await _pumpShell(tester, actions: [
        PlusLauncherAction(icon: Icons.send, label: 'Send', onTap: () {}),
        PlusLauncherAction(
            icon: Icons.qr_code, label: 'Receive', onTap: () {}),
      ]);
      _lastController!.open();
      await tester.pumpAndSettle();

      final screenWidth = tester.view.physicalSize.width /
          tester.view.devicePixelRatio;
      final sendRect = tester.getRect(find.text('Send'));
      // The row's own right edge, not merely its left — the whole block
      // must land in the right half of a 400-wide viewport, close to
      // where the physical + lives.
      expect(sendRect.right, greaterThan(screenWidth / 2),
          reason: 'action rows must render on the plus/right side, not '
              'drift to the opposite side of the screen');
    });

    testWidgets('the cluster right edge stays inside the viewport',
        (tester) async {
      await _pumpShell(tester, actions: [
        PlusLauncherAction(icon: Icons.send, label: 'Send', onTap: () {}),
      ]);
      _lastController!.open();
      await tester.pumpAndSettle();

      final screenWidth = tester.view.physicalSize.width /
          tester.view.devicePixelRatio;
      final sendRect = tester.getRect(find.text('Send'));
      expect(sendRect.right, lessThanOrEqualTo(screenWidth));
    });

    testWidgets('a short label and a long label share the same right '
        'edge — the cluster is not a full-width column', (tester) async {
      await _pumpShell(tester, actions: [
        PlusLauncherAction(icon: Icons.send, label: 'Go', onTap: () {}),
        PlusLauncherAction(
            icon: Icons.qr_code,
            label: 'Add Cash',
            onTap: () {}),
      ]);
      _lastController!.open();
      await tester.pumpAndSettle();

      final screenWidth = tester.view.physicalSize.width /
          tester.view.devicePixelRatio;
      final shortRowRight =
          tester.getRect(find.ancestor(
              of: find.text('Go'),
              matching: find.byType(Row))).right;
      final longRowRight =
          tester.getRect(find.ancestor(
              of: find.text('Add Cash'),
              matching: find.byType(Row))).right;

      // Shared trailing edge — the defining proof the cluster is bounded
      // intrinsic-width, right-aligned, not a stretched full-width mass.
      expect((shortRowRight - longRowRight).abs(), lessThan(1.0));
      // And it does not become a full-width column: the short row's own
      // LEFT edge sits well inside the right half of the screen, not at
      // the viewport's left edge.
      final shortRowLeft =
          tester.getRect(find.ancestor(
              of: find.text('Go'),
              matching: find.byType(Row))).left;
      expect(shortRowLeft, greaterThan(screenWidth / 2));
    });

    testWidgets('the cluster remains anchored above the plus on a '
        'narrow phone width', (tester) async {
      await _pumpShell(
        tester,
        size: const Size(360, 800),
        actions: [
          PlusLauncherAction(icon: Icons.send, label: 'Send', onTap: () {}),
          PlusLauncherAction(
              icon: Icons.qr_code, label: 'Receive', onTap: () {}),
        ],
      );
      _lastController!.open();
      await tester.pumpAndSettle();

      final plusRect = tester.getRect(find.byType(PlusLauncherTrigger));
      final receiveRect = tester.getRect(find.text('Receive'));
      // The cluster's bottom-most row sits above the plus's vertical
      // position, and does not drift far horizontally from it.
      expect(receiveRect.bottom, lessThanOrEqualTo(plusRect.top + 1));
      expect((receiveRect.right - plusRect.right).abs(), lessThan(100.0));
    });

    testWidgets('§5A — text LEFT, icon RIGHT: the icon closes each row on '
        'the shared trailing edge', (tester) async {
      await _pumpShell(tester, actions: [
        PlusLauncherAction(icon: Icons.send, label: 'Send', onTap: () {}),
        PlusLauncherAction(
            icon: Icons.qr_code, label: 'Withdraw', onTap: () {}),
      ]);
      _lastController!.open();
      await tester.pumpAndSettle();

      const rowIcons = {'Send': Icons.send, 'Withdraw': Icons.qr_code};
      for (final label in ['Send', 'Withdraw']) {
        final textRect = tester.getRect(find.text(label));
        final row = find.ancestor(
            of: find.text(label), matching: find.byType(Row));
        final iconRect = tester.getRect(
            find.descendant(of: row, matching: find.byIcon(rowIcons[label]!)).first);
        // The label ends BEFORE its icon begins — text left, icon right.
        expect(textRect.right, lessThanOrEqualTo(iconRect.left),
            reason: 'label "$label" must sit LEFT of its icon');
      }
    });

    testWidgets('§5B — the + keeps the explicit outer right inset, never '
        'flush against the screen edge', (tester) async {
      await _pumpShell(tester, actions: [
        PlusLauncherAction(icon: Icons.send, label: 'Send', onTap: () {}),
      ]);
      _lastController!.open();
      await tester.pumpAndSettle();

      final screenWidth = tester.view.physicalSize.width /
          tester.view.devicePixelRatio;
      final plusRect = tester.getRect(find.byType(PlusLauncherTrigger));
      // The named geometry token — same value as the pill's rest lateral
      // inset, so the bottom control system is symmetric and stable.
      expect(screenWidth - plusRect.right,
          closeTo(NavScrollCompression.outerRightInset, 0.5),
          reason: 'the + must sit one deliberate outer inset inside the '
              'screen edge, not flush at the viewport');
    });

    testWidgets('opening and closing preserves the same anchor',
        (tester) async {
      await _pumpShell(tester, actions: [
        PlusLauncherAction(icon: Icons.send, label: 'Send', onTap: () {}),
      ]);

      _lastController!.open();
      await tester.pumpAndSettle();
      final firstOpenRect = tester.getRect(find.text('Send'));

      _lastController!.close();
      await tester.pumpAndSettle();
      expect(find.text('Send'), findsNothing);

      _lastController!.open();
      await tester.pumpAndSettle();
      final secondOpenRect = tester.getRect(find.text('Send'));

      expect(secondOpenRect, firstOpenRect);
    });
  });
}
