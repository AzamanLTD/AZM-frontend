// =============================================================================
// RELEASE-LEVEL REVIEW REGRESSION 5 (PR #128, 2026-10-01)
//
// The shared AddPayoutSheet ("Add Mobile Money" flow) maps the selected
// network id to the canonical provider string before calling the
// account-name lookup. A wrong case used to send AirtelTigo lookups to
// the backend as TELECEL — the backend treats AIRTELTIGO as its own
// network/channel, so the lookup could fail or bind the wrong identity.
//
// This test drives the REAL sheet widget over a stubbed dart:io
// HttpClient and asserts the provider value in the OUTBOUND request
// body for all three selectable networks, so the AirtelTigo path can
// never silently collapse into Telecel again.
// =============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/screens/saved_wallets_screen.dart';

/// Every captured outbound request: {method, path, body}.
final List<Map<String, dynamic>> captured = [];

class _Route {
  _Route(this.status, this.body);
  final int status;
  final Map<String, dynamic> body;
}

final Map<String, _Route> _wire = {};

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _map = {};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _map[preserveHeaderCase ? name : name.toLowerCase()] = [value.toString()];
  @override
  void forEach(void Function(String name, List<String> values) f) =>
      _map.forEach(f);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this.method, this.uri, this.route);

  @override
  final String method;
  @override
  final Uri uri;
  final _Route route;
  final List<int> _outbound = [];

  @override
  final HttpHeaders headers = _FakeHttpHeaders();
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  int contentLength = -1;
  @override
  bool persistentConnection = true;

  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _outbound.addAll(chunk);
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    // Prove what actually left the app, not what the sheet meant to send.
    captured.add({
      'method': method,
      'path': uri.path,
      'body': utf8.decode(_outbound),
    });
    final body = Uint8List.fromList(utf8.encode(jsonEncode(route.body)));
    return _FakeHttpClientResponse(route.status, body, reasonPhrase: 'OK');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this.statusCode, this.body,
      {required this.reasonPhrase});

  @override
  final int statusCode;
  final Uint8List body;
  @override
  final String reasonPhrase;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _singleShot().listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  Stream<Uint8List> _singleShot() async* {
    if (body.isNotEmpty) yield body;
  }

  @override
  int get contentLength => body.length;
  @override
  bool get isRedirect => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  bool get persistentConnection => true;
  @override
  HttpHeaders get headers =>
      _FakeHttpHeaders()..set('content-type', 'application/json');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    for (final entry in _wire.entries) {
      final key = entry.key.split(' ');
      if (key[0] == method && url.path.endsWith(key[1])) {
        return _FakeHttpClientRequest(method, url, entry.value);
      }
    }
    throw StateError('lookup test: unexpected HTTP $method ${url.path}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

void _noop() {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _TestHttpOverrides();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    _wire.clear();
    captured.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

    // The name-lookup endpoint the sheet's Verify action calls.
    _wire['POST /saved-momo/lookup'] = _Route(200, {
      'name': 'Test Holder',
      'msisdn': '+233541234567',
    });
  });

  Future<String> lookupPayloadsJson() async => jsonEncode(captured
      .where((r) =>
          r['method'] == 'POST' && (r['path'] as String).endsWith('lookup'))
      .map((r) => jsonDecode(r['body'] as String) as Map<String, dynamic>)
      .toList());

  testWidgets('AddPayoutSheet name lookup sends the canonical provider for '
      'every network — AirtelTigo is AIRTELTIGO, not TELECEL',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
            home: Scaffold(body: AddPayoutSheet(onSaved: _noop))),
      ),
    );
    await tester.pump();

    // The sheet defaults to MTN. Type a number and verify.
    final phoneField = find.byWidgetPredicate((w) =>
        w is TextField &&
        (w.decoration?.hintText ?? '').startsWith('0541234567'));
    await tester.enterText(phoneField, '0541234567');
    await tester.tap(find.text('Verify Account Holder'));
    await tester.pumpAndSettle();

    // AirtelTigo: the case that regressed. The outbound request body
    // must carry AIRTELTIGO — reverting the fix sends 'TELECEL' here
    // and this expect fails.
    await tester.tap(find.text('AirtelTigo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Re-verify'));
    await tester.pumpAndSettle();

    // Telecel: must stay TELECEL so the fix cannot collapse the two.
    await tester.tap(find.text('Telecel Cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Re-verify'));
    await tester.pumpAndSettle();

    // The lookup resolved the holder name into the sheet (the flow the
    // user actually sees), and exactly three lookups left the app.
    // The lookup resolved the holder name into the sheet (the flow the
    // user actually sees).
    expect(find.text('Registered to: Test Holder'), findsOneWidget);
    final payloads = await lookupPayloadsJson();

    expect(
      payloads,
      // The sheet also adopts the normalized msisdn returned by the
      // first lookup, so the later requests carry it.
      '[{"provider":"MTN","phoneNumber":"0541234567"},'
      '{"provider":"AIRTELTIGO","phoneNumber":"+233541234567"},'
      '{"provider":"TELECEL","phoneNumber":"+233541234567"}]',
      reason: 'Each Verify must send the canonical provider for the '
          'selected network, in order: default MTN, then AirtelTigo, '
          'then Telecel.',
    );
  });
}
