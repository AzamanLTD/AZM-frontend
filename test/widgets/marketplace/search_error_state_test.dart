// =============================================================================
// MARKETPLACE LIST — honest failure vs. legitimate empty (Workstream F).
//
// A DEAD search request used to render as "No businesses found / Be the
// first to register here" — a failed request masquerading as an empty
// result, with no retry. These tests pin the retired contract at the
// screen level:
//   • a failed search (error set, zero results) shows the FAILURE state,
//     never the empty-state texts; Retry re-fires the real search
//   • a successful search with zero results keeps the legitimate
//     "No businesses found" empty state, no Retry, no failure glyph
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/services/business_service.dart';

/// Sets the HONEST failure state exactly the way the real notifier does
/// after a network/server error: isLoading cleared, error recorded, no
/// results. Counts calls so Retry observability is real.
class _FailingSearchNotifier extends BusinessSearchNotifier {
  _FailingSearchNotifier() : super(BusinessService());

  int calls = 0;

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {
    calls++;
    state = state.copyWith(isLoading: false, error: 'SocketException: dead');
  }
}

/// A search that succeeds with zero results — the LEGITIMATE empty case.
class _EmptySearchNotifier extends BusinessSearchNotifier {
  _EmptySearchNotifier() : super(BusinessService());

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {
    state = state.copyWith(isLoading: false, clearError: true);
  }
}

Future<void> _pumpHome(WidgetTester tester, BusinessSearchNotifier notifier) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [businessSearchProvider.overrideWith((ref) => notifier)],
      child: const MaterialApp(home: MarketplaceHomeScreen()),
    ),
  );
  // Flush the init post-frame search + any animations.
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('failure: dead search shows the failure state, never the empty lie', (tester) async {
    final notifier = _FailingSearchNotifier();
    await _pumpHome(tester, notifier);

    expect(find.byKey(const Key('marketplace-search-failure')), findsOneWidget);
    expect(find.text("Couldn't load businesses"), findsOneWidget);
    expect(find.text('No businesses found'), findsNothing,
        reason: 'a failed request must never read as a zero-result success');
    expect(find.text('Be the first to register here'), findsNothing);
  });

  testWidgets('failure: Retry re-fires the real search', (tester) async {
    final notifier = _FailingSearchNotifier();
    await _pumpHome(tester, notifier);
    final before = notifier.calls;

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(notifier.calls, before + 1);
  });

  testWidgets('empty: successful zero-result search keeps the honest empty state', (tester) async {
    await _pumpHome(tester, _EmptySearchNotifier());

    expect(find.byKey(const Key('marketplace-search-failure')), findsNothing);
    expect(find.text('No businesses found'), findsOneWidget);
    expect(find.text("Couldn't load businesses"), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });
}
