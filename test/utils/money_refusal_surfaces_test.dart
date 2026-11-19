// WP-L closure — the SURFACE helper every money screen calls.
//
// These assert the two things a money surface must never get wrong:
//   1. A proven backend refusal renders its exact, specific copy.
//   2. Anything unproven renders a sentence that claims NOTHING about the
//      money — never a failure, never a retry invite.
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/utils/money_refusal_copy.dart';

class _Coded implements Exception {
  _Coded(this.code);
  final String code;
}

class _Bare implements Exception {
  const _Bare();
}

void main() {
  group('safeMoneyErrorText', () {
    test('proven refusal renders the authority copy, not the fallback', () {
      final text = safeMoneyErrorText(
        _Coded('IDEMPOTENCY_IN_PROGRESS'),
        unknownFallback: 'fallback',
      );
      expect(text, contains('still being processed'));
      expect(text, isNot(contains('fallback')));
    });

    test('insufficient funds renders the exact pre-economic copy', () {
      final text = safeMoneyErrorText(
        _Coded('INSUFFICIENT_FUNDS'),
        unknownFallback: 'fallback',
      );
      expect(text, contains('nothing was moved'));
    });

    test('a bare exception never leaks toString() and never claims failure', () {
      final text = safeMoneyErrorText(
        const _Bare(),
        unknownFallback: unconfirmedMoneyOutcomeText(),
      );
      expect(text, unconfirmedMoneyOutcomeText());
      expect(text.toLowerCase(), isNot(contains('failed')));
      expect(text, contains('could not confirm'));
    });

    test('the default unknown sentence invites checking, not repeating', () {
      final text = unconfirmedMoneyOutcomeText();
      expect(text, contains('Check Activity'));
      expect(text.toLowerCase(), isNot(contains('try again now')));
    });

    test('a JSON code inside an error string is still proven', () {
      final text = safeMoneyErrorText(
        Exception('ApiException: {"success":false,"code":"TOTP_INVALID"}'),
        unknownFallback: 'fallback',
      );
      expect(text, contains('authenticator code is not valid'));
    });
  });
}
