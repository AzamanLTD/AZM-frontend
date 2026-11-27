// The wallet withdrawal must state the payout destination type for numeric
// destinations (MoMo numbers and Binance Pay IDs look alike), and must not
// guess one for unambiguous address formats. Mirrors AZM-backend
// services/payoutDestinationClassification.js.
import 'package:azaman/screens/withdrawal_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Binance Pay saved methods are typed BINANCE_PAY_ID', () {
    expect(payoutDestinationTypeFor('BINANCE_ID'), 'BINANCE_PAY_ID');
    expect(payoutDestinationTypeFor('binance_pay_id'), 'BINANCE_PAY_ID');
  });

  test('mobile money saved methods are typed MOMO', () {
    for (final n in [
      'MOMO',
      'MTN',
      'mtn_momo',
      'TELECEL',
      'VODAFONE',
      'AIRTELTIGO',
    ]) {
      expect(payoutDestinationTypeFor(n), 'MOMO', reason: n);
    }
  });

  test('unambiguous address formats carry no guessed type', () {
    expect(payoutDestinationTypeFor('TRC20'), isNull);
    expect(payoutDestinationTypeFor('ERC20_BEP20'), isNull);
    expect(payoutDestinationTypeFor(null), isNull);
    expect(payoutDestinationTypeFor('SOMETHING_ELSE'), isNull);
  });
}
