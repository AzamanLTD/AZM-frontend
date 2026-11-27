// WP-L — screen-level proof for the savings goal sheet.
//
// The chain under test is the real one:
//   goal sheet -> Fund tile -> amount prompt -> SlideToConfirm
//     -> AzamanBiometricGate.run -> _submit -> postFinancial
//
// The only stubs are platform boundaries that do not exist in a test host:
// SharedPreferences (the biometric opt-in flag lives there) and the ApiClient
// provider. Nothing in the production authorization path is bypassed.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/money_refusal_copy.dart';
import 'package:azaman/widgets/savings_goal_sheet.dart';
import 'package:azaman/widgets/slide_to_confirm.dart';

import '../support/money_access_test_support.dart';

/// Stubs the local_auth platform channel — a boundary that does not exist in a
/// test host. The production gate logic itself is untouched.
void _mockBiometrics({required bool authenticateSucceeds}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/local_auth'),
    (call) async {
      switch (call.method) {
        // local_auth expects a List<String> here, not a bool: returning the
        // wrong type makes canCheckBiometrics throw, isAvailable false, and the
        // gate fall through to "biometrics unavailable" (which allows the
        // action). Type it correctly so the real gate runs.
        case 'getAvailableBiometrics':
          return <String>['fingerprint'];
        case 'canCheckBiometrics':
        case 'isDeviceSupported':
          return true;
        case 'authenticate':
          return authenticateSucceeds;
        default:
          return null;
      }
    },
  );
}

final _goal = <String, dynamic>{
  'id': 'goal-1',
  'name': 'Rent 2027',
  'status': 'ACTIVE',
  'frequency': 'MONTHLY',
  'frequencyAmount': 250.0,
  'currentAmountGhs': 1250.0,
  'targetAmountGhs': 5000.0,
  'isLocked': false,
};

/// Counts every financial dispatch and answers with a canned body.
class _CountingApi extends ApiClient {
  _CountingApi({this.body = const {'success': true}, this.error});

  final Map<String, dynamic> body;
  final Object? error;
  int calls = 0;
  final List<String> endpoints = <String>[];

  @override
  Future<http.Response> postFinancial(
    String endpoint,
    Map<String, dynamic> payload, {
    required String operationType,
    FinancialOperationRef? ref,
    bool requireAuth = true,
    Map<String, String>? headers,
    bool failClosedOnPendingFingerprintChange = false,
  }) async {
    calls++;
    endpoints.add(endpoint);
    if (error != null) throw error!;
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

Future<void> _pumpSheet(WidgetTester tester, ApiClient api) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        unlockedMoneyAccess(),
        apiClientProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => SavingsGoalSheet.show(
                context,
                goal: _goal,
                onChanged: () {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _openFundPrompt(WidgetTester tester, {String amount = '10'}) async {
  await tester.tap(find.text('Fund').first);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, amount);
  await tester.pumpAndSettle();
}

/// Completes the slide exactly as a customer does: press, travel, release.
Future<void> _slide(WidgetTester tester) async {
  final slide = find.byType(SlideToConfirm);
  expect(slide, findsOneWidget);
  final rect = tester.getRect(slide);
  final gesture = await tester.startGesture(
    Offset(rect.left + 24, rect.center.dy),
  );
  for (var i = 0; i < 12; i++) {
    await gesture.moveBy(Offset((rect.width - 48) / 12, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // The biometric opt-in flag lives in SharedPreferences. With it absent the
    // gate runs the action immediately, which is the production behaviour for
    // a customer who has not opted in.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('the Fund tile opens the amount prompt for that goal',
      (tester) async {
    final api = _CountingApi();
    await _pumpSheet(tester, api);
    await tester.tap(find.text('Fund').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Fund "Rent 2027"'), findsWidgets);
    expect(find.byType(TextField), findsWidgets);
    expect(find.byType(SlideToConfirm), findsOneWidget);
    expect(api.calls, 0, reason: 'opening a prompt must not move money');
  });

  testWidgets('a completed slide dispatches exactly one request',
      (tester) async {
    final api = _CountingApi();
    await _pumpSheet(tester, api);
    await _openFundPrompt(tester);
    await _slide(tester);

    expect(api.calls, 1, reason: 'one deliberate slide, one request');
    expect(api.endpoints.single, contains('/savings/goals/'));
    expect(api.endpoints.single, contains('/deposit'));
  });

  testWidgets('an incomplete gesture dispatches nothing', (tester) async {
    final api = _CountingApi();
    await _pumpSheet(tester, api);
    await _openFundPrompt(tester);

    final slide = find.byType(SlideToConfirm);
    final rect = tester.getRect(slide);
    final gesture = await tester.startGesture(
      Offset(rect.left + 24, rect.center.dy),
    );
    // Travel only a third of the track, then release.
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(Offset(rect.width / 12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(api.calls, 0, reason: 'a partially dragged thumb is not consent');
  });

  testWidgets('a refusal renders the canonical copy, not the raw message',
      (tester) async {
    final api = _CountingApi(body: {
      'success': false,
      'code': 'NATIVE_GHS_SHORTFALL_BACKING_UNAVAILABLE',
      'message': 'raw backend text that must never reach a customer',
    });
    await _pumpSheet(tester, api);
    await _openFundPrompt(tester);
    await _slide(tester);

    final copy =
        refusalCopyFor('NATIVE_GHS_SHORTFALL_BACKING_UNAVAILABLE')!;
    expect(api.calls, 1);
    expect(find.textContaining(copy.message), findsWidgets);
    expect(find.textContaining('raw backend text'), findsNothing);
  });

  testWidgets('an ambiguous outcome never reads as a failure', (tester) async {
    final api = _CountingApi(error: http.ClientException('connection reset'));
    await _pumpSheet(tester, api);
    await _openFundPrompt(tester);
    await _slide(tester);

    expect(find.textContaining('could not confirm'), findsWidgets);
    expect(find.textContaining('failed'), findsNothing);
  });

  testWidgets('a cancelled authorization does not dispatch, and allows retry',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Arm the real opt-in flag through the same API the settings screen uses.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_lock_enabled', true);
    _mockBiometrics(authenticateSucceeds: false);

    final api = _CountingApi();
    await _pumpSheet(tester, api);
    await _openFundPrompt(tester);
    await _slide(tester);

    expect(api.calls, 0, reason: 'a cancelled gate must not move money');
    expect(find.textContaining('Authentication failed'), findsWidgets);

    // The slide re-arms after a cancel, so a deliberate retry can go through.
    _mockBiometrics(authenticateSucceeds: true);
    await _slide(tester);
    expect(api.calls, 1, reason: 'an authorized retry dispatches once');
  });

  testWidgets('the same slide cannot dispatch twice', (tester) async {
    final api = _CountingApi();
    await _pumpSheet(tester, api);
    await _openFundPrompt(tester);
    await _slide(tester);
    expect(api.calls, 1);

    // Drive another full gesture if any slide control is still mounted, and
    // settle: no second dispatch and no fresh operation may appear.
    if (find.byType(SlideToConfirm).evaluate().isNotEmpty) {
      await _slide(tester);
    }
    await tester.pumpAndSettle();
    expect(api.calls, 1, reason: 'one operation, one durable identity');
  });
}
