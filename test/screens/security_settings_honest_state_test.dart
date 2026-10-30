// AZAMAN — the security screen may only state what the server confirmed.
//
// Two defects lived here, both of the same kind: the UI reported an outcome the
// backend had never granted. "Azaman PIN removed" changed a local bool and
// nothing else, and 2FA showed ON the moment a secret was minted, before any
// code had ever been checked. These tests drive real responses and assert the
// screen's claim matches them.

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

/// Records what the screen sent and answers from a small table.
class _Wire {
  /// The disable route defaults to a REFUSAL, which is what this suite is
  /// about; a 200 here would mean the server accepted the code.
  _Wire({this.setupStatus = 201, this.verifyStatus = 200, this.status = 400});

  final int setupStatus;
  final int verifyStatus;
  final int status;

  final List<String> paths = [];

  MockClient get client => MockClient((request) async {
    paths.add(request.url.path);
    final path = request.url.path;
    if (path.endsWith('/security/2fa/setup')) {
      return http.Response(
        jsonEncode({
          'data': {
            'secret': 'JBSWY3DPEHPK3PXP',
            'otpauthUrl':
                'otpauth://totp/Azaman?secret=JBSWY3DPEHPK3PXP&issuer=Azaman',
          },
        }),
        setupStatus,
      );
    }
    if (path.endsWith('/security/2fa/verify')) {
      return http.Response(jsonEncode({'success': true}), verifyStatus);
    }
    if (path.endsWith('/security/2fa/disable')) {
      return http.Response(
        jsonEncode({'success': false, 'message': 'Invalid code'}),
        status,
      );
    }
    if (path.endsWith('/security/pin/set')) {
      return http.Response(jsonEncode({'success': true}), 200);
    }
    if (path.endsWith('/security/sessions')) {
      return http.Response(jsonEncode({'sessions': []}), 200);
    }
    return http.Response(jsonEncode({}), 200);
  });
}

Widget _host(_Wire wire) => ProviderScope(
  overrides: [
    securityApiClientProvider.overrideWithValue(ApiClient(client: wire.client)),
    authProvider.overrideWith((ref) => AuthProvider()),
  ],
  child: const MaterialApp(home: SecuritySettingsScreen()),
);

Finder _authenticatorSwitch() => find.descendant(
  of: find
      .ancestor(of: find.text('Google Authenticator'), matching: find.byType(Row))
      .first,
  matching: find.byType(Switch),
);

bool _switchValue(WidgetTester tester, String label) {
  final row = find
      .ancestor(of: find.text(label), matching: find.byType(Row))
      .first;
  final switches = tester.widgetList<Switch>(
    find.descendant(of: row, matching: find.byType(Switch)),
  );
  return switches.first.value;
}

/// Drags the section into view. The screen is one long ListView and its
/// children are unmounted when scrolled away, so an assertion about the 2FA
/// switch has to bring it back before looking for it.
/// A tall surface keeps the whole screen mounted: these tests are about what the
/// screen CLAIMS, not about scrolling.
void _sizeForEverything(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Taps the switch that belongs to the Google Authenticator row, not whichever
/// switch happens to be first in the tree.
Future<void> _tapAuthenticatorSwitch(WidgetTester tester) async {
  await tester.tap(_authenticatorSwitch());
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The shared client reads the access token from secure storage before every
    // request; without a mock the read throws and no request is ever made.
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('minting a secret does not switch 2FA on', (tester) async {
    final wire = _Wire();
    _sizeForEverything(tester);
    await tester.pumpWidget(_host(wire));
    await tester.pump(const Duration(milliseconds: 100));

    await _tapAuthenticatorSwitch(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      wire.paths.any((p) => p.endsWith('/security/2fa/setup')),
      isTrue,
      reason: 'the setup call is what mints the secret',
    );
    expect(
      find.text('Not enabled yet — confirm a code below'),
      findsOneWidget,
      reason: 'a secret is not protection until a code from it is confirmed',
    );
    expect(
      _switchValue(tester, 'Google Authenticator'),
      isFalse,
      reason: 'the switch must not read ON before verification',
    );
    expect(
      wire.paths.any((p) => p.endsWith('/security/2fa/verify')),
      isFalse,
      reason: 'nothing may verify on the member behalf',
    );
  });

  testWidgets('the switch moves only after the server confirms a code', (
    tester,
  ) async {
    final wire = _Wire();
    _sizeForEverything(tester);
    await tester.pumpWidget(_host(wire));
    await tester.pump(const Duration(milliseconds: 100));

    await _tapAuthenticatorSwitch(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.tap(find.text('Verify & Enable'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      wire.paths.any((p) => p.endsWith('/security/2fa/verify')),
      isTrue,
    );
    expect(_switchValue(tester, 'Google Authenticator'), isTrue);
    expect(
      find.text('On — a code is required when you sign in'),
      findsOneWidget,
    );
  });

  testWidgets('a refused disable leaves 2FA on and says so', (tester) async {
    final wire = _Wire();
    _sizeForEverything(tester);
    await tester.pumpWidget(_host(wire));
    await tester.pump(const Duration(milliseconds: 100));

    // Enable first, through the real path.
    await _tapAuthenticatorSwitch(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.tap(find.text('Verify & Enable'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_switchValue(tester, 'Google Authenticator'), isTrue);

    // Now try to turn it off; the server refuses.
    await _tapAuthenticatorSwitch(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField).last, '000000');
    await tester.tap(find.text('Turn off'));
    await tester.pump();
    // Snackbars queue, and this screen's own load notices can be ahead of the
    // refusal: give the queue time to reach the message under test.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(
      wire.paths.any((p) => p.endsWith('/security/2fa/disable')),
      isTrue,
    );
    expect(
      _switchValue(tester, 'Google Authenticator'),
      isTrue,
      reason: 'a refused disable must not leave the screen claiming it is off',
    );
    expect(
      find.text('Invalid code'),
      findsOneWidget,
      reason: 'the server reason must reach the member',
    );
  });

  testWidgets('the PIN tile offers no removal it cannot perform', (
    tester,
  ) async {
    final wire = _Wire();
    _sizeForEverything(tester);
    await tester.pumpWidget(_host(wire));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('Set PIN').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Azaman PIN active'), findsOneWidget);
    expect(
      find.text('Remove'),
      findsNothing,
      reason: 'there is no /security/pin/remove endpoint to call',
    );
    expect(find.text('Change it above'), findsOneWidget);
    expect(
      wire.paths.any((p) => p.endsWith('/security/pin/set')),
      isTrue,
    );
  });
}
