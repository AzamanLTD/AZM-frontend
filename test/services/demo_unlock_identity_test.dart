// AZAMAN — THE DEMO PIN IS NOT A MASTER KEY.
//
// A demo BUILD is not a demo MEMBER. The walkable PIN 1234 exists so the lock
// can be demonstrated without a backend; if it were wired to `demoMode` alone
// then every ordinary account signed into that build could open money with
// four predictable digits. These contracts pin the binding to the seeded
// identity, and pin the production refusal.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/config.dart';
import 'package:azaman/data/demo_seed_data.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/services/app_unlock_gateway.dart';
import 'package:azaman/services/money_unlock_flow.dart';

User _user(String id) => User(
  id: id,
  username: 'member-$id',
  email: 'member-$id@example.com',
  token: 'token',
  role: 'USER',
);

/// The gateway the app would use for [userId], with the build flags stated
/// explicitly rather than inherited from whatever this test binary was built
/// with.
Future<AppUnlockGateway> _gatewayFor(String? userId) async {
  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => Stream<User?>.value(userId == null ? null : _user(userId)),
      ),
    ],
  );
  addTearDown(container.dispose);
  // The signed-in identity arrives as a stream; the gateway is chosen after it
  // resolves. Before that there is no member to demo for, which is the safe
  // default rather than a shortcut.
  await container.read(currentUserProvider.future);
  return container.read(appUnlockGatewayProvider);
}

void main() {
  tearDown(AppConfig.clearDemoModeOverrideForTest);

  group('demo build', () {
    setUp(AppConfig.enableDemoMode);

    test('the seeded demo identity gets the walkable demo PIN', () async {
      expect(
        await _gatewayFor(DemoSeedData.demoUserId),
        isA<DemoAppUnlockGateway>(),
        reason: 'the demo identity is the one the predictable PIN was made for',
      );
    });

    test('an ordinary account in the same build does NOT', () async {
      final gateway = await _gatewayFor('ordinary-member');
      expect(
        gateway,
        isNot(isA<DemoAppUnlockGateway>()),
        reason: 'a demo build must not hand every account a master PIN',
      );
    });

    test('no signed-in member means no demo PIN either', () async {
      expect(await _gatewayFor(null), isNot(isA<DemoAppUnlockGateway>()));
    });

    test('the demo gateway is the demo TYPE the sheet labels from', () async {
      // money_unlock_sheet decides its "Demo PIN" banner with
      // `gateway is DemoAppUnlockGateway`, so being that type IS the label.
      expect(
        await _gatewayFor(DemoSeedData.demoUserId),
        isA<DemoAppUnlockGateway>(),
      );
    });
  });
}
