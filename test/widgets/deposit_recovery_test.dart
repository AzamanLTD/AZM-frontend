// test/widgets/deposit_recovery_test.dart
// =============================================================================
// INTERRUPTED-DEPOSIT RECOVERY (PR #202 item 1) — widget regressions.
//
// The notification-centre Resume pushes /deposit with the draft's
// editable inputs as route extra. When that draft carries a
// `pendingReference`, the panel must reconcile it against the backend's
// durable ledger BEFORE anything else, and land the user on the honest
// state for THAT deposit:
//
//   (a) ledger PENDING  -> the in-flight view (no keypad, no double
//                          instruction; the exact reference is shown)
//   (b) ledger COMPLETED-> the confirmed end state + settle-while-away
//                          snackbar
//   (c) ledger FAILED   -> the fresh form + honest failure snackbar
//   (d) reference gone  -> the fresh form, silently (no claim made)
//
// Runs against the stubbed dart:io HTTP layer (HttpOverrides) with demo
// mode OFF so the real ApiClient path — history search, then Backend
// F's status endpoint — is exercised end-to-end with zero sockets.
// =============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/saved_momo_provider.dart';
import 'package:azaman/services/deposit_continuations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:azaman/router/transitions.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/durable_operation_registry.dart';

// ── Stubbed dart:io HTTP layer (only the surface IOClient touches) ─────────

class _Route {
  _Route(this.status, this.body, [this.gate]);
  final int status;
  final Map<String, dynamic> body;
  final Completer<void>? gate;
}

final Map<String, _Route> _wire = {};
final List<String> _unexpectedCalls = [];

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
  final List<int> _bytes = [];

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
      _bytes.addAll(chunk);
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    final gate = route.gate;
    if (gate != null) await gate.future;
    return _FakeHttpClientResponse(
      route.status,
      Uint8List.fromList(utf8.encode(jsonEncode(route.body))),
      reasonPhrase: route.status == 200 ? 'OK' : 'Error',
    );
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

class _FakeHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    for (final entry in _wire.entries) {
      final key = entry.key.split(' ');
      if (key[0] == method && url.path.endsWith(key[1])) {
        return _FakeHttpClientRequest(method, url, entry.value);
      }
    }
    _unexpectedCalls.add('$method ${url.path}');
    throw StateError('recovery test: unexpected HTTP $method ${url.path}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

// ── Harness ─────────────────────────────────────────────────────────────────

class _FakeSavedMomo extends SavedMomoNotifier {
  _FakeSavedMomo(this.accounts);
  final List<SavedMomoAccount> accounts;
  @override
  Future<List<SavedMomoAccount>> build() async => accounts;
}

SavedMomoAccount _acct(String id, String label, String provider) =>
    SavedMomoAccount(
      id: id,
      nickname: label,
      provider: provider,
      phoneNumber: '+233244111222',
      accountName: label,
      isVerified: true,
      isPrimary: true,
      createdAt: DateTime.utc(2026, 9, 1),
    );

final List<SavedMomoAccount> _accounts = [
  _acct('acct-a', 'Kwame Mensah', 'MTN'),
];

Map<String, dynamic> _ledgerRow(String id, String status) => {
  'id': id,
  'txHash': _ref,
  'status': status,
  'type': 'DEPOSIT_FIAT',
  'amountUsdc': '12.340000000000',
};

const _ref = 'MOOLRE_DEP_12_1712345678_a1b2c3d4';

/// In-memory FlutterSecureStorage — the continuation service runs its
/// REAL implementation against the same async API.
class _MemSecureStorage implements FlutterSecureStorage {
  final Map<String, String> store = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final named = invocation.namedArguments;
    switch (invocation.memberName) {
      case #read:
        return Future.value(store[named[#key] as String]);
      case #write:
        final key = named[#key] as String;
        final value = named[#value] as String?;
        if (value == null) {
          store.remove(key);
        } else {
          store[key] = value;
        }
        return Future.value();
      case #delete:
        store.remove(named[#key] as String);
        return Future.value();
      case #deleteAll:
        store.clear();
        return Future.value();
      default:
        throw UnimplementedError('${invocation.memberName}');
    }
  }
}

/// A logged-in user so user-scoped persistence (drafts keep, submitted
/// continuations) is exercised with a real id.
class _FixedAuth extends AuthProvider {
  _FixedAuth(this.sessionUser);
  final User sessionUser;
  @override
  User? get user => sessionUser;
  @override
  Future<void> fetchUserDetails() async {}
}

final _recoveryUser = User(
  id: 'user-1',
  username: 'me',
  email: 'me@example.com',
  token: 'tok',
  role: 'USER',
);

late DepositContinuationsService contSvc;

Widget _app() {
  final memStore = _MemSecureStorage();
  contSvc = DepositContinuationsService(storage: memStore);
  return ProviderScope(
    overrides: [
      savedMomoProvider.overrideWith(() => _FakeSavedMomo(_accounts)),
      authProvider.overrideWith((ref) => _FixedAuth(_recoveryUser)),
      depositContinuationsProvider.overrideWith(
        (ref) => DepositContinuationsController(contSvc),
      ),
    ],
    child: MaterialApp.router(routerConfig: _router()),
  );
}

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (c, s) => Scaffold(
        body: Center(
          child: TextButton(
            // Resume pushes the canonical route with the draft's
            // editable inputs as extra — same as the notification
            // centre's launcher resume path.
            onPressed: () => GoRouter.of(c).push(
              '/deposit',
              extra: {
                'amountRaw': '50',
                'accountId': 'acct-a',
                'pendingReference': _ref,
              },
            ),
            child: const Text('home-sentinel'),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/deposit',
      name: 'deposit',
      pageBuilder: (c, s) => risePage(
        key: s.pageKey,
        restorationId: s.name,
        child: DepositScreen(
          restoredDraft: s.extra is Map<String, dynamic>
              ? s.extra as Map<String, dynamic>
              : null,
        ),
      ),
    ),
  ],
);

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openDepositWithDraft(WidgetTester tester) async {
  await tester.tap(find.text('home-sentinel'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _TestHttpOverrides();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    _wire.clear();
    _unexpectedCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async => null);
    SharedPreferences.setMockInitialValues({});
    ApiClient.operationAccountOverride = () async => 'regression-user';
    DurableOperationRegistry.storageWriterOverride = null;
  });

  tearDown(() {
    ApiClient.operationAccountOverride = null;
    DurableOperationRegistry.storageWriterOverride = null;
  });

  group('Interrupted-deposit recovery', () {
    testWidgets(
      '(a) ledger PENDING -> the in-flight view with the exact reference, '
      'no keypad',
      (tester) async {
        _phoneSize(tester);
        _wire['GET /finance/transactions'] = _Route(200, {
          'success': true,
          'transactions': [_ledgerRow('row-1', 'PENDING')],
          'hasMore': false,
          'nextCursor': null,
        });
        _wire['GET /deposit/fiat/status/row-1'] = _Route(200, {
          'success': true,
          'transaction': {'id': 'row-1', 'status': 'PENDING'},
          'continuation': {
            'provider': 'MTN',
            'amountGhs': '50.00',
            'payerPhoneMasked': '0244***222',
          },
        });

        await tester.pumpWidget(_app());
        await _openDepositWithDraft(tester);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 100));

        // The in-flight view: waiting state, exact reference visible, and
        // NO keypad/form (a new instruction cannot be started). The view
        // pulses forever — fixed pumps only, never pumpAndSettle.
        expect(find.text('Waiting for confirmation...'), findsOneWidget);
        expect(find.text(_ref), findsOneWidget);
        expect(find.text('Prompt sent'), findsOneWidget);
        expect(
          find.byType(TextField),
          findsNothing,
          reason: 'no OTP/form field: nothing new can be instructed',
        );
        expect(_unexpectedCalls, isEmpty);
      },
    );

    testWidgets('(b) ledger COMPLETED -> confirmed end state + '
        'settle-while-away snackbar', (tester) async {
      _phoneSize(tester);
      _wire['GET /finance/transactions'] = _Route(200, {
        'success': true,
        'transactions': [_ledgerRow('row-2', 'COMPLETED')],
        'hasMore': false,
        'nextCursor': null,
      });

      await tester.pumpWidget(_app());
      // FIX 3 — a submitted continuation from the earlier session exists:
      // the settled ledger answer must authoritatively resolve it.
      await contSvc.save('user-1', _ref);
      await _openDepositWithDraft(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Deposit Confirmed!'), findsOneWidget);
      expect(find.text('Start another deposit'), findsOneWidget);
      expect(
        find.textContaining('completed while you were away'),
        findsOneWidget,
      );
      // Settled is terminal: the continuation endpoint is never consulted.
      expect(_unexpectedCalls, isEmpty);
      expect(
        await contSvc.loadForUser('user-1'),
        isEmpty,
        reason: 'a settled deposit leaves the continuation lifecycle',
      );
    });

    testWidgets('(c) ledger FAILED -> fresh form + honest failure snackbar', (
      tester,
    ) async {
      _phoneSize(tester);
      _wire['GET /finance/transactions'] = _Route(200, {
        'success': true,
        'transactions': [_ledgerRow('row-3', 'FAILED')],
        'hasMore': false,
        'nextCursor': null,
      });

      await tester.pumpWidget(_app());
      await contSvc.save('user-1', _ref);
      await _openDepositWithDraft(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));

      // The draft's amount was restored into the fresh form.
      expect(find.text('Add Cash'), findsWidgets);
      expect(find.textContaining('did not go through'), findsOneWidget);
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'the restored keypad form, not a result view',
      );
      expect(_unexpectedCalls, isEmpty);
      expect(
        await contSvc.loadForUser('user-1'),
        isEmpty,
        reason: 'a failed deposit is authoritatively resolved too',
      );
    });

    testWidgets('(d) FAIL CLOSED: a lookup that cannot resolve the '
        'reference blocks new deposits — never a silent fresh form', (
      tester,
    ) async {
      _phoneSize(tester);
      // The ledger lookup itself FAILS (server error) — which is NOT
      // evidence the earlier instruction did not commit.
      _wire['GET /finance/transactions'] = _Route(500, {
        'message': 'ledger unavailable',
      });

      await tester.pumpWidget(_app());
      await contSvc.save('user-1', _ref);
      await _openDepositWithDraft(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));

      // The explicit unresolved state: the reference is preserved and
      // shown, nothing is claimed, and the CTA is blocked.
      expect(
        find.textContaining('could not confirm your earlier deposit'),
        findsOneWidget,
      );
      expect(find.text('Check again'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('Confirm your earlier deposit first'),
        findsOneWidget,
        reason: 'the blocked CTA states exactly what it wants',
      );
      semantics.dispose();
      // No success, no failure, no "start fresh" claim of any kind.
      expect(find.text('Waiting for confirmation...'), findsNothing);
      expect(find.textContaining('while you were away'), findsNothing);
      expect(find.textContaining('did not go through'), findsNothing);
      expect(find.textContaining('Nothing was charged again'), findsOneWidget);
      expect(_unexpectedCalls, isEmpty);
      // The submitted continuation survives an unresolved lookup.
      expect(
        (await contSvc.loadForUser('user-1')).map((c) => c.reference),
        contains(_ref),
      );
    });

    testWidgets('(e) FAIL CLOSED -> retry re-checks the SAME operation and '
        'a settled ledger resolves it', (tester) async {
      _phoneSize(tester);
      // First sweep: lookup fails. Second sweep: the ledger answers.
      _wire['GET /finance/transactions'] = _Route(500, {
        'message': 'ledger unavailable',
      });

      await tester.pumpWidget(_app());
      await contSvc.save('user-1', _ref);
      await _openDepositWithDraft(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Check again'), findsOneWidget);

      // The ledger recovers: the SAME reference now resolves as settled.
      _wire['GET /finance/transactions'] = _Route(200, {
        'success': true,
        'transactions': [_ledgerRow('row-4', 'COMPLETED')],
        'hasMore': false,
        'nextCursor': null,
      });

      await tester.tap(find.text('Check again'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));

      // Honest resolution at last: confirmed end state, banner gone.
      expect(find.text('Deposit Confirmed!'), findsOneWidget);
      expect(
        find.textContaining('completed while you were away'),
        findsOneWidget,
      );
      expect(find.text('Check again'), findsNothing);
      expect(
        find.textContaining('could not confirm your earlier deposit'),
        findsNothing,
      );
      expect(
        await contSvc.loadForUser('user-1'),
        isEmpty,
        reason: 'the settled ledger resolved the continuation',
      );
      expect(_unexpectedCalls, isEmpty);
    });
  });
}
