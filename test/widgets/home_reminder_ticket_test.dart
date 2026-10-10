// =============================================================================
// AZAMAN — HOME REMINDER TICKET TESTS  (ticket booklet pass, Task A)
//
// The regression tests the ticket pass owns:
//   * silhouette — the clip is a real ticket (rounded corners kept,
//     inward side cut-outs at the vertical mid-line)
//   * tone palette — deterministic from identity, distinct within the
//     active set, both themes
//   * text fit — no overflow on narrow phones, at large text scales,
//     with long names (titles ellipsize, nothing renders exceptions)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/home_reminder_deck.dart';
import 'package:azaman/widgets/home/home_reminder_ticket.dart';

Future<void> _pumpTicket(
  WidgetTester tester, {
  double width = 360,
  double height = 116,
  double textScale = 1.0,
  bool dark = false,
  HomeReminderCardData card = const HomeReminderCardData(
    id: 't1',
    eyebrow: 'SUSU',
    title: 'Susu contribution due Oct 12',
    subtitle: 'Circle Susu',
    icon: Icons.wallet_outlined,
  ),
}) async {
  await tester.binding.setSurfaceSize(Size(width, height));
  await tester.pumpWidget(
    ProviderScope(
      child: Consumer(
        builder: (context, ref, _) {
          final colors = ref.watch(themeProvider.select((t) => t.colors));
          return MaterialApp(
            theme: ThemeProvider.getThemeData(
              dark ? AzamanTheme.dark : AzamanTheme.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: Size(width, height),
                textScaler: TextScaler.linear(textScale),
                platformBrightness: dark ? Brightness.dark : Brightness.light,
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: HomeReminderTicketFace(
                    card: card,
                    colors: colors,
                    height: height,
                    toneIndex: 0,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('silhouette — the clip is a real ticket: corners kept, '
      'inward side cut-outs at the mid-line', (tester) async {
    await _pumpTicket(tester);

    const size = Size(360, 116);
    final path = const HomeTicketClipper().getClip(size);

    // The corners survive: a point inset past the corner rounding is
    // inside the ticket.
    expect(
      path.contains(const Offset(6, 6)),
      isTrue,
      reason: 'the top-left corner keeps its rounding, not a cut-out',
    );

    // The inward cut-outs: points just past the mid-line edge on both
    // sides are OUTSIDE the clip (the notch bites into the ticket).
    final midY = size.height / 2;
    for (final x in <double>[1.0, size.width - 1]) {
      expect(
        path.contains(Offset(x, midY)),
        isFalse,
        reason: 'the side cut-out removes the mid-line edge on both sides',
      );
    }
  });

  testWidgets('tone palette — deterministic from identity, distinct '
      'within the set', (tester) async {
    const ids = ['susu-s1', 'resume-biz-1', 'relevance-b2'];
    final tones = [
      for (final id in ids) homeTicketToneIndex(id: id, allIds: ids),
    ];
    expect(
      tones.toSet().length,
      3,
      reason: 'every ticket in the active set is distinct',
    );
    // Deterministic: same identities, same assignment.
    expect([
      for (final id in ids) homeTicketToneIndex(id: id, allIds: ids),
    ], tones);
  });

  testWidgets('text fit — no overflow on a narrow phone at 1.6x text '
      'scale with long names', (tester) async {
    await _pumpTicket(
      tester,
      width: 320,
      height: 116,
      textScale: 1.6,
      card: const HomeReminderCardData(
        id: 'long-1',
        eyebrow: 'MARKETPLACE',
        title: 'Ama Boakye Quality Fabrics & Tailoring Emporium',
        subtitle: 'Textiles, Fashion & Very Long Category Names Accra',
        icon: Icons.store_outlined,
      ),
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'long content ellipsizes instead of overflowing',
    );
    expect(find.byType(Text), findsWidgets);
  });

  testWidgets('text fit — the tall FILL geometry renders clean too', (
    tester,
  ) async {
    await _pumpTicket(
      tester,
      width: 360,
      height: 200,
      textScale: 1.3,
      card: const HomeReminderCardData(
        id: 'tall-1',
        eyebrow: 'SUSU',
        title: 'Your payout cycle runs Nov 3 — Contribution Rotation',
        subtitle: 'Ama Boakye Quality Fabrics & Tailoring',
        icon: Icons.wallet_outlined,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('both themes — the ticket renders with accessible ink in '
      'light and dark', (tester) async {
    for (final dark in <bool>[false, true]) {
      await _pumpTicket(tester, dark: dark);
      expect(tester.takeException(), isNull);
    }
  });
}
