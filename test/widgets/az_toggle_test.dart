// =============================================================================
// AZ TOGGLE — the branded Settings toggle (Stage 2 §3).
//
// Pins the replacement contract: the stock Flutter Switch is gone from
// Settings surfaces, the branded control fires the caller's callback,
// honours disabled state, exposes screen-reader truth, and snaps under
// reduced motion.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/az_toggle.dart';
import 'package:azaman/widgets/sensory_preferences_section.dart';

/// Loads the real theme provider with its async palette init. SharedPreferences
/// must be mocked before calling.
Future<ThemeProvider> _loadTheme(WidgetTester tester) async {
  final theme = (await tester.runAsync<ThemeProvider>(() async {
    final t = ThemeProvider();
    int guard = 0;
    while (!t.isLoaded && guard++ < 100) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    return t;
  }))!;
  return theme;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AzToggle', () {
    testWidgets('a tap flips the value through the caller callback', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final theme = await _loadTheme(tester);

      // A stateful host: the toggle's caller rebuilds it with the new
      // value (as the real Settings rows do) — that round-trip is the
      // contract being pinned.
      var value = false;
      bool? lastValue;
      Widget host() => MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AzToggle(
              value: value,
              colors: theme.colors,
              semanticLabel: 'Push Notifications',
              onChanged: (v) {
                lastValue = v;
                setState(() => value = v);
              },
            ),
          ),
        ),
      );

      await tester.pumpWidget(host());

      await tester.tap(find.byType(AzToggle));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        lastValue,
        isTrue,
        reason: 'the branded toggle drives the caller callback',
      );
      expect(find.byType(AzToggle), findsOneWidget);

      await tester.tap(find.byType(AzToggle));
      await tester.pump(const Duration(milliseconds: 300));
      expect(lastValue, isFalse, reason: 'and back');
    });

    testWidgets(
      'screen-reader semantics expose the toggled state and a label',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final theme = await _loadTheme(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AzToggle(
                value: true,
                colors: theme.colors,
                semanticLabel: 'Push Notifications',
                onChanged: (_) {},
              ),
            ),
          ),
        );

        final semantics = find.bySemanticsLabel('Push Notifications');
        expect(
          semantics,
          findsOneWidget,
          reason: 'the toggle is discoverable by label',
        );

        // a11y activation flips it without any visual gesture
        bool? activated;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AzToggle(
                value: false,
                colors: theme.colors,
                semanticLabel: 'Push Notifications',
                onChanged: (v) => activated = v,
              ),
            ),
          ),
        );
        await tester.tap(find.bySemanticsLabel('Push Notifications'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          activated,
          isTrue,
          reason: 'semantics onTap is the accessible control path',
        );
      },
    );
  });

  // ---------------------------------------------------------------------
  // Stage 2 follow-up: gesture arbitration. A pointer-down must never
  // commit a setting change; only a COMPLETED tap (or a semantic action)
  // may flip the value, fire haptics and persist.
  // ---------------------------------------------------------------------
  group('AzToggle gesture arbitration', () {
    testWidgets('a drag that starts on the toggle and is won by the scrollable '
        'never commits the setting or its persistence', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final theme = await _loadTheme(tester);

      var changes = 0;
      bool? lastValue;
      Widget host() => MaterialApp(
        home: Scaffold(
          // A REAL scrollable parent with enough content to win the
          // gesture arena when the pointer drags vertically.
          body: ListView(
            children: [
              const SizedBox(height: 48),
              Center(
                child: AzToggle(
                  value: false,
                  colors: theme.colors,
                  semanticLabel: 'Push Notifications',
                  onChanged: (v) {
                    changes++;
                    lastValue = v;
                    prefs.setBool('az_toggle_probe', v);
                  },
                ),
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      );

      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 300));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(AzToggle)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      // The drag exceeds touch slop: the Scrollable claims the arena and
      // the tap recognizer is rejected (this is the cancelled-tap path).
      await gesture.moveBy(const Offset(0, -140));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        changes,
        0,
        reason: 'a scroll-won drag must not toggle the setting',
      );
      expect(
        lastValue,
        isNull,
        reason: 'the caller callback must not fire at all',
      );
      expect(
        prefs.getBool('az_toggle_probe'),
        isNull,
        reason: 'nothing may be persisted by a cancelled gesture',
      );
      expect(find.byType(AzToggle), findsOneWidget);
    });

    testWidgets(
      'pointer-down alone never commits; the completed tap commits exactly '
      'once and persists',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final theme = await _loadTheme(tester);

        var changes = 0;
        bool? lastValue;
        Widget host() => MaterialApp(
          home: Scaffold(
            body: Center(
              child: AzToggle(
                value: false,
                colors: theme.colors,
                semanticLabel: 'Push Notifications',
                onChanged: (v) {
                  changes++;
                  lastValue = v;
                  prefs.setBool('az_toggle_probe', v);
                },
              ),
            ),
          ),
        );

        await tester.pumpWidget(host());
        await tester.pump(const Duration(milliseconds: 300));

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(AzToggle)),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(
          changes,
          0,
          reason: 'a pointer-down/hold must never flip a setting',
        );

        await gesture.up();
        await tester.pumpAndSettle();

        expect(changes, 1, reason: 'one completed tap, exactly one toggle');
        expect(lastValue, isTrue);
        expect(
          prefs.getBool('az_toggle_probe'),
          isTrue,
          reason: 'a completed tap persists',
        );
      },
    );

    testWidgets('a cancelled pointer interaction leaves value and persistence '
        'untouched', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final theme = await _loadTheme(tester);

      var changes = 0;
      Widget host() => MaterialApp(
        home: Scaffold(
          body: Center(
            child: AzToggle(
              value: false,
              colors: theme.colors,
              semanticLabel: 'Push Notifications',
              onChanged: (v) {
                changes++;
                prefs.setBool('az_toggle_probe', v);
              },
            ),
          ),
        ),
      );

      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 300));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(AzToggle)),
      );
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(changes, 0);
      expect(prefs.getBool('az_toggle_probe'), isNull);
    });

    testWidgets(
      'a saved value rehydrates from persistence and a semantic action '
      'still activates the control',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'az_toggle_probe': true,
        });
        final prefs = await SharedPreferences.getInstance();
        final theme = await _loadTheme(tester);

        var value = prefs.getBool('az_toggle_probe') ?? false;
        var changes = 0;
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (context, setState) => AzToggle(
                    value: value,
                    colors: theme.colors,
                    semanticLabel: 'Push Notifications',
                    onChanged: (v) {
                      changes++;
                      prefs.setBool('az_toggle_probe', v);
                      setState(() => value = v);
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(value, isTrue, reason: 'the stored preference rehydrates');

        await tester.tap(find.bySemanticsLabel('Push Notifications'));
        await tester.pumpAndSettle();

        expect(
          changes,
          1,
          reason: 'the semantic action is the accessible activation path',
        );
        expect(value, isFalse);
        expect(prefs.getBool('az_toggle_probe'), isFalse);
        handle.dispose();
      },
    );
  });

  group('sensory preferences integration', () {
    testWidgets(
      'the sensory rows use the branded control — no stock Flutter Switch '
      'on the surface',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final theme = await _loadTheme(tester);
        final container = ProviderContainer(
          overrides: [
            themeProvider.overrideWith((ref) => theme),
            currentUserProvider.overrideWith((ref) => Stream.value(null)),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(body: SensoryPreferencesSection()),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.byType(AzToggle),
          findsWidgets,
          reason: 'the branded toggle replaces the Switch treatment',
        );
        expect(
          find.byType(Switch),
          findsNothing,
          reason: 'the green stock Switch is gone from Settings toggles',
        );
      },
    );
  });
}
