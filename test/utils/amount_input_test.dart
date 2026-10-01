// =============================================================================
// ADD CASH REDESIGN — GROUP B (amount state machine) + mapping sanity.
//
// The keypad's invalid-state rules are enforced by ONE pure function,
// AmountInput.applyKey. These tests exercise every rule without pumping a
// widget — the widget tests then only need to prove the wiring.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/utils/amount_input.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/widgets/momo_network.dart';

void main() {
  group('AmountInput.applyKey — decimal rules', () {
    test('empty input renders as 0 and has no value', () {
      expect(AmountInput.display(''), '0');
      expect(AmountInput.value(''), isNull);
    });

    test('digits accumulate normally', () {
      var raw = '';
      for (final k in ['1', '2', '4', '0']) {
        raw = AmountInput.applyKey(raw, k);
      }
      expect(raw, '1240');
      expect(AmountInput.value(raw), 1240);
      expect(AmountInput.display(raw), '1,240');
    });

    test('only one decimal point can exist', () {
      var raw = '';
      raw = AmountInput.applyKey(raw, '.');
      expect(raw, '0.');
      raw = AmountInput.applyKey(raw, '.'); // second '.' is a no-op
      expect(raw, '0.');
      raw = AmountInput.applyKey(raw, '5');
      raw = AmountInput.applyKey(raw, '.'); // still a no-op after digits
      expect(raw, '0.5');
    });

    test('fraction is capped at two digits (pesewas)', () {
      var raw = '';
      for (final k in ['1', '2', '.', '3', '4']) {
        raw = AmountInput.applyKey(raw, k);
      }
      expect(raw, '12.34');
      expect(
        raw,
        AmountInput.applyKey(raw, '5'),
      ); // third fractional digit — no-op
      expect(AmountInput.display(raw), '12.34');
    });

    test('typed fraction is preserved unpadded ("12.3" not "12.30")', () {
      var raw = '';
      for (final k in ['1', '2', '.', '3']) {
        raw = AmountInput.applyKey(raw, k);
      }
      expect(AmountInput.display(raw), '12.3');
    });

    test('leading zero is replaced, never "05"', () {
      var raw = '';
      raw = AmountInput.applyKey(raw, '0');
      expect(raw, '0');
      raw = AmountInput.applyKey(raw, '5');
      expect(raw, '5'); // '05' would be a leading-zero buildup
      expect(AmountInput.value(raw), 5);
      raw = AmountInput.applyKey(raw, '0');
      expect(raw, '50'); // '50', never '050'
    });

    test('trailing "." still has a value ("12." is 12)', () {
      var raw = '';
      for (final k in ['1', '2', '.']) {
        raw = AmountInput.applyKey(raw, k);
      }
      expect(raw, '12.');
      expect(AmountInput.value(raw), 12);
      expect(AmountInput.display(raw), '12.'); // the typed dot stays visible
    });

    test('backspace deletes from the right, down to empty', () {
      var raw = '';
      for (final k in ['9', '.', '9']) {
        raw = AmountInput.applyKey(raw, k);
      }
      expect(raw, '9.9');
      raw = AmountInput.applyKey(raw, 'del');
      expect(raw, '9.');
      raw = AmountInput.applyKey(raw, 'del');
      expect(raw, '9');
      raw = AmountInput.applyKey(raw, 'del');
      expect(raw, '');
      expect(raw, AmountInput.applyKey(raw, 'del')); // del on empty — no-op
      expect(AmountInput.display(''), '0');
    });

    test('integer digits are capped at seven (GH₵ 9,999,999.99 max)', () {
      var raw = '';
      for (var i = 0; i < 10; i++) {
        raw = AmountInput.applyKey(raw, '9');
      }
      expect(raw, '9999999');
      expect(AmountInput.display(raw), '9,999,999');
    });

    test('"0." accepts zero before the point but value stays null at 0.00', () {
      var raw = '';
      for (final k in ['0', '.', '0']) {
        raw = AmountInput.applyKey(raw, k);
      }
      expect(raw, '0.0');
      expect(AmountInput.value(raw), isNull); // zero is not an amount
    });

    test('non-digit non-special keys are no-ops (defensive)', () {
      expect(AmountInput.applyKey('', 'x'), '');
      expect(AmountInput.applyKey('12', 'x'), '12');
    });
  });

  group('AmountInput.display — grouping', () {
    test('groups thousands with commas', () {
      var raw = '';
      for (final k in ['1', '2', '3', '4', '5', '6', '7']) {
        raw = AmountInput.applyKey(raw, k);
      }
      expect(AmountInput.display(raw), '1,234,567');
    });

    test('display never pads the fraction the user has not typed', () {
      expect(AmountInput.display('500'), '500');
      expect(AmountInput.display('50.5'), '50.5');
      expect(AmountInput.display('50.50'), '50.50');
    });
  });

  group('MomoNetwork — central provider identity', () {
    test('canonical providers map to their brands', () {
      expect(MomoNetwork.of('MTN').code, 'MTN');
      expect(MomoNetwork.of('TELECEL').code, 'TEL');
      expect(MomoNetwork.of('AIRTELTIGO').code, 'AT');
    });

    test('backend enum values map to the same identities', () {
      expect(MomoNetwork.of('MTN_MOMO').id, 'MTN');
      expect(MomoNetwork.of('TELECEL_CASH').id, 'TELECEL');
      expect(MomoNetwork.of('AIRTELTIGO').id, 'AIRTELTIGO');
    });

    test('legacy VODAFONE values present as TELECEL everywhere', () {
      expect(MomoNetwork.of('VODAFONE').id, 'TELECEL');
      expect(MomoNetwork.of('VODAFONE_CASH').id, 'TELECEL');
      expect(MomoNetwork.of('VODAFONE').color, MomoNetwork.of('TELECEL').color);
    });

    test('every network gets its own AIRTELTIGO treatment (the old screens '
        'shipped none)', () {
      expect(MomoNetwork.of('AIRTELTIGO').color, const Color(0xFFD62828));
      expect(MomoNetwork.of('AIRTELTIGO').isKnown, isTrue);
    });

    test('unknown providers render neutrally, never as a wrong brand', () {
      final info = MomoNetwork.of('GLO');
      expect(info.isKnown, isFalse);
      expect(info.code, 'MM');
    });

    test('provider colors are consistent with the shipped withdrawal pick', () {
      // The two surfaces that already shipped AIRTELTIGO used these exact
      // values; the central mapping standardises on them.
      expect(MomoNetwork.of('MTN').color, const Color(0xFFFFCC00));
      expect(MomoNetwork.of('TELECEL').color, const Color(0xFFE60000));
      expect(MomoNetwork.of('AIRTELTIGO').color, const Color(0xFFD62828));
    });
  });

  group('MomoNetwork.formatPhone — Ghana mobile presentation', () {
    test('E.164 becomes 3-3-4 local grouping', () {
      expect(MomoNetwork.formatPhone('+233244123456'), '024 412 3456');
      expect(MomoNetwork.formatPhone('+233500987654'), '050 098 7654');
    });

    test('already-local numbers regroup', () {
      expect(MomoNetwork.formatPhone('0244123456'), '024 412 3456');
    });

    test('bare-233 forms normalise to local', () {
      expect(MomoNetwork.formatPhone('233244123456'), '024 412 3456');
    });

    test('unrecognised shapes are shown honestly, never invented', () {
      expect(MomoNetwork.formatPhone('024'), '024');
      expect(MomoNetwork.formatPhone('abc'), 'abc');
      expect(MomoNetwork.formatPhone(''), '');
    });
  });

  group('AzMoney integration (odometer feed)', () {
    test('the exact strings the odometer renders for typed amounts', () {
      expect(AzMoney.ghs(50), 'GH₵${AzMoney.nbsp}50.00');
      expect(AzMoney.amount(50, decimals: 0), '50');
    });
  });
}
