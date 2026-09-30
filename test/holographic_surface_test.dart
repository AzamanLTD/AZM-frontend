import 'package:azaman/providers/sensory_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:azaman/widgets/holographic_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({bool interactive = true, bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 180,
              child: HolographicSurface(
                base: const Color(0xFF111827),
                tint: const Color(0xFFD4A017),
                interactive: interactive,
                padding: const EdgeInsets.all(16),
                child: const Text('GH₵ 1,240.42'),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AzSensory.apply(const SensoryPreferences());
  });
  tearDown(() => AzSensory.apply(const SensoryPreferences()));

  for (final forced in [true, false]) {
    testWidgets('sheen override=$forced wins over opposite OS flag', (tester) async {
      AzSensory.apply(SensoryPreferences(forceReduceMotion: forced));
      await tester.pumpWidget(_host(reduceMotion: !forced));
      expect(find.descendant(of: find.byType(HolographicSurface),
        matching: find.byType(Listener)), forced ? findsNothing : findsOneWidget);
      expect(find.text('GH₵ 1,240.42'), findsOneWidget);
      final gradients = tester.widgetList<DecoratedBox>(find.descendant(
        of: find.byType(HolographicSurface), matching: find.byType(DecoratedBox)))
        .where((w) => (w.decoration as BoxDecoration).gradient != null);
      expect(gradients.length, greaterThanOrEqualTo(3));
    });
  }

  testWidgets('changing override stops a moving sheen without losing its material', (tester) async {
    final sensory = SensoryProvider();
    addTearDown(sensory.dispose);
    await tester.pumpWidget(AzMotionScope(notifier: sensory, child: _host()));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(find.byType(HolographicSurface)));
    await gesture.moveBy(const Offset(40, 20));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    await sensory.setForceReduceMotion(true);
    await tester.pump();
    expect(find.descendant(of: find.byType(HolographicSurface), matching: find.byType(Listener)), findsNothing);
    expect(find.text('GH₵ 1,240.42'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await sensory.setForceReduceMotion(false);
    await tester.pump();
    expect(find.descendant(of: find.byType(HolographicSurface), matching: find.byType(Listener)), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('renders its child', (tester) async {
    await tester.pumpWidget(_host());
    expect(find.text('GH₵ 1,240.42'), findsOneWidget);
  });

  testWidgets('a pointer move does not throw and does not consume the drag',
      (tester) async {
    await tester.pumpWidget(_host());
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HolographicSurface)),
    );
    await gesture.moveBy(const Offset(40, 20));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a parent horizontal scroll still receives the drag', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            children: [
              SizedBox(
                width: 300,
                height: 180,
                child: HolographicSurface(
                  base: const Color(0xFF111827),
                  tint: const Color(0xFFD4A017),
                  child: const Text('card'),
                ),
              ),
              const SizedBox(width: 900, height: 180, child: Text('filler')),
            ],
          ),
        ),
      ),
    );

    // A drag starting ON the holographic surface must scroll the deck.
    await tester.drag(find.byType(HolographicSurface), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0),
        reason: 'Listener stole the drag from the parent scroll view');
  });

  testWidgets('reduced motion makes it fully static', (tester) async {
    await tester.pumpWidget(_host(reduceMotion: true));
    // Scoped to the surface itself: the framework injects its own Listeners
    // (ScrollBehavior etc.), so a global findsNothing would be too broad.
    expect(
      find.descendant(
        of: find.byType(HolographicSurface),
        matching: find.byType(Listener),
      ),
      findsNothing,
    );
  });
}
