// =============================================================================
// AZAMAN — UNIFIED SEND: VISUAL CAPTURES (320 / 360 / 390 dp)
//
// Deliberate, reviewable golden ADDITIONS for the Send composer journey.
// Three phone widths × three stages (compose, review, success) = 9 rasters.
// Generated once with `flutter test --update-goldens` on the pinned engine;
// any later regeneration must be a reviewable diff, never a green-maker.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/send_money_screen.dart';
import 'package:azaman/services/recipient_discovery_service.dart';

const _storageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

class _FixedAuth extends AuthProvider {
  _FixedAuth(this.sessionUser);
  final User sessionUser;

  @override
  User? get user => sessionUser;

  @override
  Future<void> fetchUserDetails() async {}
}

class _FakeFriends extends FriendProvider {
  _FakeFriends(super.ref) {
    friends = [];
    isLoading = false;
  }

  @override
  Future<void> refreshAll() async {}
}

User _user() => User(
      id: '7',
      username: 'me',
      email: 'me@example.com',
      token: 'tok',
      role: 'USER',
      azamanId: 'AZM-999999999',
      availableBalance: 50.0,
    );

const _sizes = {
  '320': Size(320, 692),
  '360': Size(360, 800),
  '390': Size(390, 844),
};

SendMoneyScreen _screen() => SendMoneyScreen.toFriend(
      recipient: SendRecipient(
        username: 'ama',
        displayName: 'Ama Mensah',
        userId: 101,
        friendshipId: 'fs-1',
        source: SendRecipientSource.friend,
      ),
      sendOverride: (friendshipId, amount, reference, token) async =>
          {'success': true},
    );

Future<void> _pump(WidgetTester tester, Size size) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
    if (call.method == 'read') return 'mock-token';
    return null;
  });
  SharedPreferences.setMockInitialValues({'azaman_theme': 1});
  final tp = ThemeProvider();
  tester.view
    ..physicalSize = size * 3.0
    ..devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FixedAuth(_user())),
        friendProvider.overrideWith((ref) => _FakeFriends(ref)),
        themeProvider.overrideWith((ref) => tp),
      ],
      child: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(child: _screen()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(
  WidgetTester tester,
  String width,
  String stage,
) async {
  final size = _sizes[width]!;
  await _pump(tester, size);

  if (stage != 'compose') {
    // Keypad — same drive as the green composer UX suite.
    for (final key in const ['5', '.', '0', '0']) {
      await tester.tap(find.text(key).first);
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('send-cta-Review')));
    await tester.pumpAndSettle();
  }

  if (stage == 'success') {
    await tester.enterText(
        find.byKey(const ValueKey('send-reference-field')), 'Jollof money');
    await tester.pump();
    await tester.tap(
        find.byKey(const ValueKey('send-cta-Send 5.00 USDC')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-success-icon')), findsOneWidget);
  }

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('../goldens/send/${width}dp_$stage.png'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final width in const ['320', '360', '390']) {
    for (final stage in const ['compose', 'review', 'success']) {
      testWidgets('capture $width dp — $stage', (tester) async {
        await _capture(tester, width, stage);
      });
    }
  }
}
