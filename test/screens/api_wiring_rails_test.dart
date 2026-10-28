// =============================================================================
// General API wiring rail contracts (notification prefs, call history,
// forward dialog) — URL construction + envelope shape
// =============================================================================
// Three client surfaces previously constructed dead URLs:
//   • notification preferences hardcoded '/api/users/...' (→ /api/api/...)
//   • call history hardcoded '/api/calls' (→ /api/api/calls)
//   • the forward dialog hardcoded '/api/friends' + '/api/groups' — the
//     groups rail does not exist at all (the real rail is /api/group-chats),
//     and both envelopes are {success, friends}/{success, groups}, not bare
//     arrays.
//
// These widget tests pump the REAL screens through provider-overridden
// recording clients and pin the exact paths + the envelope keys each parse
// depends on (verified against backend main route handlers).
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:azaman/screens/call/call_history_screen.dart';
import 'package:azaman/screens/chat/forward_dialog.dart';
import 'package:azaman/screens/notification_preferences_screen.dart';
import 'package:azaman/services/api_client.dart';

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _RecordingClient extends ApiClient {
  final List<(String method, String path)> calls = [];
  final List<Map<String, dynamic>> putBodies = [];
  bool prefsFail = false;

  @override
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    calls.add(('GET', endpoint));
    switch (endpoint) {
      case '/users/me/notification-preferences':
        return _json(200, {
          'data': {
            'pushEnabled': true,
            'inAppEnabled': true,
            'emailEnabled': false,
            'quietHoursEnabled': true,
            'quietStart': '22:00',
            'quietEnd': '07:00',
            'categories': {
              'money': true,
              'social': false,
              'chat': true,
              'security': true,
              'system': false,
              'vendor': true,
              'admin': true,
            },
            'bypassQuiet': {
              'money': false,
              'social': false,
              'chat': false,
              'security': true,
              'system': false,
              'vendor': false,
              'admin': false,
            },
          },
        });
      case '/calls?limit=50':
        return _json(200, {
          'success': true,
          'data': [
            {
              'id': 'call-1',
              'type': 'VOICE',
              'status': 'ENDED',
              'durationSec': 61,
              'createdAt': '2026-10-19T10:00:00Z',
              'caller': {'id': 'u1', 'username': 'kofi'},
              'callee': {'id': 'u2', 'username': 'ama'},
            },
          ],
          'pagination': {'total': 1, 'limit': 50, 'offset': 0},
        });
      case '/friends':
        return _json(200, {
          'success': true,
          'friends': [
            {'id': 'f1', 'username': 'ama'},
          ],
        });
      case '/group-chats':
        return _json(200, {
          'success': true,
          'groups': [
            {'id': 'g1', 'name': 'Market Team'},
          ],
        });
    }
    return _json(404, {'success': false});
  }

  @override
  Future<http.Response> put(
    String endpoint,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    calls.add(('PUT', endpoint));
    putBodies.add(Map<String, dynamic>.from(body));
    if (prefsFail) return _json(500, {'success': false});
    return _json(200, {'success': true});
  }
}

Widget _app(Widget home, _RecordingClient client) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(client)],
    child: MaterialApp(home: home),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('notification prefs screen reads and saves the real rails', (
    tester,
  ) async {
    final client = _RecordingClient();
    _phone(tester);

    await tester.pumpWidget(
      _app(const NotificationPreferencesScreen(), client),
    );
    await tester.pumpAndSettle();

    // GET the real preferences rail — single-prefixed, response {data: prefs}.
    expect(
      client.calls,
      contains(('GET', '/users/me/notification-preferences')),
    );
    // The fetched prefs drove the UI: quiet hours came back ENABLED.
    expect(find.text('Enable Quiet Hours'), findsOneWidget);

    // Saving PUTs the same rail with the merged prefs object.
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      client.calls,
      contains(('PUT', '/users/me/notification-preferences')),
    );
    expect(client.putBodies.single['quietStart'], isNotNull);
    expect(find.text('Notification preferences saved'), findsOneWidget);

    // No double-prefixed call was ever constructed.
    for (final (_, path) in client.calls) {
      expect(path.startsWith('/api/'), isFalse, reason: 'saw $path');
    }
  });

  testWidgets('call history screen loads from the real /calls rail', (
    tester,
  ) async {
    final client = _RecordingClient();
    _phone(tester);

    await tester.pumpWidget(_app(const CallHistoryScreen(), client));
    await tester.pumpAndSettle();

    // The exact corrected path, with the limit query intact.
    expect(client.calls, contains(('GET', '/calls?limit=50')));
    // The {success, data} envelope parsed into a rendered history entry.
    expect(find.text('Failed to load calls'), findsNothing);
    expect(find.text('No call history'), findsNothing);
  });

  testWidgets(
    'forward dialog loads friends from /friends and groups from /group-chats',
    (tester) async {
      final client = _RecordingClient();
      _phone(tester);

      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ForwardDialog.show(
                  context: context,
                  messageId: 'm1',
                  fromContext: 'friend',
                ),
                child: const Text('Open Forward'),
              ),
            ),
          ),
          client,
        ),
      );

      await tester.tap(find.text('Open Forward'));
      await tester.pumpAndSettle();

      // Both real rails, exactly once-prefixed. '/api/groups' does not exist
      // on the backend — the rail is '/group-chats'.
      expect(
        client.calls,
        containsAll([('GET', '/friends'), ('GET', '/group-chats')]),
      );
      for (final (_, path) in client.calls) {
        expect(path.startsWith('/api/'), isFalse, reason: 'saw $path');
      }

      // The {success, friends}/{success, groups} envelopes parsed and rendered.
      expect(find.text('ama'), findsOneWidget);
      expect(find.text('Market Team'), findsOneWidget);

      // Dismiss the sheet by tapping the modal barrier above it.
      await tester.tapAt(const Offset(210, 20));
      await tester.pumpAndSettle();
    },
  );
}
