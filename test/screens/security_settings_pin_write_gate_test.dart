// AZAMAN — NO PIN FORM, AND NO PIN WRITE, WITHOUT A CONFIRMED PIN STATUS.
//
// The legacy /security/pin/set on backend main reads only `pin` and overwrites
// pinHash: no current-PIN proof, no compare-and-swap, no refusal codes. The
// verifying handler ships with the app-unlock routes, and the only signal this
// client has that they exist is the capabilities read succeeding. When that read
// fails, "no PIN yet" and "rotate an existing PIN" are indistinguishable.
//
// Two consequences are pinned here:
//
//   • the screen does not render a PIN form it cannot honestly label — an empty
//     first-time form over an existing secret is a false statement about the
//     account, not a harmless default;
//   • nothing is written to /security/pin/set until the server says which case
//     this is, and then the request carries exactly the proof that case needs.
//
// The unavailable state is asserted as what the member sees before they touch
// anything, plus the Retry that can only ask the server again.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/screens/security_settings.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/app_unlock_gateway.dart';
import 'package:azaman/services/money_unlock_flow.dart';

/// Accepts anything, so a wrongly sent write would look like success.
class _Wire {
  final List<String> paths = [];
  final List<Map<String, dynamic>> bodies = [];

  MockClient get client => MockClient((request) async {
    paths.add(request.url.path);
    if (request.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(request.body);
        if (decoded is Map<String, dynamic>) bodies.add(decoded);
      } catch (_) {
        // Not part of this contract.
      }
    }
    if (request.url.path.endsWith('/security/sessions')) {
      return http.Response(jsonEncode({'sessions': []}), 200);
    }
    return http.Response(jsonEncode({'success': true}), 200);
  });

  int countOf(String suffix) => paths.where((p) => p.endsWith(suffix)).length;
}

/// Answers the capability read from a queue, or fails while [error] is set.
class _Caps implements AppUnlockGateway {
  _Caps(this.answers, {this.error});

  final List<AppUnlockCapabilities> answers;

  /// While non-null every read throws this. Clearing it is how a test models
  /// the network or the route coming back.
  Object? error;
  int calls = 0;

  @override
  Future<AppUnlockCapabilities> capabilities() async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    final index = calls - 1 < answers.length ? calls - 1 : answers.length - 1;
    return answers[index];
  }

  @override
  Future<void> verifyPin(String pin) async {}
  @override
  Future<void> verifyTotp(String token) async {}
  @override
  Future<AppUnlockSmsChallenge> sendSmsChallenge() async =>
      throw UnimplementedError();
  @override
  Future<void> verifySmsChallenge({
    required String challengeId,
    required String code,
  }) async {}
}

/// Answers only when the test completes [gate], so the loading state is visible.
class _GatedCaps implements AppUnlockGateway {
  _GatedCaps(this.answer);

  final AppUnlockCapabilities answer;
  final Completer<void> gate = Completer<void>();

  @override
  Future<AppUnlockCapabilities> capabilities() async {
    await gate.future;
    return answer;
  }

  @override
  Future<void> verifyPin(String pin) async {}
  @override
  Future<void> verifyTotp(String token) async {}
  @override
  Future<AppUnlockSmsChallenge> sendSmsChallenge() async =>
      throw UnimplementedError();
  @override
  Future<void> verifySmsChallenge({
    required String challengeId,
    required String code,
  }) async {}
}

const AppUnlockCapabilities _noPin = AppUnlockCapabilities(
  pinConfigured: false,
  authenticatorConfigured: false,
  phoneVerified: false,
  smsUnlockAvailable: false,
);

const AppUnlockCapabilities _withPin = AppUnlockCapabilities(
  pinConfigured: true,
  authenticatorConfigured: false,
  phoneVerified: false,
  smsUnlockAvailable: false,
);

Widget _host(_Wire wire, AppUnlockGateway caps) => ProviderScope(
  overrides: [
    securityApiClientProvider.overrideWithValue(ApiClient(client: wire.client)),
    appUnlockGatewayProvider.overrideWithValue(caps),
    authProvider.overrideWith((ref) => AuthProvider()),
  ],
  child: const MaterialApp(home: SecuritySettingsScreen()),
);

void _sizeForEverything(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.text('Set PIN').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tapRetry(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('pin-status-retry')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// The unavailable explanation, as the member reads it before acting.
final _unavailableCopy = find.textContaining(
  'could not confirm whether this account has a PIN',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('a 404 from capabilities is an unavailable PIN, not a new one', (
    tester,
  ) async {
    _sizeForEverything(tester);
    final wire = _Wire();
    await tester.pumpWidget(
      _host(
        wire,
        _Caps(
          [_noPin],
          error: ApiException(
            message: 'Not Found',
            statusCode: 404,
            code: 'NOT_FOUND',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('pin-status-unavailable')),
      findsOneWidget,
      reason: 'the backend main has no app-unlock routes; say so',
    );
    expect(_unavailableCopy, findsOneWidget);
    expect(
      find.text('New 4-digit PIN'),
      findsNothing,
      reason: 'no form may imply this account has no PIN',
    );
    expect(
      find.text('Azaman PIN active'),
      findsNothing,
      reason: 'nor may it imply the PIN is confirmed to exist',
    );
    expect(find.text('Set PIN'), findsNothing);
    expect(wire.countOf('/security/pin/set'), 0);
  });

  testWidgets('a transient network failure reads the same way as a 404', (
    tester,
  ) async {
    _sizeForEverything(tester);
    final wire = _Wire();
    await tester.pumpWidget(
      _host(wire, _Caps([_noPin], error: Exception('connection reset'))),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('pin-status-unavailable')),
      findsOneWidget,
    );
    expect(_unavailableCopy, findsOneWidget);
    expect(find.text('New 4-digit PIN'), findsNothing);
    expect(
      find.byKey(const ValueKey('pin-status-retry')),
      findsOneWidget,
      reason: 'the only honest action is to ask again',
    );
  });

  testWidgets('the explanation precedes any attempt to save', (tester) async {
    _sizeForEverything(tester);
    final wire = _Wire();
    await tester.pumpWidget(
      _host(wire, _Caps([_noPin], error: Exception('offline'))),
    );
    await tester.pumpAndSettle();

    // Nothing has been tapped: this is the state on arrival.
    expect(_unavailableCopy, findsOneWidget);
    expect(
      find.textContaining('Nothing has been changed'),
      findsOneWidget,
      reason: 'the member is told the account is untouched',
    );
  });

  testWidgets('no write happens while the status is unavailable', (
    tester,
  ) async {
    _sizeForEverything(tester);
    final wire = _Wire();
    final caps = _Caps([_noPin], error: Exception('offline'));
    await tester.pumpWidget(_host(wire, caps));
    await tester.pumpAndSettle();

    await _tapRetry(tester);
    expect(caps.calls, greaterThan(1), reason: 'Retry asks the server');
    expect(wire.countOf('/security/pin/set'), 0);
    expect(find.text('Azaman PIN set successfully'), findsNothing);
  });

  testWidgets('retry recovers into confirmed first-time setup', (tester) async {
    _sizeForEverything(tester);
    final wire = _Wire();
    final caps = _Caps([_noPin], error: Exception('offline'));
    await tester.pumpWidget(_host(wire, caps));
    await tester.pumpAndSettle();
    expect(_unavailableCopy, findsOneWidget);

    caps.error = null;
    await _tapRetry(tester);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('pin-status-unavailable')),
      findsNothing,
      reason: 'the confirmed answer replaces the unavailable state',
    );
    expect(find.text('New 4-digit PIN'), findsOneWidget);
    expect(
      find.text('Current 4-digit PIN'),
      findsNothing,
      reason: 'nothing exists yet to prove',
    );

    await tester.enterText(find.byType(TextField).at(0), '5678');
    await tester.enterText(find.byType(TextField).at(1), '5678');
    await _tapSave(tester);

    expect(wire.countOf('/security/pin/set'), 1);
    expect(wire.bodies.last['pin'], '5678');
    expect(wire.bodies.last.containsKey('currentPin'), isFalse);
  });

  testWidgets('retry recovers into confirmed rotation', (tester) async {
    _sizeForEverything(tester);
    final wire = _Wire();
    final caps = _Caps([_withPin], error: Exception('offline'));
    await tester.pumpWidget(_host(wire, caps));
    await tester.pumpAndSettle();
    expect(_unavailableCopy, findsOneWidget);
    expect(find.text('Azaman PIN active'), findsNothing);

    caps.error = null;
    await _tapRetry(tester);
    await tester.pumpAndSettle();

    expect(find.text('Azaman PIN active'), findsOneWidget);
    expect(find.text('Current 4-digit PIN'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '1234');
    await tester.enterText(find.byType(TextField).at(1), '5678');
    await tester.enterText(find.byType(TextField).at(2), '5678');
    await _tapSave(tester);

    expect(wire.countOf('/security/pin/set'), 1);
    expect(wire.bodies.last['pin'], '5678');
    expect(
      wire.bodies.last['currentPin'],
      '1234',
      reason: 'a rotation carries the proof the server verifies',
    );
  });

  testWidgets('a confirmed existing PIN is represented as active', (
    tester,
  ) async {
    _sizeForEverything(tester);
    await tester.pumpWidget(_host(_Wire(), _Caps([_withPin])));
    await tester.pumpAndSettle();

    expect(find.text('Azaman PIN active'), findsOneWidget);
    expect(find.byKey(const ValueKey('pin-status-unavailable')), findsNothing);
    expect(find.text('Current 4-digit PIN'), findsOneWidget);
  });

  testWidgets('a confirmed first-time account gets no current-PIN prompt', (
    tester,
  ) async {
    _sizeForEverything(tester);
    await tester.pumpWidget(_host(_Wire(), _Caps([_noPin])));
    await tester.pumpAndSettle();

    expect(find.text('New 4-digit PIN'), findsOneWidget);
    expect(find.text('Current 4-digit PIN'), findsNothing);
    expect(find.text('Azaman PIN active'), findsNothing);
    expect(find.byKey(const ValueKey('pin-status-unavailable')), findsNothing);
  });

  testWidgets('rotation carries both fields, first-time creation carries one', (
    tester,
  ) async {
    _sizeForEverything(tester);
    final wire = _Wire();
    await tester.pumpWidget(_host(wire, _Caps([_noPin])));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '4321');
    await tester.enterText(find.byType(TextField).at(1), '4321');
    await _tapSave(tester);

    expect(wire.countOf('/security/pin/set'), 1);
    expect(wire.bodies.last.keys.toSet(), {'pin'});
    expect(
      wire.countOf('/security/pin/verify'),
      0,
      reason: 'a second verification path can disagree with the write',
    );
  });

  testWidgets('loading is its own state, not an empty account', (tester) async {
    _sizeForEverything(tester);
    final wire = _Wire();
    final caps = _GatedCaps(_noPin);
    await tester.pumpWidget(_host(wire, caps));
    await tester.pump();

    expect(
      find.textContaining('Checking your PIN status'),
      findsOneWidget,
      reason: 'unknown is not "nothing configured"',
    );
    expect(find.text('New 4-digit PIN'), findsNothing);
    expect(find.byKey(const ValueKey('pin-status-retry')), findsNothing);

    caps.gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('New 4-digit PIN'), findsOneWidget);
  });
}
