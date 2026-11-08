// test/presence/nearby_presence_card_test.dart
// =============================================================================
// AZAMAN — NEARBY HOME CARD (Part 6.6 §F acceptance)
//
// Proves the visibility ladder, and that inserting card 0 is purely additive:
// the deck's measurement constant is untouched.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/config.dart';
import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/providers/presence_preferences_provider.dart';
import 'package:azaman/widgets/home/home_reminder_deck.dart';
import 'package:azaman/widgets/home/nearby_presence_card.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.setPresenceOverrideForTest(null);
  });
  tearDown(() => AppConfig.setPresenceOverrideForTest(null));

  /// Pumps a Consumer that evaluates the card builder and captures the result.
  Future<HomeReminderCardData?> capture(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    HomeReminderCardData? card;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                card = nearbyPresenceCard(ref, context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    return card;
  }

  ProviderContainer makeContainer() => ProviderContainer();

  testWidgets('flag OFF ⇒ no card at all', (tester) async {
    final c = makeContainer();
    addTearDown(c.dispose);
    AppConfig.setPresenceOverrideForTest(false);
    expect(await capture(tester, c), isNull);
  });

  testWidgets('locked app ⇒ no card above the lock surface', (tester) async {
    final c = makeContainer();
    addTearDown(c.dispose);
    AppConfig.setPresenceOverrideForTest(true);
    // MoneyAccessController starts locked.
    expect(c.read(moneyAccessProvider).isLocked, isTrue);
    expect(await capture(tester, c), isNull);
  });

  testWidgets('unlocked + discovery OFF ⇒ the entry card only', (tester) async {
    final c = makeContainer();
    addTearDown(c.dispose);
    AppConfig.setPresenceOverrideForTest(true);
    final money = c.read(moneyAccessProvider);
    money.finishUnlock(money.beginUnlock());
    await c
        .read(presencePreferencesProvider.notifier)
        .setNearbyDiscovery(false);

    final card = await capture(tester, c);
    expect(card, isNotNull);
    expect(card!.id, 'nearby-discover');
    expect(card.title, 'Find stores near you');
    // The entry card leads to preferences, never a storefront.
  });

  testWidgets('all three preferences start OFF', (tester) async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final p = c.read(presencePreferencesProvider);
    expect(p.nearbyDiscovery, isFalse);
    expect(p.presenceNotifications, isFalse);
    expect(p.personalisation, isFalse);
  });

  test('deck measurement constant is unchanged', () {
    expect(HomeReminderDeck.bandCap, 344);
  });
}
