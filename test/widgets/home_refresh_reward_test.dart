// NEW-D — AzRefreshReward tests.
//
// Pins the §G.8 reward semantics (and §H.7's receipt-not-summons rule):
// the second haptic fires ONLY when a trusted balance actually increased
// across the refresh. Equality is not a reward ("nothing changed" is a
// receipt, not a celebration), and a comparison that cannot be made
// honestly (null on either side) gives no reward at all.
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/home/az_refresh_reward.dart';

void main() {
  group('AzRefreshReward.landed', () {
    test('a real increase is a reward', () {
      expect(AzRefreshReward.landed(before: 100, after: 250), isTrue);
    });

    test('a fraction of a unit still counts — money is money', () {
      expect(AzRefreshReward.landed(before: 100, after: 100.01), isTrue);
    });

    test('equality is NOT a reward — same balance means nothing changed', () {
      expect(AzRefreshReward.landed(before: 100, after: 100), isFalse);
    });

    test('a decrease is not a reward', () {
      expect(AzRefreshReward.landed(before: 250, after: 100), isFalse);
    });

    test('null before: no honest comparison, no reward', () {
      expect(AzRefreshReward.landed(before: null, after: 250), isFalse);
    });

    test('null after: no honest comparison, no reward', () {
      expect(AzRefreshReward.landed(before: 100, after: null), isFalse);
    });

    test('both null: no reward', () {
      expect(AzRefreshReward.landed(before: null, after: null), isFalse);
    });
  });
}
