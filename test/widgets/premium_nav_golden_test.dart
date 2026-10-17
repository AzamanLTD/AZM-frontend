// CORRECTION G/I — golden gate for the PremiumBottomNav surfaces.
//
// Locks the rendered pixels of the two nav presentations the correction
// round rebuilt:
//
//   1. REST — three tabs + the + beside the pill, the selected tab marked
//      by colour only (the glow backdrop was removed in correction G).
//   2. FOCUSED — the Marketplace root composition: [ … Marketplace
//      (search field) ], the + handed off horizontally by the shell.
//
// in BOTH brightnesses, so any change to the rim hairline, the dark-surface
// tint, the search field chrome or the pill geometry shows up as an
// intentional, reviewable pixel diff rather than a silent visual
// regression on device.
//
// The + is a grey-box stand-in (not the real PlusActionLauncher) so the
// golden pins the NAV band only — the launcher has its own behaviour
// suite, and letting it mount would bake its providers into the raster.
//
// Regenerate deliberately (never to make a suite green):
//   flutter test --update-goldens test/widgets/premium_nav_golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/chat_provider.dart';
import 'package:azaman/providers/marketplace_nav_focus.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';

import '../goldens/golden_harness.dart';

void main() {
  setUp(() {
    // The theme provider and haptic paths both read persisted prefs; pin
    // them to a clean in-memory store so every raster starts from the
    // default (light + gold) identity.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final brightness in Brightness.values) {
    final name = brightness == Brightness.dark ? 'dark' : 'light';

    for (final focused in <bool>[false, true]) {
      final state = focused ? 'focused' : 'rest';

      testWidgets('PremiumBottomNav $state — $name', (tester) async {
        await pumpGoldenSurface(
          tester,
          brightness: brightness,
          surfaceSize: const Size(360, 140),
          home: goldenNoMotion(
            ProviderScope(
              overrides: [
                // Inert badges: the golden pins geometry and chrome, not
                // unread state. Same seam the nav behaviour suites use.
                totalUnreadChatCountProvider.overrideWith((ref) async => 0),
                activeTradeCountProvider.overrideWith((ref) async => 0),
                unreadCountProvider.overrideWith((ref) => 0),
                // Direct state control: the shell sets this on tab entry.
                marketplaceNavFocusProvider.overrideWith((ref) => focused),
              ],
              child: Scaffold(
                body: const SizedBox.shrink(),
                bottomNavigationBar: RepaintBoundary(
                  child: PremiumBottomNav(
                    selectedIndex: focused ? 2 : 0,
                    onItemSelected: (_) {},
                    trailing: const SizedBox(
                      key: ValueKey('plus-stand-in'),
                      width: 54,
                      height: 54,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        if (brightness == Brightness.dark) {
          // The nav reads its palette from themeProvider, not from the
          // MaterialApp brightness the harness pins. Flip it synchronously
          // and re-settle so the raster captures the dark identity.
          // (setTheme's fire-and-forget backend sync dies on the default
          // dev host and is swallowed by its own guard — no external
          // effect in tests.)
          final container = ProviderScope.containerOf(
            tester.element(find.byType(PremiumBottomNav)),
          );
          await container.read(themeProvider).setTheme(AzamanTheme.dark);
          await tester.pump(kGoldenSettle);
        }

        await expectLater(
          find.byType(PremiumBottomNav),
          matchesGoldenFile('goldens/premium_nav_${state}_$name.png'),
        );
      });
    }
  }
}
