// NEW-HOME §2 — the typewriter heading contract.
//
// The greeting must TYPE / ERASE / TYPE as a real character-level state
// machine (never an AnimatedSwitcher cross-fade), with:
//   * priority selection (reminder > event > greeting > feature)
//   * identical-message no-ops (no needless erase/retype)
//   * interruption safety (a new message erases the current one first)
//   * reduced motion (the final current message appears immediately)
//   * honest fallback copy that can never fabricate data
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/az_typewriter_heading.dart';

void main() {
  group('TypewriterMachine — type / pause / erase / type', () {
    test('types forward character by character', () {
      fakeAsync((async) {
        final m = TypewriterMachine()
          ..showMessage('Hey');
        expect(m.phase, TypewriterPhase.typing);
        expect(m.shownText, '');

        async.elapse(const Duration(milliseconds: 22));
        expect(m.shownText, 'H');

        async.elapse(const Duration(milliseconds: 44));
        expect(m.shownText, 'Hey');
        expect(m.phase, TypewriterPhase.idle,
            reason: 'typing completes and the message holds');
        m.dispose();
      });
    });

    test('erases backward, then types the next message', () {
      fakeAsync((async) {
        final m = TypewriterMachine()..showMessage('Hello');
        async.elapse(const Duration(seconds: 1));
        expect(m.shownText, 'Hello');

        m.showMessage('World');
        expect(m.phase, TypewriterPhase.erasing,
            reason: 'the old message must erase before the new one types');
        async.elapse(const Duration(milliseconds: 13));
        expect(m.shownText, 'Hell');
        // Finish erasing + typing.
        async.elapse(const Duration(seconds: 1));
        expect(m.shownText, 'World');
        m.dispose();
      });
    });

    test('an identical next message does NOT needlessly erase/retype', () {
      fakeAsync((async) {
        final m = TypewriterMachine()..showMessage('Same');
        async.elapse(const Duration(seconds: 1));
        expect(m.shownText, 'Same');

        m.showMessage('Same');
        expect(m.phase, TypewriterPhase.idle,
            reason: 'identical text must not restart the grammar');
        expect(m.shownText, 'Same');
        async.elapse(const Duration(seconds: 1));
        expect(m.shownText, 'Same');
        m.dispose();
      });
    });

    test('interrupting mid-type erases the partial and types the new one',
        () {
      fakeAsync((async) {
        final m = TypewriterMachine()..showMessage('Hello');
        async.elapse(const Duration(milliseconds: 44));
        expect(m.shownText, 'He');

        m.showMessage('Nope');
        expect(m.phase, TypewriterPhase.erasing);
        async.elapse(const Duration(seconds: 1));
        expect(m.shownText, 'Nope');
        m.dispose();
      });
    });

    test('reduced-motion path: the final message appears immediately', () {
      fakeAsync((async) {
        final m = TypewriterMachine()..showImmediately('Instant');
        expect(m.shownText, 'Instant');
        expect(m.phase, TypewriterPhase.idle);
        async.elapse(const Duration(seconds: 1));
        expect(m.shownText, 'Instant');
        m.dispose();
      });
    });

    test('cancellation: dispose stops every pending timer without throwing',
        () {
      fakeAsync((async) {
        final m = TypewriterMachine()..showMessage('Pending');
        m.dispose();
        async.elapse(const Duration(seconds: 10));
        // Reaching here without a timer callback on a disposed machine is
        // the pass condition.
      });
    });
  });

  group('HeadingMessageSelector — priority order', () {
    test('a verified reminder outranks a verified event', () {
      final top = HeadingMessageSelector.topContextual(
        susuDueTomorrow: true,
        moneyArrivedToday: 'USDC 50.00',
      );
      expect(top, isNotNull);
      expect(top!.priority, HomeHeadingPriority.reminder);
      expect(top.text, 'Your Susu contribution is due tomorrow');
    });

    test('an event wins when no reminder exists', () {
      final top = HeadingMessageSelector.topContextual(
        susuDueTomorrow: false,
        moneyArrivedToday: 'USDC 50.00',
      );
      expect(top, isNotNull);
      expect(top!.priority, HomeHeadingPriority.event);
    });

    test('nothing contextual → null (the greeting/feature ladder remains)',
        () {
      expect(
        HeadingMessageSelector.topContextual(
            susuDueTomorrow: false, moneyArrivedToday: null),
        isNull,
      );
    });

    test('the feature fallback copy never fabricates data', () {
      expect(kHeadingFeatureMessages.length, 4);
      for (final m in kHeadingFeatureMessages) {
        expect(m.priority, HomeHeadingPriority.feature);
        // No numbers, balances, rates, offers or urgency in fallback copy.
        expect(RegExp(r'\d').hasMatch(m.text), isFalse,
            reason: '${m.text} must not carry fabricated figures');
        expect(m.text.toLowerCase(), isNot(contains('urgent')));
        expect(m.text.toLowerCase(), isNot(contains('now!')));
      }
    });
  });

  group('AzTypewriterHeading widget — reduced motion', () {
    testWidgets('shows the final current message immediately (no per-char '
        'animation)', (tester) async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => AuthProvider()),
          unreadCountProvider.overrideWith((ref) => 0),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeProvider.getThemeData(AzamanTheme.light),
            home: const MediaQuery(
              data: MediaQueryData(size: Size(400, 900), disableAnimations: true),
              child: Scaffold(body: AzTypewriterHeading()),
            ),
          ),
        ),
      );
      await tester.pump(); // first frame
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // The baseline greeting is present IN FULL on the very first frames
      // — under reduced motion there is no character-by-character reveal.
      expect(
        find.textContaining(RegExp('Good (morning|afternoon|evening)')),
        findsOneWidget,
      );
    });
  });
}
