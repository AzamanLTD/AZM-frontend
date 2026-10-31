// The money gate's state machine. These are the rules that make a local
// privacy gate trustworthy: locked before anything is shown, one challenge at
// a time, and no late result may unlock after the gate was relocked.

import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/money_access_provider.dart';

void main() {
  test('starts locked, and money is not viewable', () {
    final c = MoneyAccessController();
    expect(c.state, MoneyAccessState.locked);
    expect(c.canViewMoney, isFalse);
    expect(c.isAuthenticating, isFalse);
  });

  test('an attempt moves to authenticating, then unlocks', () {
    final c = MoneyAccessController();
    final attempt = c.beginUnlock();
    expect(c.state, MoneyAccessState.authenticating);
    c.finishUnlock(attempt);
    expect(c.state, MoneyAccessState.unlocked);
    expect(c.canViewMoney, isTrue);
  });

  test('cancelling returns to locked', () {
    final c = MoneyAccessController();
    final attempt = c.beginUnlock();
    c.cancelUnlock(attempt);
    expect(c.state, MoneyAccessState.locked);
  });

  test('a relock invalidates an in-flight attempt', () {
    final c = MoneyAccessController();
    final attempt = c.beginUnlock();
    c.lock();
    c.finishUnlock(attempt);
    expect(
      c.state,
      MoneyAccessState.locked,
      reason: 'a late verification must not unlock a relocked app',
    );
  });

  test('a second attempt invalidates the first', () {
    final c = MoneyAccessController();
    final first = c.beginUnlock();
    c.cancelUnlock(first);
    final second = c.beginUnlock();
    c.finishUnlock(first);
    expect(
      c.state,
      MoneyAccessState.authenticating,
      reason: 'only the current attempt may finish',
    );
    c.finishUnlock(second);
    expect(c.state, MoneyAccessState.unlocked);
  });

  test('finishing twice notifies once', () {
    final c = MoneyAccessController();
    var notifications = 0;
    c.addListener(() => notifications++);
    final attempt = c.beginUnlock();
    c.finishUnlock(attempt);
    c.finishUnlock(attempt);
    expect(c.state, MoneyAccessState.unlocked);
    expect(notifications, 2, reason: 'begin + finish, nothing more');
  });

  test('locking while already locked still invalidates attempts', () {
    final c = MoneyAccessController();
    final attempt = c.beginUnlock();
    c.cancelUnlock(attempt);
    c.lock();
    c.finishUnlock(attempt);
    expect(c.state, MoneyAccessState.locked);
  });
}
