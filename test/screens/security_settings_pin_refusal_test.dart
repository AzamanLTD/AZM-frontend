// AZAMAN — THE THREE PIN REFUSALS THAT MUST NOT BE SWALLOWED.
//
// The screen already spoke for PIN_CURRENT_REQUIRED, PIN_INVALID, PIN_LOCKED
// and PIN_FORMAT_INVALID. Three codes from the backend's `setPin` had no
// deliberate handling, and two of them mean the client's view of the account is
// older than the server's:
//
//   PIN_ROTATION_CONFLICT — the compare-and-swap lost. The PIN changed
//                           elsewhere; nothing here may claim a change.
//   PIN_NOT_CONFIGURED    — the server says no PIN exists, so prompting for a
//                           current one is a dead end.
//   PIN_REQUIRED          — the proof was missing from the request. Name the
//                           missing input; do not guess a cause.
//
// Asserted here as user-visible outcomes (what is on screen, what the server
// was asked, what the member's typing survived), never as string constants.

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

/// Answers the PIN write with one specific refusal and records every path.
class _Wire {
  _Wire({required this.status, required this.code});

  final int status;
  final String code;
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
    if (request.url.path.endsWith('/security/pin/set')) {
      return http.Response(
        jsonEncode({
          'success': false,
          'code': code,
          'message': 'PIN change was refused.',
        }),
        status,
      );
    }
    if (request.url.path.endsWith('/security/sessions')) {
      return http.Response(jsonEncode({'sessions': []}), 200);
    }
    return http.Response(jsonEncode({}), 200);
  });

  int countOf(String suffix) =>
      paths.where((p) => p.endsWith(suffix)).length;
}

/// Capabilities answered from a queue, so the screen's first read and the
/// refresh after a refusal can disagree — which is the whole point.
class _CapsGateway implements AppUnlockGateway {
  _CapsGateway(this.answers);

  final List<AppUnlockCapabilities> answers;
  int calls = 0;

  @override
  Future<AppUnlockCapabilities> capabilities() async {
    final answer = answers[calls < answers.length ? calls : answers.length - 1];
    calls++;
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

const AppUnlockCapabilities _pinConfigured = AppUnlockCapabilities(
  pinConfigured: true,
  authenticatorConfigured: false,
  phoneVerified: false,
  smsUnlockAvailable: false,
);

Widget _host(_Wire wire, _CapsGateway gateway) => ProviderScope(
  overrides: [
    securityApiClientProvider.overrideWithValue(ApiClient(client: wire.client)),
    appUnlockGatewayProvider.overrideWithValue(gateway),
    authProvider.overrideWith((ref) => AuthProvider()),
  ],
  child: const MaterialApp(home: SecuritySettingsScreen()),
);

void _sizeForEverything(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

String _textIn(WidgetTester tester, int index) =>
    tester.widget<TextField>(find.byType(TextField).at(index)).controller!.text;

/// Fills current/new/confirm and taps the write button.
Future<void> _attemptRotation(
  WidgetTester tester, {
  String current = '1234',
  String next = '5678',
}) async {
  await tester.enterText(find.byType(TextField).at(0), current);
  await tester.enterText(find.byType(TextField).at(1), next);
  await tester.enterText(find.byType(TextField).at(2), next);
  await tester.tap(find.text('Set PIN').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('a rotation conflict says the PIN changed elsewhere and re-asks', (
    tester,
  ) async {
    _sizeForEverything(tester);
    final wire = _Wire(status: 409, code: 'PIN_ROTATION_CONFLICT');
    final gateway = _CapsGateway([_pinConfigured]);
    await tester.pumpWidget(_host(wire, gateway));
    await tester.pumpAndSettle();
    expect(
      find.text('Current 4-digit PIN'),
      findsOneWidget,
      reason: 'a configured account is asked for the PIN being replaced',
    );
    final readsBefore = gateway.calls;

    await _attemptRotation(tester);

    expect(
      find.textContaining('changed somewhere else'),
      findsOneWidget,
      reason: 'the member is told why the change was refused',
    );
    expect(
      find.text('Azaman PIN set successfully'),
      findsNothing,
      reason: 'a refusal may never be reported as a saved PIN',
    );
    expect(
      gateway.calls,
      greaterThan(readsBefore),
      reason: 'the stale view is re-read from the server, not assumed',
    );
    expect(
      _textIn(tester, 1),
      '5678',
      reason: 'the new PIN the member typed is theirs to keep',
    );
    expect(
      _textIn(tester, 0),
      '',
      reason: 'the proof is known-stale, so it is cleared rather than resent',
    );
    expect(
      find.text('Azaman PIN active'),
      findsOneWidget,
      reason: 'the PIN still exists; only this change failed',
    );
  });

  testWidgets('one refusal is one write, never a second verification path', (
    tester,
  ) async {
    _sizeForEverything(tester);
    final wire = _Wire(status: 409, code: 'PIN_ROTATION_CONFLICT');
    final gateway = _CapsGateway([_pinConfigured]);
    await tester.pumpWidget(_host(wire, gateway));
    await tester.pumpAndSettle();

    await _attemptRotation(tester);

    expect(wire.countOf('/security/pin/set'), 1);
    expect(
      wire.countOf('/security/pin/verify'),
      0,
      reason: 'the write verifies the current PIN itself; a rival check '
          'could disagree with the one guarding the hash',
    );
    final sent = wire.bodies.where((b) => b.containsKey('pin')).last;
    expect(sent['pin'], '5678');
    expect(
      sent['currentPin'],
      '1234',
      reason: 'the contract stays { pin, currentPin }',
    );
  });

  testWidgets('an account with no PIN stops being asked for a current one', (
    tester,
  ) async {
    _sizeForEverything(tester);
    final wire = _Wire(status: 409, code: 'PIN_NOT_CONFIGURED');
    // The first read is our stale view; the refresh is the server's truth.
    final gateway = _CapsGateway([
      _pinConfigured,
      const AppUnlockCapabilities(
        pinConfigured: false,
        authenticatorConfigured: false,
        phoneVerified: false,
        smsUnlockAvailable: false,
      ),
    ]);
    await tester.pumpWidget(_host(wire, gateway));
    await tester.pumpAndSettle();
    expect(find.text('Current 4-digit PIN'), findsOneWidget);

    await _attemptRotation(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('Current 4-digit PIN'),
      findsNothing,
      reason: 'the server said no PIN exists, so the proof prompt is a lie',
    );
    expect(find.text('Azaman PIN active'), findsNothing);
    expect(
      find.textContaining('No Azaman PIN is set'),
      findsOneWidget,
      reason: 'the member is pointed at the initial setup instead',
    );
    expect(find.text('Azaman PIN set successfully'), findsNothing);
    expect(
      _textIn(tester, 1),
      '5678',
      reason: 'saving again is one tap, because the new PIN was kept',
    );
    expect(wire.countOf('/security/pin/set'), 1);
  });

  testWidgets('a missing current PIN is named, and nothing is retried', (
    tester,
  ) async {
    _sizeForEverything(tester);
    final wire = _Wire(status: 400, code: 'PIN_REQUIRED');
    final gateway = _CapsGateway([_pinConfigured]);
    await tester.pumpWidget(_host(wire, gateway));
    await tester.pumpAndSettle();
    final readsBefore = gateway.calls;

    await _attemptRotation(tester);

    expect(
      find.textContaining('current PIN was missing'),
      findsOneWidget,
      reason: 'the missing input is named rather than a cause being invented',
    );
    expect(find.text('Azaman PIN set successfully'), findsNothing);
    expect(
      gateway.calls,
      readsBefore,
      reason: 'a missing field is not evidence that our account view is stale',
    );
    expect(
      find.text('Current 4-digit PIN'),
      findsOneWidget,
      reason: 'the honest state is still "this account has a PIN"',
    );
    expect(wire.countOf('/security/pin/set'), 1);
  });
}
