// Regression: Home "Save" -> context.push('/savings') mounts SavingsScreen
// bare (no Scaffold of its own). Without a Material ancestor every Text
// falls back to Flutter's debug style (yellow double underline +
// monospace), which is exactly what shipped on-device. The screen must
// provide its own Material host.
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/savings_overview_provider.dart';
import 'package:azaman/screens/savings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StaticSavings extends SavingsOverviewNotifier {
  @override
  Future<SavingsOverview> build() async => const SavingsOverview({
        'totalSavedGhs': 3200.0,
        'goals': [
          {
            'id': 'g1',
            'name': 'New',
            'currentAmountGhs': 510,
            'targetAmountGhs': 1000,
          },
        ],
      });
}

void main() {
  testWidgets(
      'SavingsScreen mounted bare (as the /savings route does) has a '
      'Material host: no debug underline, no monospace fallback',
      (tester) async {
    SharedPreferences.setMockInitialValues({'azaman_theme': 0});
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => AuthProvider()),
        savingsOverviewProvider.overrideWith(_StaticSavings.new),
      ],
    );
    addTearDown(container.dispose);

    // The route page here is a plain Navigator page with NO Scaffold: the
    // same shape traversePage() produces around SavingsScreen.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (_) => const Directionality(
              textDirection: TextDirection.ltr,
              child: SavingsScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final screen = find.byType(SavingsScreen);
    expect(screen, findsOneWidget);

    // 1. A Scaffold (hence Material) lives inside SavingsScreen itself.
    expect(
      find.descendant(of: screen, matching: find.byType(Scaffold)),
      findsOneWidget,
      reason: 'SavingsScreen must own its Material host',
    );

    // 2. Every rendered Text resolves to NO underline (the debug fallback
    //    is TextDecoration.underline + doubleunderline in yellow).
    final texts = tester.widgetList<Text>(
      find.descendant(of: screen, matching: find.byType(Text)),
    );
    expect(texts, isNotEmpty);
    for (final t in texts) {
      final ctx = tester.element(find.byWidget(t));
      final style = DefaultTextStyle.of(ctx).style.merge(t.style);
      expect(
        style.decoration == null || style.decoration == TextDecoration.none,
        isTrue,
        reason: 'Text "${t.data}" resolved decoration ${style.decoration} '
            '(missing-Material debug underline)',
      );
      expect(style.fontFamily, isNot('monospace'),
          reason: 'Text "${t.data}" fell back to monospace');
    }
  });
}
