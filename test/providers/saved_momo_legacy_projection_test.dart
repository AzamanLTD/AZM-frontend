// =============================================================================
// REGRESSION — legacy `/wallet/saved` MoMo projection (production-path
// blocker found in PR #128 review, 2026-10-01).
//
// The switch in `SavedMomoNotifier._fetchLegacyWallets()` used a logical-or
// pattern, `'AIRTELTIGO' || 'TELECEL_CASH' => 'TELECEL'`, which folded
// AIRTELTIGO rows into the TELECEL bucket: the Add Cash payment-method
// sheet then badges airteltigo numbers with the TELECEL chip (or shows
// no badge at all, since AIRTELTIGO was expected canonical).
//
// The Add Cash widget tests could not catch this because they inject
// already-canonical SavedMomoAccount objects. This suite instead drives
// the REAL SavedMomoNotifier.build() → _fetch() → _fetchLegacyWallets()
// pipeline over a stubbed dart:io HTTP client (HttpOverrides), so the
// legacy wire shape → SavedMomoAccount projection is exercised exactly
// as it runs in production.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/saved_momo_provider.dart';

// --- Fake dart:io HTTP stack (only the surface IOClient touches) -----------

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _map = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    final key = preserveHeaderCase ? name : name.toLowerCase();
    _map[key] = [value.toString()];
  }

  @override
  void forEach(void Function(String name, List<String> values) f) {
    _map.forEach(f);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this.uri, this._status, this._bodyBytes);

  @override
  final Uri uri;
  final int _status;
  final Uint8List _bodyBytes;

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
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse(
    _status,
    _bodyBytes,
    reasonPhrase: _status == 200 ? 'OK' : '',
  );

  // StreamConsumer surface used by Stream.pipe() for the request body.
  @override
  Future addStream(Stream<List<int>> stream) async {
    await stream.drain();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(
    this.statusCode,
    this.body, {
    required this.reasonPhrase,
  });

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
    return _singleShot().listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
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

/// Routes GETs by path. `_legacyWallets` is mutated per test — the global
/// `apiClient` (an IOClient over one HttpClient) is created lazily ONCE, so
/// the fake must read its payload from a live variable.
final Map<String, Map<String, dynamic>> _wire = {};
final List<Map<String, dynamic>> _legacyWallets = [];

class _FakeHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final route = _wire[url.path];
    if (route == null) {
      throw StateError(
        'regression test: unexpected HTTP call $method ${url.path}',
      );
    }
    final body = jsonEncode(route);
    return _FakeHttpClientRequest(
      url,
      200,
      Uint8List.fromList(utf8.encode(body)),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

// --- Test -------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  // The wire shape of the legacy SavedWallet table, exactly as the backend
  // /wallet/saved endpoint returns it: `network` carries the LEGACY token,
  // `accountName` is only present once MoMo has resolved the registered
  // name, and crypto wallets (e.g. USDC_POLYGON) share the table.
  Map<String, dynamic> legacyRow({
    required String id,
    required String network,
    required String label,
    required String address,
    String? accountName,
    String createdAt = '2026-01-15T10:00:00Z',
  }) => {
    'id': id,
    'network': network,
    'label': label,
    'address': address,
    if (accountName != null) 'accountName': accountName,
    'createdAt': createdAt,
  };

  setUp(() {
    // ApiClient.get(requireAuth: true) reads the auth token from secure
    // storage before every call; answer null like an unauthenticated
    // cold start.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async => null);

    _wire.clear();
    _legacyWallets.clear();
    _wire['/api/saved-momo'] = {
      'accounts': [], // new table empty — isolate the legacy projection
    };
    _wire['/api/wallet/saved'] = {'wallets': _legacyWallets};
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    HttpOverrides.global = null;
  });

  // NOTE: HttpOverrides must be live BEFORE the first call into the global
  // `apiClient` — the IOClient's HttpClient is created once, lazily.
  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  test('an AIRTELTIGO legacy row projects to provider AIRTELTIGO (the '
      'review blocker)', () async {
    _legacyWallets.addAll([
      legacyRow(
        id: 'w-9',
        network: 'AIRTELTIGO',
        label: 'Airtel Money',
        address: '+233269998877',
        accountName: 'Kwabena Mensah',
      ),
    ]);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final accounts = await container.read(savedMomoProvider.future);

    expect(accounts, hasLength(1));
    final account = accounts.single;
    expect(
      account.provider,
      'AIRTELTIGO',
      reason:
          'the logical-or switch used to fold AIRTELTIGO into '
          'TELECEL — the payment-method sheet then badged an airteltigo '
          'number as TELECEL',
    );
    expect(account.id, 'legacy:w-9');
    expect(account.phoneNumber, '+233269998877');
    expect(account.accountName, 'Kwabena Mensah');
    expect(account.isVerified, isTrue);
  });

  test('every legacy network token maps to its canonical provider', () async {
    _legacyWallets.addAll([
      legacyRow(
        id: 'a',
        network: 'MTN_MOMO',
        label: 'MoMo',
        address: '+233244000111',
        accountName: 'Ama Owusu',
      ),
      legacyRow(
        id: 'b',
        network: 'TELECEL_CASH',
        label: 'Cash',
        address: '+233500112233',
        accountName: 'Yao Dede',
      ),
      legacyRow(
        id: 'c',
        network: 'VODAFONE_CASH',
        label: 'Old cash',
        address: '+233200445566',
        accountName: 'Kofi Boateng',
      ),
      legacyRow(
        id: 'd',
        network: 'AIRTELTIGO',
        label: 'Airtel',
        address: '+233269001122',
        accountName: 'Efua Sarpong',
      ),
    ]);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final accounts = await container.read(savedMomoProvider.future);

    expect(accounts, hasLength(4));
    final byId = {for (final a in accounts) a.id: a.provider};
    expect(byId['legacy:a'], 'MTN');
    expect(byId['legacy:b'], 'TELECEL');
    expect(byId['legacy:c'], 'TELECEL'); // VODAFONE_CASH legacy → TELECEL
    expect(byId['legacy:d'], 'AIRTELTIGO');
  });

  test('crypto wallets sharing the legacy table are filtered out; MoMo '
      'rows without a resolved name stay unverified', () async {
    _legacyWallets.addAll([
      legacyRow(
        id: 'x1',
        network: 'USDC_POLYGON',
        label: 'USDC wallet',
        address: '0xabc123',
      ),
      legacyRow(
        id: 'm2',
        network: 'MTN_MOMO',
        label: 'MoMo pending name',
        address: '+233244555666',
      ), // accountName absent
    ]);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final accounts = await container.read(savedMomoProvider.future);

    expect(accounts, hasLength(1));
    final momo = accounts.single;
    expect(momo.id, 'legacy:m2');
    expect(momo.isVerified, isFalse);
    expect(momo.accountName, isNull);
  });
}
