// The hold dial: tap stays a tap, hold opens four directions, lean + release
// runs one, a centre release keeps it open, unavailable directions do
// nothing, and a horizontal swipe still scrolls a row of avatars.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/liquid/az_hold_dial.dart';

Map<AzDialDirection, AzHoldDialAction> _actions(List<String> log, {bool downEnabled = true}) => {
      AzDialDirection.up: AzHoldDialAction(icon: Icons.north, label: 'New stories', onSelect: () => log.add('up')),
      AzDialDirection.down: AzHoldDialAction(
          icon: Icons.south, label: 'Seen stories', onSelect: downEnabled ? () => log.add('down') : null),
      AzDialDirection.left: AzHoldDialAction(icon: Icons.west, label: 'Profile', onSelect: () => log.add('left')),
      AzDialDirection.right: AzHoldDialAction(icon: Icons.east, label: 'Message', onSelect: () => log.add('right')),
    };

Widget _host(List<String> log, {bool downEnabled = true}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: AzHoldDial(
            onTap: () => log.add('tap'),
            actions: _actions(log, downEnabled: downEnabled),
            child: const SizedBox(width: 64, height: 64, child: ColoredBox(color: Colors.teal)),
          ),
        ),
      ),
    );

void main() {
  group('leanFor', () {
    test('inside the dead zone there is no lean', () {
      expect(AzHoldDial.leanFor(const Offset(10, 8)), isNull);
    });
    test('the dominant axis wins', () {
      expect(AzHoldDial.leanFor(const Offset(0, -40)), AzDialDirection.up);
      expect(AzHoldDial.leanFor(const Offset(5, 40)), AzDialDirection.down);
      expect(AzHoldDial.leanFor(const Offset(-40, 10)), AzDialDirection.left);
      expect(AzHoldDial.leanFor(const Offset(40, -10)), AzDialDirection.right);
    });
  });

  testWidgets('a tap is still a tap, and opens no dial', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(_host(log));
    await tester.tap(find.byType(AzHoldDial));
    await tester.pumpAndSettle();
    expect(log, ['tap']);
    expect(find.byIcon(Icons.north), findsNothing);
  });

  testWidgets('hold, lean up, release runs New stories', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(_host(log));
    final centre = tester.getCenter(find.byType(AzHoldDial));
    final g = await tester.startGesture(centre);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.north), findsOneWidget, reason: 'the dial opened on hold');
    await g.moveBy(const Offset(0, -50));
    await tester.pump();
    expect(find.text('New stories'), findsOneWidget);
    await g.up();
    await tester.pumpAndSettle();
    expect(log, ['up']);
    expect(find.byIcon(Icons.north), findsNothing, reason: 'the dial closed');
  });

  testWidgets('releasing in the centre keeps the dial open for a tap', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(_host(log));
    final g = await tester.startGesture(tester.getCenter(find.byType(AzHoldDial)));
    await tester.pump(const Duration(milliseconds: 400));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.east), findsOneWidget);
    await tester.tap(find.byIcon(Icons.east));
    await tester.pumpAndSettle();
    expect(log, ['right']);
  });

  testWidgets('an unavailable direction does nothing', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(_host(log, downEnabled: false));
    final g = await tester.startGesture(tester.getCenter(find.byType(AzHoldDial)));
    await tester.pump(const Duration(milliseconds: 400));
    await g.moveBy(const Offset(0, 50));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(log, isEmpty);
  });

  testWidgets('a horizontal swipe in a row of avatars scrolls, not dials', (tester) async {
    final log = <String>[];
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 100,
          child: ListView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < 12; i++)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: AzHoldDial(
                    onTap: () => log.add('tap'),
                    actions: _actions(log),
                    child: const SizedBox(width: 64, height: 64, child: ColoredBox(color: Colors.teal)),
                  ),
                ),
            ],
          ),
        ),
      ),
    ));
    await tester.drag(find.byType(AzHoldDial).first, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(100));
    expect(find.byIcon(Icons.north), findsNothing);
    expect(log, isEmpty);
  });
}
