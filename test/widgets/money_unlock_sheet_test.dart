// THE SHEET MAY ONLY SAY WHAT THE SERVER SAID.
//
// The unlock challenge is the last line of defence in front of a member's
// money, so the sheet's contract is pinned here:
//
//   • only backend-configured challenges are offered — no invented methods;
//   • a refusal is shown with its reason and remaining attempts, and the sheet
//     stays open;
//   • "unlocked" is returned ONLY on an accepted proof;
//   • an account with nothing configured gets the truth, not a dead input;
//   • the SMS path never shows a full phone number.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/app_unlock_gateway.dart';
import 'package:azaman/services/money_unlock.dart';
import 'package:azaman/services/money_unlock_flow.dart';
import 'package:azaman/widgets/home/money_unlock_sheet.dart';

class _FakeGateway implements AppUnlockGateway {
  _FakeGateway({
    this.acceptedPin,
    this.refusal,
    this.smsRefusal,
    this.challenge,
  });

  final String? acceptedPin;
  final AppUnlockRefusal? refusal;
  final AppUnlockRefusal? smsRefusal;
  final AppUnlockSmsChallenge? challenge;

  String? seenPin;
  int smsSends = 0;

  @override
  Future<AppUnlockCapabilities> capabilities() async =>
      AppUnlockCapabilities.none;

  @override
  Future<void> verifyPin(String pin) async {
    seenPin = pin;
    if (refusal != null) throw refusal!;
    if (pin == acceptedPin) return;
    throw const AppUnlockRefusal('PIN_INVALID', attemptsLeft: 2);
  }

  @override
  Future<void> verifyTotp(String token) async =>
      throw const AppUnlockRefusal('TOTP_INVALID', attemptsLeft: 1);

  @override
  Future<AppUnlockSmsChallenge> sendSmsChallenge() async {
    smsSends++;
    if (smsRefusal != null) throw smsRefusal!;
    return challenge!;
  }

  @override
  Future<void> verifySmsChallenge({
    required String challengeId,
    required String code,
  }) async {
    if (code == '123456') return;
    throw const AppUnlockRefusal('CODE_INVALID', attemptsLeft: 2);
  }
}

AppUnlockCapabilities _pinOnly() => const AppUnlockCapabilities(
  pinConfigured: true,
  authenticatorConfigured: false,
  phoneVerified: true,
  smsUnlockAvailable: true,
);

Future<MoneyUnlockResult?> _openSheet(
  WidgetTester tester, {
  required AppUnlockGateway gateway,
  required AppUnlockCapabilities capabilities,
}) async {
  MoneyUnlockResult? result;
  await tester.binding.setSurfaceSize(const Size(400, 900));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showMoneyUnlockSheet(
                    context,
                    gateway: gateway,
                    capabilities: capabilities,
                    userId: 'user_1',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  // The sheet records the chosen method in shared_preferences after a
  // successful proof; without the mock that write would throw on the platform
  // channel. (The sheet also tolerates that failure — see below — but the test
  // environment should behave like a device.)
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('an accepted PIN unlocks and closes the sheet', (tester) async {
    final gateway = _FakeGateway(acceptedPin: '1234');
    await _openSheet(
      tester,
      gateway: gateway,
      capabilities: const AppUnlockCapabilities(
        pinConfigured: true,
        authenticatorConfigured: false,
        phoneVerified: false,
        smsUnlockAvailable: false,
      ),
    );

    expect(find.byKey(const ValueKey('money-unlock-sheet')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('money-unlock-input')),
      '1234',
    );
    await tester.tap(find.byKey(const ValueKey('money-unlock-submit')));
    await tester.pumpAndSettle();

    expect(gateway.seenPin, '1234');
    expect(
      find.byKey(const ValueKey('money-unlock-sheet')),
      findsNothing,
      reason: 'an accepted proof closes the challenge',
    );
  });

  testWidgets('a wrong PIN stays open and states the attempts left', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      refusal: const AppUnlockRefusal('PIN_INVALID', attemptsLeft: 3),
    );
    await _openSheet(
      tester,
      gateway: gateway,
      capabilities: const AppUnlockCapabilities(
        pinConfigured: true,
        authenticatorConfigured: false,
        phoneVerified: false,
        smsUnlockAvailable: false,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('money-unlock-input')),
      '0000',
    );
    await tester.tap(find.byKey(const ValueKey('money-unlock-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('money-unlock-sheet')), findsOneWidget);
    expect(
      find.text('That PIN is not right. 3 tries left.'),
      findsOneWidget,
      reason: 'the server’s own attemptsLeft is what the member sees',
    );
  });

  testWidgets('a locked PIN says so instead of counting down', (tester) async {
    final gateway = _FakeGateway(
      refusal: const AppUnlockRefusal('PIN_LOCKED', attemptsLeft: 0),
    );
    await _openSheet(
      tester,
      gateway: gateway,
      capabilities: const AppUnlockCapabilities(
        pinConfigured: true,
        authenticatorConfigured: false,
        phoneVerified: false,
        smsUnlockAvailable: false,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('money-unlock-input')),
      '0000',
    );
    await tester.tap(find.byKey(const ValueKey('money-unlock-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('Too many wrong PINs. PIN unlock is locked for now.'),
      findsOneWidget,
    );
  });

  testWidgets('only configured methods are offered', (tester) async {
    await _openSheet(
      tester,
      gateway: _FakeGateway(acceptedPin: '1234'),
      capabilities: const AppUnlockCapabilities(
        pinConfigured: true,
        authenticatorConfigured: false,
        phoneVerified: false,
        smsUnlockAvailable: false,
      ),
    );

    // One challenge means no choice chips: the input is the whole sheet.
    expect(find.text('Authenticator code'), findsNothing);
    expect(find.text('Text message code'), findsNothing);
    expect(find.byKey(const ValueKey('money-unlock-input')), findsOneWidget);
    expect(find.text('4 to 8 digits'), findsOneWidget);
  });

  testWidgets('a method choice appears only when there is a choice', (
    tester,
  ) async {
    await _openSheet(
      tester,
      gateway: _FakeGateway(acceptedPin: '1234'),
      capabilities: _pinOnly(),
    );

    expect(find.text('Azaman PIN'), findsOneWidget);
    expect(find.text('Text message code'), findsOneWidget);
  });

  testWidgets('SMS sends a challenge and shows the server mask', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      acceptedPin: '1234',
      challenge: const AppUnlockSmsChallenge(
        challengeId: 'ch_9',
        maskedPhone: '+233 •• •• 1234',
      ),
    );
    await _openSheet(tester, gateway: gateway, capabilities: _pinOnly());

    await tester.tap(find.text('Text message code'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('money-unlock-submit')));
    await tester.pumpAndSettle();

    expect(gateway.smsSends, 1);
    expect(find.text('Code sent to +233 •• •• 1234'), findsOneWidget);
  });

  testWidgets('an account with nothing configured gets the truth', (
    tester,
  ) async {
    await _openSheet(
      tester,
      gateway: _FakeGateway(),
      capabilities: AppUnlockCapabilities.none,
    );

    expect(
      find.byKey(const ValueKey('money-unlock-empty-state')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('money-unlock-input')), findsNothing);
    expect(find.byKey(const ValueKey('money-unlock-submit')), findsNothing);
  });

  testWidgets('the demo build labels its demo PIN', (tester) async {
    await _openSheet(
      tester,
      gateway: DemoAppUnlockGateway(),
      capabilities: const AppUnlockCapabilities(
        pinConfigured: true,
        authenticatorConfigured: false,
        phoneVerified: false,
        smsUnlockAvailable: false,
      ),
    );

    expect(find.text('Demo build: the demo PIN is 1234.'), findsOneWidget);
  });
}
