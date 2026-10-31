// AZAMAN — NO PIN WRITE WITHOUT A CONFIRMED PIN STATUS.
//
// The legacy /security/pin/set on backend main reads only `pin` and overwrites
// pinHash: no current-PIN proof, no compare-and-swap, no refusal codes. The
// verifying handler ships with the app-unlock routes, and the only signal this
// client has that they exist is the capabilities read succeeding. When that read
// fails, "no PIN yet" and "rotate an existing PIN" are indistinguishable, so the
// screen must write nothing rather than risk replacing a PIN nobody proved.

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

class _Caps implements AppUnlockGateway {
  _Caps({this.answer, this.fails = false});

  final AppUnlockCapabilities? answer;
  final bool fails;
  int calls = 0;

  @override
  Future<AppUnlockCapabilities> capabilities() async {
    calls++;
    if (fails) throw Exception('404');
    return answer!;
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

Widget _host(_Wire wire, _Caps caps) => ProviderScope(
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('an unconfirmed PIN status writes nothing and says so', (
    tester,
  ) async {
    _sizeForEverything(tester);
    final wire = _Wire();
    final caps = _Caps(fails: true);
    await tester.pumpWidget(_host(wire, caps));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '5678');
    await tester.enterText(find.byType(TextField).at(1), '5678');
    await _tapSave(tester);

    expect(
      wire.countOf('/security/pin/set'),
      0,
      reason:
          'a server that cannot say whether a PIN exists must not be asked '
          'to overwrite one',
    );
    expect(
      find.textContaining('Your PIN status could not be confirmed'),
      findsOneWidget,
      reason: 'the member is told why nothing happened',
    );
    expect(
      find.text('Azaman PIN set successfully'),
      findsNothing,
      reason: 'no success may be reported for a write that was never sent',
    );
    expect(
      caps.calls,
      greaterThan(1),
      reason: 'the status is re-read rather than assumed',
    );
  });

  testWidgets('a confirmed PIN status allows the write, with proof attached', (
    tester,
  ) async {
    _sizeForEverything(tester);
    final wire = _Wire();
    await tester.pumpWidget(_host(wire, _Caps(answer: _withPin)));
    await tester.pumpAndSettle();

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

  testWidgets('a confirmed first-time PIN is created without a current PIN', (
    tester,
  ) async {
    _sizeForEverything(tester);
    final wire = _Wire();
    await tester.pumpWidget(_host(wire, _Caps(answer: _noPin)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '5678');
    await tester.enterText(find.byType(TextField).at(1), '5678');
    await _tapSave(tester);

    expect(wire.countOf('/security/pin/set'), 1);
    expect(wire.bodies.last.containsKey('currentPin'), isFalse);
  });
}
