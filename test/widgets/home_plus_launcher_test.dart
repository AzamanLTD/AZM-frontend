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

Future<void> _pumpLauncher(
  WidgetTester tester, {
  bool reducedMotion = false,
  required List<PlusLauncherAction> actions,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 900))
              .copyWith(disableAnimations: reducedMotion),
          child: Scaffold(
            body: PlusActionLauncher(actions: actions),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('closed: only the + trigger is alive, no actions visible',
      (tester) async {
    final picked = <String>[];
    await _pumpLauncher(
      tester,
      actions: [
        PlusLauncherAction(
            icon: Icons.send, label: 'Send', onTap: () => picked.add('Send')),
      ],
    );

    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('Send'), findsNothing);
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

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // All four actions visible — Send / Receive / Add Cash / Withdraw.
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);
    expect(find.text('Add Cash'), findsOneWidget);
    expect(find.text('Withdraw'), findsOneWidget);

    // The + is still present — now in its close role.
    expect(find.byIcon(Icons.add), findsOneWidget);

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
    await tester.tap(find.byIcon(Icons.add));
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

    await tester.tap(find.byIcon(Icons.add));
    // ONE pump: reduced motion means no entrance traversal.
    await tester.pump();
    expect(find.text('Send'), findsOneWidget);

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(picked, ['Send']);
  });
}
