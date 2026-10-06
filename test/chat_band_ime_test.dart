// EXPERIENCE PASS §14 — the chat composer IS the contextual band.
//
// Entering an actual chat, the band's role is owned by the chat
// composer: PremiumChatInput already carries the nav pill's geometry
// ("matching the bottom nav bar's dimensions and style"), and in a
// chat the shell's nav band is hidden (chat screens are imperative
// routes — the depth band shows only on router pages), so the
// composer is the ONE bottom surface. These guards pin the §14
// contract:
//
//   1. The composer rides the IME: with a simulated keyboard open,
//      the input bar sits at/above the IME's top edge — never behind
//      it — and stays hit-testable where it renders.
//   2. The composer keeps the pill geometry while riding (same
//      rounded-pill silhouette, not a floating detached strip): its
//      height stays constant between IME-closed and IME-open states.
import 'package:azaman/config.dart';
import 'package:azaman/data/demo_seed_data.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/friends/friend_chat_screen.dart';
import 'package:azaman/widgets/premium_chat_input.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart'
    show NavScrollCompression;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('§14: the chat composer rides the IME — above it, never '
      'behind it, same pill geometry', (tester) async {
    AppConfig.enableDemoMode();

    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // NOTE: disposed at the END of the body, not via addTearDown — the
    // chat notifier owns periodic timers and Flutter's pending-timer
    // check runs before addTearDown callbacks (same seam as
    // friend_chat_plus_button_test.dart).
    final container = ProviderContainer();
    final user = User(
      id: DemoSeedData.demoUserId,
      username: DemoSeedData.demoUsername,
      email: 'kwesi.mensah@demo.azaman.app',
      token: DemoSeedData.demoToken,
      role: 'USER',
      azmBalance: 12450.00,
      availableBalance: 12450.00,
    );
    container.read(authProvider).setUser(user);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: container.read(themeProvider).themeData,
          home: const FriendChatScreen(
            friendshipId: 'demo-friendship-2',
            friendUsername: 'Bella',
            friendId: 2,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    final composerFinder = find.byType(PremiumChatInput);
    expect(composerFinder, findsOneWidget);
    // §15 — ONE SYSTEM: the composer PILL (the floating surface, not the
    // SafeArea wrapper) carries the SAME band height token as the nav
    // pill (NavScrollCompression.expandedHeight), so the contextual
    // morph reads as the band continuing, not as two unrelated
    // surfaces.
    final pillFinder = find.byWidgetPredicate((w) =>
        w is Container &&
        (w.constraints?.maxHeight ?? double.infinity) ==
            NavScrollCompression.expandedHeight);
    expect(pillFinder, findsOneWidget);
    final restingHeight = tester.getRect(pillFinder).height;

    // Focus the composer's field, then open a 300px keyboard.
    await tester.tap(find.byType(TextField).first);
    tester.view.viewInsets =
        FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final imeTop = 900.0 - 300.0;
    expect(tester.getRect(composerFinder).bottom,
        lessThanOrEqualTo(imeTop + 1));
    // The field is still hit-testable where it renders.
    expect(find.byType(TextField).first.hitTestable(), findsOneWidget);
    // Same pill geometry while riding — the surface is attached to the
    // IME movement, not a shrunken/floating strip.
    expect(tester.getRect(pillFinder).height, restingHeight);

    // Unmount the chat screen so its poll/socket timers are disposed,
    // then dispose the container to cancel the chat notifier's periodic
    // timers — before the binding's no-timers-pending invariant runs.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    container.dispose();
  });
}
