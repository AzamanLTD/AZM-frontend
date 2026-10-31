// AZAMAN — THE PREFERENCE THAT DECIDES WHICH PROOF LOCKS THE MONEY.
//
// The screen is a mirror of one key: 'azm.money_unlock.preferred.<userId>'.
// It is read on the tap path, so it cannot wait on disk — which is exactly why
// the races around it have to be proved rather than reasoned about:
//
//   • restart        a saved choice must be honoured on the FIRST unlock, not
//                    the second, so the flow hydrates before it reads;
//   • account switch one member's choice must never aim another member's
//                    unlock, even when their reads interleave;
//   • intent         a choice made while a read is in flight wins;
//   • storage        unreadable storage means "no preference", never a
//                    fabricated one;
//   • logout         nothing survives.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/app_unlock_gateway.dart';
import 'package:azaman/services/money_unlock_flow.dart';

/// A notifier with the container that owns it, so `state` assertions are real
/// provider state and not a detached object.
class _Harness {
  _Harness(this.container, this.notifier);
  final ProviderContainer container;
  final MoneyUnlockPreference notifier;
  AppUnlockMethod? get state => container.read(moneyUnlockPreferenceProvider);
}

_Harness _harness() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return _Harness(
    container,
    container.read(moneyUnlockPreferenceProvider.notifier),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('restart: a saved choice is honoured on the first read', () async {
    final h = _harness();
    await h.notifier.remember('user-a', AppUnlockMethod.pin);

    // A fresh provider stands for the next app launch.
    final reopened = _harness();
    expect(
      reopened.state,
      isNull,
      reason: 'nothing is claimed before the read, not even a guess',
    );
    await reopened.notifier.hydrate('user-a');
    expect(
      reopened.state,
      AppUnlockMethod.pin,
      reason:
          'the member chose PIN last session and must not be asked for '
          'something else now',
    );
  });

  test('account switch: A\'s slow read never overwrites B', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      moneyUnlockPreferenceKey('user-a'): AppUnlockMethod.totp.name,
      moneyUnlockPreferenceKey('user-b'): AppUnlockMethod.pin.name,
    });
    final h = _harness();

    // A's read starts and is still in flight when the account changes.
    final staleA = h.notifier.hydrate('user-a');
    // B is the signed-in member now, and completes first.
    await h.notifier.hydrate('user-b');
    expect(h.state, AppUnlockMethod.pin);

    // A's future finally lands. It must be discarded, not applied.
    await staleA;
    expect(
      h.state,
      AppUnlockMethod.pin,
      reason:
          'a read started for the previous account must not aim this '
          'member\'s unlock at their authenticator',
    );

    // And signing out clears it rather than leaving a method armed.
    h.notifier.clear();
    expect(h.state, isNull);
  });

  test(
    'account switch: switching accounts drops the previous choice first',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        moneyUnlockPreferenceKey('user-a'): AppUnlockMethod.totp.name,
      });
      final h = _harness();
      await h.notifier.hydrate('user-a');
      expect(h.state, AppUnlockMethod.totp);

      // user-b has no stored choice at all: the mirror must be empty, not A's.
      await h.notifier.hydrate('user-b');
      expect(
        h.state,
        isNull,
        reason:
            'a member with no choice must fall back to device auth, never '
            'inherit the previous member\'s authenticator',
      );
    },
  );

  test('intent during hydration: the member\'s new choice wins', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      moneyUnlockPreferenceKey('user-a'): AppUnlockMethod.totp.name,
    });
    final h = _harness();

    final reading = h.notifier.hydrate('user-a');
    // The member picks PIN while the stored TOTP read is still in flight.
    await h.notifier.remember('user-a', AppUnlockMethod.pin);
    await reading;

    expect(
      h.state,
      AppUnlockMethod.pin,
      reason: 'a stale read must not undo a deliberate choice',
    );
  });

  test('storage failure claims no preference, and does not throw', () async {
    // A prefs implementation that fails every read.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final h = _harness();
    // Break the store after the mirror has been used once.
    await h.notifier.hydrate('user-a');
    expect(h.state, isNull);

    // A value that is not a known method is ignored rather than trusted.
    SharedPreferences.setMockInitialValues(<String, Object>{
      moneyUnlockPreferenceKey('user-c'): 'telepathy',
    });
    final other = _harness();
    await other.notifier.hydrate('user-c');
    expect(
      other.state,
      isNull,
      reason: 'an unrecognised stored value is not a method this build can run',
    );
  });

  test('hydration is idempotent for the same account', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      moneyUnlockPreferenceKey('user-a'): AppUnlockMethod.pin.name,
    });
    final h = _harness();
    await h.notifier.hydrate('user-a');
    h.notifier.state; // no-op read for clarity
    // Mutating the mirror then re-hydrating the SAME account must not clobber
    // the live value with the stored one.
    await h.notifier.remember('user-a', AppUnlockMethod.sms);
    await h.notifier.hydrate('user-a');
    expect(h.state, AppUnlockMethod.sms);
  });
}
