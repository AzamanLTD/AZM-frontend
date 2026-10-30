// MONEY IN A CHAT IS STILL MONEY.
//
// A transfer bubble carries the amount, a payment reference and — for an
// inbound request — an "Accept & Pay" control. It was the one money surface the
// gate did not reach, which meant a locked member could read a payment amount
// from a conversation and, worse, pay a request straight out of the bubble.
//
// Now: masked while locked (not dimmed — replaced, and excluded from
// semantics), the figures return on unlock, and Accept & Pay refuses instead of
// starting a payment.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/chat_money_card.dart';

import '../support/money_access_test_support.dart';

class _Counters {
  int accepted = 0;
  int declined = 0;
}

Future<_Counters> _pump(
  WidgetTester tester, {
  required bool unlocked,
  required bool asRequest,
}) async {
  final counters = _Counters();
  await tester.binding.setSurfaceSize(const Size(390, 700));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [if (unlocked) unlockedMoneyAccess()],
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: Scaffold(
          body: Center(
            child: ChatMoneyCard(
              amount: 1842.5,
              currency: 'GHS',
              isMe: false,
              contactName: 'Kwame',
              // An inbound REQUEST sits in 'pending' — that is the state whose
              // Accept & Pay control the gate has to refuse.
              status: asRequest ? 'pending' : 'completed',
              isRequest: asRequest,
              reference: '#TXN-99120',
              memo: 'For the logo work',
              timestamp: DateTime(2026, 10, 30),
              onAccept: asRequest ? () => counters.accepted++ : null,
              onDecline: asRequest ? () => counters.declined++ : null,
            ),
          ),
        ),
      ),
    ),
  );
  // The card runs a looping sheen, so every wait here is bounded: pumpAndSettle
  // would wait for an animation that never ends.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return counters;
}

void main() {
  testWidgets('locked: the amount and reference are masked', (tester) async {
    await _pump(tester, unlocked: false, asRequest: false);

    expect(find.textContaining('1,842'), findsNothing);
    expect(find.textContaining('1842'), findsNothing);
    expect(find.textContaining('#TXN'), findsNothing);

    // The conversation itself stays readable.
    expect(find.textContaining('For the logo work'), findsOneWidget);
  });

  testWidgets('locked: masked figures stay out of semantics', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, unlocked: false, asRequest: false);

    final labels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((s) => s.properties.label ?? '')
        .join(' ');
    expect(labels.contains('1,842'), isFalse);
    expect(labels.contains('1842'), isFalse);
    handle.dispose();
  });

  testWidgets('locked: Accept & Pay does not start a payment', (tester) async {
    final counters = await _pump(tester, unlocked: false, asRequest: true);

    await tester.tap(find.text('Accept & Pay'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      counters.accepted,
      0,
      reason: 'a refusal must never reach the payment callback',
    );
    expect(find.byType(ChatMoneyCard), findsOneWidget);
  });

  testWidgets('locked: Decline is refused too', (tester) async {
    final counters = await _pump(tester, unlocked: false, asRequest: true);

    await tester.tap(find.text('Decline'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(counters.declined, 0);
  });

  testWidgets('unlocked: Accept & Pay still reaches the callback', (
    tester,
  ) async {
    final counters = await _pump(tester, unlocked: true, asRequest: true);

    await tester.tap(find.text('Accept & Pay'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(counters.accepted, 1);
  });

  testWidgets('unlocked: the real figures come back', (tester) async {
    await _pump(tester, unlocked: true, asRequest: false);

    expect(find.textContaining('1,842'), findsWidgets);
    expect(find.textContaining('#TXN'), findsOneWidget);
    expect(find.textContaining('••••'), findsNothing);
  });
}
