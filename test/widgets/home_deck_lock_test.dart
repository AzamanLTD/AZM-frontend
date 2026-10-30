// THE DECK IS MONEY.
//
// While the local gate is locked the balance deck must not be painted at all —
// not blurred, not dimmed, not present behind an overlay. This suite drives the
// real Home screen with the REAL controller (locked, as a cold start is) and
// proves the card is absent, the deck keeps its 180dp footprint, and the same
// Home unlocks into the card the moment the controller says so.
import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/widgets/home/balance_card_pair.dart';
import 'package:azaman/widgets/home/balance_card_fx.dart';
import 'package:azaman/widgets/home/money_lock_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _surfaceSize = Size(400, 900);

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final bytes = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final loader = FontLoader('Inter')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
  await loader.load();
  _fontsLoaded = true;
}

Future<ProviderContainer> _pumpLockedHome(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'has_seen_flippable_card_hint': true,
    'azaman_theme': 0,
  });
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(_surfaceSize);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      unreadCountProvider.overrideWith((ref) => 0),
      balanceDataProvider.overrideWith(
        (ref) => const BalanceData(availableBalance: 1234.56),
      ),
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
  testWidgets('a cold Home paints no balance: the deck is replaced', (
    tester,
  ) async {
    final container = await _pumpLockedHome(tester);

    expect(container.read(moneyAccessProvider).state, MoneyAccessState.locked);
    expect(
      find.byType(BalanceCardFx),
      findsNothing,
      reason: 'the card face must not be built while locked',
    );
    expect(find.byType(MoneyLockGate), findsOneWidget);
    expect(find.byType(LockedMoneySurface), findsOneWidget);
    // The masked amount the stub would have shown must not be reachable.
    expect(find.textContaining('1,234'), findsNothing);
  });

  testWidgets('the locked deck keeps the 180dp footprint', (tester) async {
    await _pumpLockedHome(tester);

    final gate = tester.getSize(find.byType(MoneyLockGate));
    expect(
      gate.height,
      BalanceCardGeometry.height,
      reason: 'the measured doorway below depends on this height',
    );
  });

  testWidgets('unlocking the controller swaps the real card back in', (
    tester,
  ) async {
    final container = await _pumpLockedHome(tester);
    final access = container.read(moneyAccessProvider);

    final attempt = access.beginUnlock();
    access.finishUnlock(attempt);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(LockedMoneySurface), findsNothing);
    expect(
      find.byType(BalanceCardFx),
      findsWidgets,
      reason: 'the deck returns once the member is unlocked',
    );
  });
}
