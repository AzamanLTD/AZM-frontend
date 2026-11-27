// Visual record: the eight money-stage skies, light and dark, at phone
// proportions with a sample amount on top (legibility is the point).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/money_stage/az_ambient_backdrop.dart';

import '../../goldens/golden_harness.dart';

Widget _tile(AzMoneyMood mood, Brightness b) {
  final p = AzSkyPalette.of(mood, b);
  return Expanded(
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(fit: StackFit.expand, children: [
          AzAmbientBackdrop(mood: mood, brightness: b, phase: 0.3),
          Align(
            alignment: const Alignment(0, -0.25),
            child: Text('GH₵ 250',
                style: TextStyle(fontSize: 46, fontWeight: FontWeight.w700, color: p.ink, letterSpacing: -1.5)),
          ),
          Align(
            alignment: const Alignment(0, -0.08),
            child: Text('GH₵ 769.00 available', style: TextStyle(fontSize: 12, color: p.inkMuted)),
          ),
          Align(
            alignment: const Alignment(0, 0.9),
            child: Text(mood.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.ink)),
          ),
        ]),
      ),
    ),
  );
}

void main() {
  const groups = {
    'a': [AzMoneyMood.send, AzMoneyMood.receive, AzMoneyMood.addMoney, AzMoneyMood.withdraw],
    'b': [AzMoneyMood.request, AzMoneyMood.pay, AzMoneyMood.convert, AzMoneyMood.bills],
  };
  for (final brightness in Brightness.values) {
    for (final g in groups.entries) {
      testWidgets('ambient skies ${g.key} - ${brightness.name}', (tester) async {
        await pumpGoldenSurface(
          tester,
          brightness: brightness,
          pixelRatio: 1,
          surfaceSize: const Size(1100, 560),
          home: goldenNoMotion(Scaffold(
            backgroundColor: const Color(0xFF202020),
            body: RepaintBoundary(child: Row(children: [for (final m in g.value) _tile(m, brightness)])),
          )),
        );
        await expectLater(find.byType(RepaintBoundary).first,
            matchesGoldenFile('../../goldens/money_stage/skies_${g.key}_${brightness.name}.png'));
      });
    }
  }
}
