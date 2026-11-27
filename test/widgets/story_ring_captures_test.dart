// Visual record: the two-colour story ring in its states, light and dark.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/story_ring.dart';

import '../goldens/golden_harness.dart';

const _states = <String, StoryRingCounts>{
  'all new': StoryRingCounts(unviewedSilentCount: 3, hasUnviewed: true, unviewedCountKnown: true),
  '5 of 6 new': StoryRingCounts(unviewedSilentCount: 5, viewedCount: 1, hasUnviewed: true, unviewedCountKnown: true),
  '3 of 4 new': StoryRingCounts(unviewedSilentCount: 3, viewedCount: 1, hasUnviewed: true, unviewedCountKnown: true),
  '1 of 4 new': StoryRingCounts(unviewedSilentCount: 1, viewedCount: 3, hasUnviewed: true, unviewedCountKnown: true),
  'all seen': StoryRingCounts(viewedCount: 4),
  'none': StoryRingCounts.empty(),
};

void main() {
  for (final dark in [false, true]) {
    testWidgets('story rings — ${dark ? 'dark' : 'light'}', (tester) async {
      SharedPreferences.setMockInitialValues({'azaman_theme': dark ? 1 : 0});
      final tp = ThemeProvider();
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && !tp.isLoaded; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      });
      final colors = tp.colors;
      await pumpGoldenSurface(
        tester,
        brightness: dark ? Brightness.dark : Brightness.light,
        surfaceSize: const Size(620, 150),
        home: ProviderScope(
          overrides: [themeProvider.overrideWith((ref) => tp)],
          child: Scaffold(
            backgroundColor: colors.background,
            body: RepaintBoundary(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in _states.entries)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StoryRing(counts: e.value, size: 72),
                        const SizedBox(height: 10),
                        Text(e.key, style: TextStyle(fontSize: 11, color: colors.textSecondary)),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await expectLater(find.byType(RepaintBoundary).first,
          matchesGoldenFile('../goldens/stories/rings_${dark ? 'dark' : 'light'}.png'));
    });
  }
}
