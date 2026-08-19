// Diagnostic widget test: mounts FriendChatScreen in demo mode, taps the
// LiquidMenuButton (+ attach button) inside PremiumChatInput, and captures
// any exception thrown during build/layout/paint. Per user report: tapping
// the + button in a friend chat shows a red "Something went wrong" card.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/config.dart';
import 'package:azaman/data/demo_seed_data.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/friends/friend_chat_screen.dart';

void main() {
  testWidgets('FriendChatScreen + LiquidMenuButton tap does not throw', (tester) async {
    AppConfig.enableDemoMode();

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

    var exception = tester.takeException();
    if (exception != null) {
      // ignore: avoid_print
      print('CAPTURED EXCEPTION (initial build): $exception');
    }

    // Find the LiquidMenuButton's GestureDetector (the + trigger) and tap it.
    final plusFinder = find.byIcon(Icons.add);
    if (plusFinder.evaluate().isNotEmpty) {
      await tester.tap(plusFinder.first, warnIfMissed: false);
      await tester.pump(); // start open animation
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    } else {
      // ignore: avoid_print
      print('COULD NOT FIND + BUTTON (Icons.add) IN WIDGET TREE');
    }

    exception = tester.takeException();
    if (exception != null) {
      // ignore: avoid_print
      print('CAPTURED EXCEPTION (after tap): $exception');
      if (exception is Error) {
        // ignore: avoid_print
        print('STACK: ${exception.stackTrace}');
      }
    }
    expect(exception, isNull, reason: 'LiquidMenuButton threw during open');
  });
}
