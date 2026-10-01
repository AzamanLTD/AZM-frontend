// =============================================================================
// RELEASE-LEVEL REVIEW REGRESSION 4 (PR #128, 2026-10-01)
//
// saved_wallets_screen MoMo tiles must render their network identity from
// MomoNetwork — the ONE authoritative provider→brand mapping (the deposit
// picker and the saved-accounts screen already do) — instead of the generic
// colors.success phone mark that said nothing about the network.
//
// The screen fetches two endpoints (legacy /wallet/saved rows + the new
// /saved-momo accounts); both are stubbed here so the merge/projection
// path and the tile rendering are exercised with zero sockets.
// =============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/screens/saved_wallets_screen.dart';
import 'package:azaman/widgets/momo_network.dart';

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
  }

  @override
  Future<HttpClientResponse> close() async {
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
    throw StateError('identity test: unexpected HTTP $method ${url.path}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _TestHttpOverrides();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    _wire.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

    // Legacy SavedWallet rows: display-form providers, network enum values —
    // the shapes the projection/allow-list path actually receives.
    _wire['GET /wallet/saved'] = _Route(200, {
      'wallets': [
        {
          'id': '1',
          'label': 'My MoMo',
          'address': '+233244000111',
          'network': 'MTN_MOMO',
          'provider': 'MTN MOMO',
          'createdAt': '2026-08-01T00:00:00.000Z',
        },
        {
          'id': '2',
          'label': 'Tigo line',
          'address': '+233500000222',
          'network': 'TELECEL_CASH',
          'provider': 'TELECEL CASH',
          'createdAt': '2026-08-02T00:00:00.000Z',
        },
        {
          'id': '3',
          'label': 'Cold wallet',
          'address': 'TWd4y9...',
          'network': 'POLYGON',
          'provider': 'EXTERNAL WALLET',
          'createdAt': '2026-08-03T00:00:00.000Z',
        },
      ],
    });
    _wire['GET /saved-momo'] = _Route(200, {'accounts': []});
  });

  testWidgets('MoMo wallet tiles carry the provider-specific MomoNetwork '
      'identity, not the generic success mark', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(420, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SavedWalletsScreen())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    // The network identity comes from MomoNetwork — the same source of
    // truth as the deposit picker and the saved-accounts screen: MTN's
    // brand mark and Telecel's, announced to screen readers as well.
    // The badge Semantics merges with the tile's own label, so match by
    // substring — the network identity is what must be announced.
    expect(find.bySemanticsLabel(RegExp('MTN Mobile Money')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Telecel Mobile Money')),
        findsOneWidget);

    // The badge colors are the networks' brand colors, not colors.success.
    final mtn = MomoNetwork.of('MTN_MOMO');
    final telecel = MomoNetwork.of('TELECEL_CASH');
    expect(mtn.color, const Color(0xFFFFCC00));
    expect(telecel.color, const Color(0xFFE60000));
    // The badges render the networks' short codes (MTN / TEL), not a
    // generic phone glyph.
    expect(find.text('MTN'), findsOneWidget);
    expect(find.text('TEL'), findsOneWidget);

    // The generic success-green phone mark is gone from the MoMo tiles.
    expect(find.byIcon(Icons.smartphone_outlined), findsNothing);

    // De-dup + allow-list: exactly the two MoMo tiles render on this tab.
    expect(find.text('My MoMo'), findsOneWidget);
    expect(find.text('Tigo line'), findsOneWidget);

    // Crypto tiles keep their plain-accent identity on the Crypto tab.
    await tester.tap(find.text('Crypto'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.currency_bitcoin), findsOneWidget);
    handle.dispose();
  });
}
