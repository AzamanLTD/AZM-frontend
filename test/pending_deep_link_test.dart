import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/router/pending_deep_link.dart';

// Shared links live on azaman.me (Azaman does not own azaman.app), and a
// link opened while signed out is kept for after sign-in instead of lost.
void main() {
  setUp(PendingDeepLink.clearForTest);

  test('links are built on azaman.me', () {
    expect(kAzamanLinkBase, 'https://azaman.me');
  });

  test('a business, storefront or Susu invite link waits for sign-in, once', () {
    PendingDeepLink.hold(Uri.parse('https://azaman.me/business/BIZ-123'));
    expect(PendingDeepLink.take(), '/business/BIZ-123');
    expect(PendingDeepLink.take(), isNull);

    PendingDeepLink.hold(Uri.parse('/storefront/bp-1?tab=menu'));
    expect(PendingDeepLink.take(), '/storefront/bp-1?tab=menu');

    PendingDeepLink.hold(Uri.parse('/susu/invite/tok-9'));
    expect(PendingDeepLink.take(), '/susu/invite/tok-9');
  });

  test('other paths are not held', () {
    PendingDeepLink.hold(Uri.parse('/wallet/withdraw'));
    expect(PendingDeepLink.take(), isNull);
  });

  test('a referral link keeps only its code, for sign-up', () {
    PendingDeepLink.hold(Uri.parse('https://azaman.me/invite/KWESI123'));
    expect(PendingDeepLink.referralCode, 'KWESI123');
    expect(PendingDeepLink.take(), isNull);
  });
}
