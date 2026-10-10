// TASK-B (layout stability) — the doorway composition must be stable.
//
// The Home page's Recent Activity doorway is positioned by a measured
// fill/gap (the deck band + the adaptive spacer keep the doorway at the
// bottom of the first viewport). The measurement probes are UNTRANSFORMED
// layout markers, so the composition is measured during the entrance and
// must be FINAL once the entrance has settled.
//
// Regression contract: past the old fixed 1200ms measurement point, the
// layout must NOT jump or resize. Capturing the relevant geometry right
// after the entrance settles and comparing it after the old measurement
// point pins that — any delayed, purely measurement-driven resize fails
// this test.
import 'dart:io';
import 'dart:typed_data';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/home_summary_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/screens/home_screen.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/services/home_summary_service.dart';
import 'package:azaman/widgets/home/activity_doorway.dart';
import 'package:azaman/widgets/home/home_reminder_deck.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _surfaceSize = Size(400, 900);

bool _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  final inter = await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
  final interLoader = FontLoader('Inter')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(inter).buffer)),
    );
  await interLoader.load();
  final regular =
      await File('assets/fonts/ComicNeue-Regular.ttf').readAsBytes();
  final bold = await File('assets/fonts/ComicNeue-Bold.ttf').readAsBytes();
  final comicLoader = FontLoader('ComicNeue')
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(regular).buffer)),
    )
    ..addFont(
      Future<ByteData>.value(ByteData.view(Uint8List.fromList(bold).buffer)),
    );
  await comicLoader.load();
  _fontsLoaded = true;
}

class _NoopHomeSummaryNotifier extends HomeSummaryNotifier {
  _NoopHomeSummaryNotifier(super.ref, super.service);
}

class _StaticHistoryNotifier extends TransactionHistoryNotifier {
  @override
  Future<void> loadMore() async {}
  @override
  Future<void> refresh() async {}
}

/// The geometry that the measured composition owns: the reminder deck's
/// band (height + top) and the doorway's slot (top + height). If a delayed
/// measurement pass resized anything, these five numbers move.
({double deckH, double deckTop, double doorwayTop, double doorwayH})
_captureGeometry(WidgetTester tester) {
  final deck = find.byType(HomeReminderDeck);
  final doorway = find.byType(RecentActivityDoorway);
  return (
    deckH: tester.getSize(deck).height,
    deckTop: tester.getTopLeft(deck).dy,
    doorwayTop: tester.getTopLeft(doorway).dy,
    doorwayH: tester.getSize(doorway).height,
  );
}

Future<void> _pumpHome(WidgetTester tester, {required bool reducedMotion}) async {
  SharedPreferences.setMockInitialValues({
    'has_seen_flippable_card_hint': true,
    'azaman_theme': 0,
  });
  await tester.runAsync(_loadFonts);
  await tester.binding.setSurfaceSize(_surfaceSize);

  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      transactionHistoryProvider.overrideWith((ref) => _StaticHistoryNotifier()),
      unreadCountProvider.overrideWith((ref) => 0),
      homeSummaryProvider.overrideWith(
        (ref) => _NoopHomeSummaryNotifier(ref, HomeSummaryService()),
      ),
      balanceDataProvider.overrideWith(
        (ref) => const BalanceData(availableBalance: 100),
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
          data: MediaQueryData(
            size: _surfaceSize,
            disableAnimations: reducedMotion,
          ),
          child: const Scaffold(body: AzamanHomePage()),
        ),
      ),
    ),
  );
}

void main() {
  for (final reducedMotion in [true, false]) {
    testWidgets(
      'doorway composition is final once the entrance settles '
      '(reducedMotion: $reducedMotion)',
      (tester) async {
        await _pumpHome(tester, reducedMotion: reducedMotion);
        // First build + the measurement frame.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        // Let the entrance choreography finish (stagger max 300ms +
        // spatial travel 450ms) and the measured composition converge.
        await tester.pump(const Duration(milliseconds: 900));

        final settled = _captureGeometry(tester);

        // Past the OLD fixed 1200ms measurement point: nothing may move.
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 100));
        final afterOldMeasurementPoint = _captureGeometry(tester);

        expect(
          afterOldMeasurementPoint.deckH,
          settled.deckH,
          reason: 'the reminder deck must not resize after the entrance',
        );
        expect(
          afterOldMeasurementPoint.deckTop,
          settled.deckTop,
          reason: 'the reminder deck must not move after the entrance',
        );
        expect(
          afterOldMeasurementPoint.doorwayTop,
          settled.doorwayTop,
          reason: 'the doorway must not move after the entrance',
        );
        expect(
          afterOldMeasurementPoint.doorwayH,
          settled.doorwayH,
          reason: 'the doorway must not resize after the entrance',
        );
      },
    );
  }
}

