// Dine-in tab pay carries the second factor the route requires (require2FA).
// Before, the app sent only {tipUsdc}, so every tab payment was refused 401.
// A challenge or a refused factor restores the tab and rethrows (the prompt
// asks again; nothing was paid); a paid tab reloads.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:azaman/providers/marketplace_extensions_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/widgets/security/second_factor.dart';

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _tab(String status) => {
  'tab': {
    'id': 't-1',
    'status': status,
    'openedAt': '2026-12-01T12:00:00Z',
    'subtotalUsdc': '4.00',
    'taxTotalUsdc': '0.00',
    'tipUsdc': '0.00',
    'grandTotalUsdc': '4.00',
    'businessProfile': {
      'id': 'bp-1',
      'bizId': 'BIZ-1',
      'businessName': 'Chop Bar',
    },
    'items': [],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  test('a challenge restores the tab; the factor goes on the retry', () async {
    final posts = <Map<String, dynamic>>[];
    var payCalls = 0;
    final client = MockClient((req) async {
      if (req.method == 'GET') {
        return _json(200, _tab(payCalls >= 2 ? 'CLOSED' : 'OPEN'));
      }
      posts.add(jsonDecode(req.body) as Map<String, dynamic>);
      payCalls++;
      if (payCalls == 1) {
        return _json(401, {
          'success': false,
          'code': 'PASSWORD_REQUIRED',
          'message': 'Password required to confirm this operation.',
        });
      }
      return _json(200, {'success': true});
    });
    final n = DineInTabNotifier(
      ApiClient(client: client),
      SocketService.instance,
      't-1',
    );
    await n.loadTab('t-1');
    expect(n.state.valueOrNull?.status, 'OPEN');

    await expectLater(
      n.payTab('t-1'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'PASSWORD_REQUIRED'),
      ),
    );
    // Restored, not an error screen: nothing was paid.
    expect(n.state.valueOrNull?.status, 'OPEN');

    await n.payTab('t-1', secondFactor: const SecondFactor.password('pw'));
    expect(posts.last['password'], 'pw');
    expect(n.state.valueOrNull?.status, 'CLOSED');
    n.dispose();
  });
}
