// =============================================================================
// CURRENCY PREFERENCE — persistence & migration (Stage 1 §4E).
//
// Pins the display-preference lifecycle contract:
//   • fresh/unset  → GHS default, and NOTHING is written (stays fresh);
//   • a deliberately saved USDC choice persists across a full reload;
//   • legacy 'GHC' / 'usd' spellings normalize safely;
//   • unrecognized junk never silently becomes USDC — it falls back to
//     the GHS default and the poisoned value is removed.
//
// The backend mirror is best-effort (fire-and-forget) and is not asserted
// here; the local key is the single authority.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/currency_model.dart';
import 'package:azaman/models/currency_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CurrencyNotifier lifecycle', () {
    test(
      'a fresh/unset preference defaults to GHS and writes nothing',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final notifier = CurrencyNotifier();
        await notifier.ready;

        expect(
          notifier.state,
          DisplayCurrency.ghs,
          reason: 'Ghana-first: fresh users see GHS-first everywhere',
        );

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.containsKey('display_currency'),
          isFalse,
          reason:
              'a fresh default must not masquerade as a deliberate '
              'choice — nothing is persisted until the user picks',
        );
      },
    );

    test('a deliberately saved USDC choice survives a full reload', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final first = CurrencyNotifier();
      await first.ready;
      await first.set(DisplayCurrency.usdc);

      // A brand-new notifier = a cold restart reading the same store.
      final reloaded = CurrencyNotifier();
      await reloaded.ready;
      expect(
        reloaded.state,
        DisplayCurrency.usdc,
        reason: 'an explicit user choice must survive restart/reload',
      );
    });

    test('a deliberately saved GHS choice also survives reload', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final first = CurrencyNotifier();
      await first.ready;
      await first.set(DisplayCurrency.ghs);
      expect(first.state, DisplayCurrency.ghs);

      final reloaded = CurrencyNotifier();
      await reloaded.ready;
      expect(reloaded.state, DisplayCurrency.ghs);
    });

    test(
      "legacy 'GHC' spellings normalize to GHS, never become USDC",
      () async {
        // 'display_currency' was historically only ever written by an
        // explicit pick — but legacy spellings may exist. 'ghc' is the
        // obsolete cedi code and must land on GHS.
        SharedPreferences.setMockInitialValues(<String, Object>{
          'display_currency': 'ghc',
        });
        final notifier = CurrencyNotifier();
        await notifier.ready;
        expect(notifier.state, DisplayCurrency.ghs);
      },
    );

    test("legacy 'usd' spelling normalizes to the USDC preference", () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'display_currency': 'usd',
      });
      final notifier = CurrencyNotifier();
      await notifier.ready;
      expect(notifier.state, DisplayCurrency.usdc);
    });

    test('unrecognized junk never silently becomes USDC — it is removed '
        'and the GHS default applies', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'display_currency': 'GBP',
      });
      final notifier = CurrencyNotifier();
      await notifier.ready;

      expect(
        notifier.state,
        DisplayCurrency.ghs,
        reason: 'junk must fall back to the Ghana-first default',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('display_currency'),
        isNull,
        reason:
            'the poisoned value is cleaned out so it cannot '
            'resurface on a later load',
      );
    });
  });

  group('CurrencyCatalog.normalizeCode', () {
    test('maps the obsolete cedi spellings onto the canonical GHS code', () {
      expect(CurrencyCatalog.normalizeCode('GHS'), 'GHS');
      expect(CurrencyCatalog.normalizeCode('GHC'), 'GHS');
      expect(CurrencyCatalog.normalizeCode('cedis'), 'GHS');
      expect(CurrencyCatalog.normalizeCode(' ghc '), 'GHS');
      expect(CurrencyCatalog.normalizeCode('USDC'), 'USDC');
      expect(CurrencyCatalog.normalizeCode('usd'), 'USDC');
    });

    test('unknown or future assets normalize to null — never invented', () {
      expect(CurrencyCatalog.normalizeCode('BTC'), isNull);
      expect(CurrencyCatalog.normalizeCode('ETH'), isNull);
      expect(CurrencyCatalog.normalizeCode(null), isNull);
      expect(CurrencyCatalog.normalizeCode(''), isNull);
    });
  });

  test('the provider wires a single CurrencyNotifier authority', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(currencyProvider), DisplayCurrency.ghs);
  });
}
