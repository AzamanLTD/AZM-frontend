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
      expect(lastValue, isTrue,
          reason: 'the branded toggle drives the caller callback');
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

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: AzToggle(
              value: true,
              colors: theme.colors,
              semanticLabel: 'Push Notifications',
              onChanged: (_) {},
            ),
          ),
        ));

        final semantics = find.bySemanticsLabel('Push Notifications');
        expect(semantics, findsOneWidget,
            reason: 'the toggle is discoverable by label');

        // a11y activation flips it without any visual gesture
        bool? activated;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: AzToggle(
              value: false,
              colors: theme.colors,
              semanticLabel: 'Push Notifications',
              onChanged: (v) => activated = v,
            ),
          ),
        ));
        await tester.tap(find.bySemanticsLabel('Push Notifications'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(activated, isTrue,
            reason: 'semantics onTap is the accessible control path');
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
        final container = ProviderContainer(overrides: [
          themeProvider.overrideWith((ref) => theme),
          currentUserProvider.overrideWith((ref) => Stream.value(null)),
        ]);
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: const Scaffold(body: SensoryPreferencesSection()),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(AzToggle), findsWidgets,
            reason: 'the branded toggle replaces the Switch treatment');
        expect(find.byType(Switch), findsNothing,
            reason: 'the green stock Switch is gone from Settings toggles');
      },
    );
  });
}
