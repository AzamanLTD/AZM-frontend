// =============================================================================
// TRANSACTION HISTORY — Ghana-first row presentation (Stage 1 §4C).
//
// The row's PRIMARY amount follows the global display preference:
//   • GHS preferred (the default) → the recorded GH₵ amount is primary and
//     the recorded USDC amount rides the secondary line.
//   • USDC preferred (deliberate) → the hierarchy flips.
//
// Both values are RECORDED at initiation (amountUsdc, metadata.amountGhs,
// rateAtInitiation) — the presentation NEVER converts with today's rate,
// so a historical transaction can never be misread as today's equivalent.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/currency_model.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/screens/transaction_history_screen.dart';

/// One recorded fiat deposit: GH₵ 150.00 in / 10.00 USDC out, at a recorded
/// rate of 15.0 — the amounts are historical fact, not live conversions.
TransactionRecord _recordedDeposit() => TransactionRecord(
      id: 'txn_recorded_deposit',
      rawType: 'DEPOSIT_FIAT',
      amountUsdc: 10.0,
      feeUsdc: 0,
      status: 'COMPLETED',
      createdAt: DateTime(2026, 10, 1),
      metadata: {
        'provider': 'MTN',
        'amountGhs': 150.0,
        'rateAtInitiation': 15.0,
        'counterparty': 'Ama',
      },
    );

class _PinnedHistory extends TransactionHistoryNotifier {
  _PinnedHistory() : super() {
    // Pinned, offline state: one recorded deposit, no paging, no network.
    state = const TransactionHistoryState(
      items: [], // replaced below — const list can't embed the record
      isLoading: false,
      hasMore: false,
    );
    state = state.copyWith(items: [_recordedDeposit()]);
  }

  @override
  Future<void> loadMore() async {} // no network in this test
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHistory(
    WidgetTester tester, {
    DisplayCurrency? preference,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (preference != null) 'display_currency': preference.name,
    });
    final theme = await tester.runAsync(() async {
      final t = ThemeProvider();
      int guard = 0;
      while (!t.isLoaded && guard++ < 100) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      return t;
    });
    expect(theme!.isLoaded, isTrue);

    final container = ProviderContainer(overrides: [
      themeProvider.overrideWith((ref) => theme),
      transactionHistoryProvider.overrideWith((ref) => _PinnedHistory()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeProvider.getThemeData(theme.currentTheme),
          home: const TransactionHistoryScreen(),
        ),
      ),
    );
    // Staggered entrance animations repeat under test; settle by fixed
    // pumps rather than pumpAndSettle so the row contract is asserted.
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('GHS preference (default): the recorded GH₵ amount is the '
      'primary row figure, the recorded USDC rides the secondary line',
      (tester) async {
    await pumpHistory(tester);

    expect(find.text('+ GH₵150.00'), findsOneWidget,
        reason: 'Ghana-first: the primary figure is the recorded cedi '
            'amount when GHS is the preferred display currency');
    expect(find.textContaining('10.00 USDC'), findsOneWidget,
        reason: 'the recorded USDC value stays visible as the secondary '
            'line — both recorded truths remain on the row');
  });

  testWidgets('USDC preference (deliberate): the hierarchy flips honestly',
      (tester) async {
    await pumpHistory(tester, preference: DisplayCurrency.usdc);

    expect(find.text('+10.00 USDC'), findsOneWidget,
        reason: 'a deliberate USDC preference makes the recorded USDC '
            'amount primary');
    expect(find.textContaining('GH₵ 150.00'), findsOneWidget,
        reason: 'the recorded GHS value rides the secondary line');
  });

  testWidgets('no live conversion: the row shows the RECORDED values, '
      'never a today-rate equivalent', (tester) async {
    await pumpHistory(tester);

    // The row must carry the recorded pair exactly (150.00 GHS / 10.00
    // USDC / rate 15.0). A today-rate conversion would produce different
    // digits — its absence is the point.
    expect(find.textContaining('GH₵'), findsWidgets);
    expect(find.textContaining('150.00'), findsWidgets);
    expect(find.textContaining('10.00 USDC'), findsOneWidget);
  });
}
