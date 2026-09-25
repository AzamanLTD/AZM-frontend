// Diagnostic widget test: mounts FriendsHubScreen in demo mode and captures
// any exception thrown during build/layout, so we can see EXACTLY what
// crashes for friend tiles (per user report: "Something went wrong" cards
// appearing in the chat/inbox list).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/config.dart';
import 'package:azaman/data/demo_seed_data.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/screens/friends/friends_hub_screen.dart';

void main() {
  testWidgets('FriendsHubScreen renders without exceptions in demo mode', (tester) async {
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
        child: const MaterialApp(home: FriendsHubScreen()),
      ),
    );

    // Let async fetchFriends()/loadGroups() calls resolve.
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Force the friend provider to actually have data (in case fetchFriends
    // needs a manual trigger the same way login->refreshAll does).
    await container.read(friendProvider).fetchFriends();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    final exception = tester.takeException();
    if (exception != null) {
      // ignore: avoid_print
      print('CAPTURED EXCEPTION: $exception');
      print('STACK: ${exception is Error ? exception.stackTrace : "n/a"}');
    }
    expect(exception, isNull, reason: 'FriendsHubScreen threw during build/layout');
  });
}
