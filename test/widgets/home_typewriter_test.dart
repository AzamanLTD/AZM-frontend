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
import 'package:azaman/providers/home_shell_active_provider.dart';
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
        expect(m.phase, TypewriterPhase.holding,
            reason: 'typing completes and the message HOLDS — the hold is '
                'a real phase that owns the rotation timer');
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
        expect(m.phase, TypewriterPhase.holding,
            reason: 'identical text must not restart the grammar — the '
                'current hold carries on undisturbed');
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
        expect(m.phase, TypewriterPhase.holding,
            reason: 'reduced motion skips the traversal, not the hold '
                'cycle');
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

  group('AzTypewriterHeading — shell inactive/resume lifecycle (audit §7)',
      () {
    String headingText(WidgetTester tester) {
      final t = find.descendant(
        of: find.byType(AzTypewriterHeading),
        matching: find.byType(Text),
      );
      return tester.widget<Text>(t.first).data ?? '';
    }

    Future<void> pumpHeading(
        WidgetTester tester, ProviderContainer container) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeProvider.getThemeData(AzamanTheme.light),
            home: const MediaQuery(
              data: MediaQueryData(size: Size(400, 900)),
              child: Scaffold(body: AzTypewriterHeading()),
            ),
          ),
        ),
      );
      await tester.pump(); // the post-frame _syncMessage arms the message
      await tester.pump(const Duration(milliseconds: 200)); // typing runs
    }

    testWidgets('the cycle runs while the shell tab is ACTIVE, freezes '
        'completely when it goes INACTIVE (even past the hold), and '
        'resumes from the same message', (tester) async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => AuthProvider()),
          unreadCountProvider.overrideWith((ref) => 0),
        ],
      );
      addTearDown(container.dispose);

      await pumpHeading(tester, container);

      // ACTIVE: the cycle advances — the greeting types in.
      final active1 = headingText(tester);
      await tester.pump(const Duration(milliseconds: 400));
      final active2 = headingText(tester);
      expect(active2 != active1, isTrue,
          reason: 'while the Home tab is active, the machine types');
      expect(active2.length >= active1.length, isTrue);

      // INACTIVE (the shell writes false on tab switch): every timer is
      // cancelled — typing stops AND the hold that would follow the
      // completed message never fires, however long the user is away.
      container.read(homeShellActiveProvider.notifier).state = false;
      await tester.pump(const Duration(milliseconds: 100));
      final paused = headingText(tester);
      expect(paused, isNotEmpty, reason: 'the paused text is kept');
      await tester.pump(const Duration(seconds: 30));
      expect(headingText(tester), paused,
          reason: 'inactive → no typing, no hold expiry, no rotation — '
              '30s is 3× the hold duration and nothing fired');

      // RESUME (the shell writes true on re-entry): a held message
      // re-arms its hold from zero; when it elapses the ladder rotates —
      // a paused machine would never have fired.
      container.read(homeShellActiveProvider.notifier).state = true;
      await tester.pump(const Duration(seconds: 2));
      expect(headingText(tester), paused,
          reason: 'resume re-arms the hold — the text is kept');
      await tester.pump(const Duration(seconds: 10));
      final rotated = headingText(tester);
      expect(rotated != paused, isTrue,
          reason: 'hold elapsed after resume → the ladder rotates again');
    });

    testWidgets('a message armed while the shell is ALREADY inactive '
        'pauses before typing a single character, then types on resume',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => AuthProvider()),
          unreadCountProvider.overrideWith((ref) => 0),
          homeShellActiveProvider.overrideWith((ref) => false),
        ],
      );
      addTearDown(container.dispose);

      await pumpHeading(tester, container);
      expect(headingText(tester), isEmpty,
          reason: 'armed while inactive → nothing types, no timer runs');

      // The shell reports Home active again: the armed message types now.
      // (The zero-duration pump builds the resume frame — a pump advances
      // the clock BEFORE building, so the typing timer only arms once the
      // rebuild has actually run.)
      container.read(homeShellActiveProvider.notifier).state = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(headingText(tester), isNotEmpty,
          reason: 'resume types the armed message');
    });
  });
}
