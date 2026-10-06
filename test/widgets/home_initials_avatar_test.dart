// =============================================================================
// EXPERIENCE PASS §10 — Home avatar: initials only, for now.
//
// The Home greeting header's avatar is a clean circular surface with the
// user's INITIALS — no profile photo, no thick gradient ring, no
// double-border. The photo stays supported elsewhere (profile, drawer,
// P2P); this is a Home presentation decision. The tap must still open the
// profile screen.
// =============================================================================

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show FontLoader;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/screens/profile_screen.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

const _surfaceSize = Size(400, 900);

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final bytes = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final loader = FontLoader('Inter')
    ..addFont(Future<ByteData>.value(
        ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
  _fontsLoaded = true;
}

/// An auth provider that never touches the network: the injected user IS
/// the session.
class _FixedAuth extends AuthProvider {
  _FixedAuth(this.sessionUser);

  final User sessionUser;

  @override
  User? get user => sessionUser;

  @override
  Future<void> fetchUserDetails() async {
    // Keep the session authenticated without a /auth/me round-trip.
  }
}

User _user({String? photo}) => User(
      id: 'u1',
      username: 'pyraxxz',
      email: 'pyraxxz@azaman.test',
      token: 'test-token',
      role: 'USER',
      profilePictureUrl: photo,
    );

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  required User user,
}) async {
  SharedPreferences.setMockInitialValues(
      {'has_seen_flippable_card_hint': true});
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(_surfaceSize);
  final auth = _FixedAuth(user);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => auth),
      balanceDataProvider.overrideWith(
          (ref) => const BalanceData(availableBalance: 100)),
      oracleRateProvider.overrideWith((ref) => 1.0),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: MediaQuery(
          data: const MediaQueryData(size: _surfaceSize),
          child: const Scaffold(body: AzamanHomePage()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 200));
  return container;
}

void main() {
  testWidgets('the avatar renders the initials even when a photo exists',
      (tester) async {
    await _pumpHome(tester, user: _user(photo: 'https://example.com/p.png'));
    // §10: initials-only on Home, for now — "Pyrax" => "P".
    expect(find.descendant(
        of: find.byWidgetPredicate((w) =>
            w is Container &&
            (w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).shape == BoxShape.circle &&
                w.constraints?.maxWidth == 44)),
        matching: find.text('P')), findsOneWidget);
    // The avatar must NOT be a photo: no AzamanNetworkImage inside it.
    expect(find.byType(AzamanNetworkImage), findsNothing);
  });

  testWidgets('the avatar keeps its subtle 1px rim and no gradient ring',
      (tester) async {
    await _pumpHome(tester, user: _user());
    // Exactly one border-decorated circular disc — no nested
    // double-container, no gradient ring (§10's premium-but-understated
    // rule).
    final tp = ThemeProvider();
    final disc = tester.widget<Container>(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            (w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).shape == BoxShape.circle) &&
            w.constraints?.maxWidth == 44,
      ),
    );
    final decoration = disc.decoration! as BoxDecoration;
    expect(decoration.gradient, isNull);
    expect(decoration.border, isNotNull);
    expect(decoration.border!.top.width, 1.0);
    expect(disc.constraints?.maxWidth, 44.0);
  });

  testWidgets('tapping the avatar still opens the profile screen',
      (tester) async {
    await _pumpHome(tester, user: _user());
    final avatarDisc = find.byWidgetPredicate((w) =>
        w is Container &&
        (w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle &&
            w.constraints?.maxWidth == 44));
    expect(avatarDisc, findsOneWidget);
    await tester.tap(avatarDisc);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Hero flight settles into the profile screen; its distinctive
    // content must be present.
    expect(find.byType(ProfileScreen), findsOneWidget);
  });
}
