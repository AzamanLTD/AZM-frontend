import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/widgets/dual_currency_text.dart';

void main() {
  group('formatGhsEquivalent', () {
    test('formats a live GHS equivalent from a positive rate', () {
      expect(formatGhsEquivalent(10, 12.34), 'GH₵ 123.40');
    });

    test('does not fabricate a zero GHS value when the rate is unavailable', () {
      expect(formatGhsEquivalent(10, 0), 'GHS unavailable');
      expect(formatGhsEquivalent(10, -1), 'GHS unavailable');
    });

    test('rejects non-finite rates', () {
      expect(formatGhsEquivalent(10, double.nan), 'GHS unavailable');
      expect(formatGhsEquivalent(10, double.infinity), 'GHS unavailable');
    });
  });
}
