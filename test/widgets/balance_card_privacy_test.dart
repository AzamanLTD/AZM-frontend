// THE CARD IS NEVER REPLACED — ITS FIGURES LOCK.
//
// The pure-widget half of the owner's deck requirement (2026-10-30). The Home
// suite proves the deck stays mounted inside the real Home; this suite proves
// the card itself:
//
//   • redacted: the mask paints, the real figure is never formatted, and the
//     accessibility tree carries no amount at all;
//   • redacted: turning the card over is REFUSED (the reveal is a protected
//     action) and the host's feedback fires instead — nothing is queued;
//   • unlocked: the real GH₵ headline renders and the flip works, so the
//     privacy layer changes nothing about the card's normal behaviour.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/balance_card_pair.dart';
import 'package:azaman/widgets/home/money_privacy.dart';

bool _fontsLoaded = false;

Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  await (FontLoader('Inter')..addFont(
        File(
          'assets/fonts/Inter-Variable.ttf',
        ).readAsBytes().then((b) => ByteData.view(b.buffer)),
      ))
      .load();
  _fontsLoaded = true;
}

BalanceCardValuation _funded() => const BalanceCardValuation(
  nativeGhsAvailable: 1234.56,
  availableUsdc: 80.09,
  balanceConfirmed: true,
  escrowLocked: 350,
  rate: FxRateView(ghsPerUsdc: 15.42, kind: FxRateKind.fresh),
).compute();

Future<ValueNotifier<int>> _pumpCard(
  WidgetTester tester, {
  required MoneyVisibility visibility,
}) async {
  await tester.runAsync(_loadFonts);
  final colors = ThemeProvider.getColors(AzamanTheme.light);
  await tester.binding.setSurfaceSize(const Size(390, 844));
  final blocked = ValueNotifier<int>(0);
  addTearDown(blocked.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeProvider.getThemeData(AzamanTheme.light),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 358,
              child: BalanceCardPair(
                valuation: _funded(),
                colors: colors,
                visibility: visibility,
                onBlockedInteraction: () => blocked.value++,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return blocked;
}

void _flipBySemantics(WidgetTester tester) {
  final node = tester.getSemantics(
    find.byKey(const ValueKey('balance-pair-semantics')),
  );
  tester.binding.pipelineOwner.semanticsOwner!.performAction(
    node.id,
    SemanticsAction.tap,
  );
}

void main() {
  testWidgets('redacted: the mask paints and the figure is not formatted', (
    tester,
  ) async {
    await _pumpCard(tester, visibility: MoneyVisibility.redacted);

    expect(find.text(kRedactedMoney), findsWidgets);
    expect(
      find.textContaining('1,234.56'),
      findsNothing,
      reason: 'the real balance is never built while locked',
    );
    // The card is still a card: frame, artwork and chip all remain.
    expect(find.byKey(const ValueKey('balance-pair-frame')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('balance-pair-front-surface')),
      findsOneWidget,
    );
  });

  testWidgets('redacted: no amount reaches the accessibility tree', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpCard(tester, visibility: MoneyVisibility.redacted);

    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('balance-pair-semantics')))
          .label,
      'Balance card — locked',
    );
    expect(
      find.bySemanticsLabel(RegExp('1,234')),
      findsNothing,
      reason: 'a locked card announces nothing about the money',
    );
    semantics.dispose();
  });

  testWidgets('redacted: the card refuses to turn over', (tester) async {
    final semantics = tester.ensureSemantics();
    final blocked = await _pumpCard(
      tester,
      visibility: MoneyVisibility.redacted,
    );

    _flipBySemantics(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.byKey(const ValueKey('balance-pair-back-surface')),
      findsNothing,
      reason: 'the reverse is the money breakdown — it stays closed',
    );
    expect(blocked.value, 1, reason: 'the refusal is delegated to the host');
    semantics.dispose();
  });

  testWidgets('unlocked: the real headline renders and the flip works', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpCard(tester, visibility: MoneyVisibility.visible);

    expect(find.textContaining('1,234'), findsWidgets);
    expect(find.text(kRedactedMoney), findsNothing);

    _flipBySemantics(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.byKey(const ValueKey('balance-pair-back-surface')),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
