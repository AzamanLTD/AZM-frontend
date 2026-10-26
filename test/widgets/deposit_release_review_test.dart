// =============================================================================
// RELEASE-LEVEL REVIEW REGRESSIONS (PR #128, 2026-10-01)
//
// Runtime blockers found in independent review of head bf8d903 that the
// existing suites could not catch:
//
//   1. Add Cash must start in the dedicated Fiat composition; Crypto now lives
//      on the separate full-page Receive destination.
//   2. Pull-down spring-back — the rendered translation must actually be
//      ZERO after the spring completes (not merely "route still open"), and
//      a new gesture interrupting a spring must resume from the on-screen
//      position, never from stale pre-spring drag state.
//   3. validate-name / account-selection race — the resolved name and the
//      initiation are bound to the exact account that was validated; the
//      payment-method row is inert while validation is in flight.
//
// Blockers 1-2 run against the overridden provider (no network). Blocker 3
// runs against a stubbed dart:io HTTP layer (HttpOverrides) with
// controllable, gated responses — demo mode is NOT enabled in this isolate
// so the real ApiClient path (validate-name + postFinancial initiate) is
// exercised end-to-end with zero sockets.
// =============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/saved_momo_provider.dart';
import 'package:azaman/services/deposit_continuations.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/router/transitions.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/durable_operation_registry.dart';
import 'package:azaman/widgets/amount_keypad.dart';

// ── Stubbed dart:io HTTP layer (only the surface IOClient touches) ─────────

class _Route {
  _Route(this.status, this.body, [this.gate]);
  final int status;
  final Map<String, dynamic> body;
  final Completer<void>? gate;
}

/// Routes keyed by "<METHOD> <path-suffix>". Captured request bodies land in
/// [_requests] so tests can assert the exact wire payload.
final Map<String, _Route> _wire = {};
final List<Map<String, dynamic>> _requests = [];
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
    if (_bytes.isNotEmpty) {
      _requests.add(jsonDecode(utf8.decode(_bytes)) as Map<String, dynamic>);
    }
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
    _unexpectedCalls.add('$method ${url.path}');
    throw StateError('regression test: unexpected HTTP $method ${url.path}');
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

SavedMomoAccount _acct(
  String id,
  String label,
  String provider,
  String phone, {
  bool isPrimary = false,
}) =>
    SavedMomoAccount(
      id: id,
      nickname: label,
      provider: provider,
      phoneNumber: phone,
      accountName: label,
      isVerified: true,
      isPrimary: isPrimary,
      createdAt: DateTime.utc(2026, 9, 1),
    );

// Kwame (MTN, primary) and Ama (Telecel) — the two-account race scenario.
final List<SavedMomoAccount> _accounts = [
  _acct('acct-a', 'Kwame Mensah', 'MTN', '+233244111222', isPrimary: true),
  _acct('acct-b', 'Ama Boateng', 'TELECEL', '+233500111222'),
];

Widget _app() {
  // FINAL REVIEW — the deposit surface belongs to an authenticated
  // session by contract: the continuation lifecycle is owner-scoped
  // and the initiation itself now REQUIRES a capturable owner (it is
  // blocked before the wire without one). The base harness runs with
  // a signed-in identity and in-memory continuations.
  return ProviderScope(
    overrides: [
      savedMomoProvider.overrideWith(() => _FakeSavedMomo(_accounts)),
      authProvider.overrideWith((ref) => _FixedAuth(_harnessUser)),
      depositContinuationsProvider.overrideWith(
        (ref) => DepositContinuationsController(
          DepositContinuationsService(storage: _MemSecureStorage()),
        ),
      ),
    ],
    child: MaterialApp.router(routerConfig: _router()),
  );
}

final _harnessUser = User(
  id: 'user-a',
  username: 'me',
  email: 'me@example.com',
  token: 'tok',
  role: 'USER',
  azamanId: 'AZM-999999999',
);

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (c, s) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => GoRouter.of(c).push('/deposit'),
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
        child: const DepositScreen(),
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

Future<void> _openDeposit(WidgetTester tester) async {
  await tester.tap(find.text('home-sentinel'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// A modal sheet's ticker anchors at its first tick: pump a zero-duration
/// frame BEFORE advancing the clock, or the sheet sits below the viewport
/// and its rows are unhittable (same contract as the existing suites).
Future<void> _settleSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Stage 50 GHS via the quick-amount pill.
Future<void> _enterAmount(WidgetTester tester) async {
  await tester.tap(find.text('GH₵ 50'));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
}

/// The sheet-level Transform — the ONLY Transform that is an ancestor of
/// the TabBarView. Its rendered y translation is what the user sees.
double _sheetTranslateY(WidgetTester tester) {
  final f = find.byKey(const ValueKey('pull-down-dismiss-transform'));
  return tester.widget<Transform>(f).transform.getTranslation().y;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _TestHttpOverrides();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    _wire.clear();
    _requests.clear();
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

  // ── Regression: Add Cash is a fiat-only surface ──────────────────────────

  group('1 — Add Cash is fiat-only', () {
    testWidgets('Add Cash opens directly into fiat with no currency switch', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);

      expect(find.text('Add Cash'), findsWidgets);
      expect(find.byType(AmountKeypad), findsOneWidget);
      expect(find.text('Crypto'), findsNothing);
      expect(find.text('Fiat'), findsNothing);
    });
  });

  // ── Blocker 2: spring-back ends at rest, interrupts resume on-screen ────

  group('2 — pull-down spring-back state', () {
    testWidgets('after a below-threshold pull springs back, the final '
        'rendered translation is EXACTLY zero', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      final origin = tester.getCenter(find.text('Add Cash').first);

      final gesture = await tester.startGesture(origin);
      await gesture.moveBy(const Offset(0, 100)); // visual 55 < 110
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump();

      // Spring back (MotionTokens.control = 180ms) — drive it to completion
      // and one frame past, so the builder has fallen back to _dragDy.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 50));

      // THE regression: after completion the builder uses the raw drag
      // offset — a stale value visibly slams the sheet back down.
      expect(_sheetTranslateY(tester), 0.0);
      expect(find.text('Add Cash'), findsWidgets);
    });

    testWidgets('a new gesture interrupting the spring resumes from the '
        'on-screen position, never stale drag state', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      final origin = tester.getCenter(find.text('Add Cash').first);

      // Pull 100px (visual 55) and release → spring starts from 55.
      final first = await tester.startGesture(origin);
      await first.moveBy(const Offset(0, 100));
      await tester.pump(const Duration(milliseconds: 50));
      await first.up();
      await tester.pump();

      // Mid-spring: capture the on-screen position…
      await tester.pump(const Duration(milliseconds: 80));
      final visualAtInterrupt = _sheetTranslateY(tester);
      expect(visualAtInterrupt, allOf(greaterThan(0), lessThan(55)));

      // …and immediately start a NEW gesture with a small continued pull.
      // Stale-state behavior would snap back up to the pre-spring offset
      // (55 + delta) instead of continuing from the visual position.
      final second = await tester.startGesture(origin);
      await second.moveBy(const Offset(0, 20)); // visual +11
      await tester.pump(const Duration(milliseconds: 50));

      final duringSecondDrag = _sheetTranslateY(tester);
      expect(duringSecondDrag,
          allOf(greaterThan(visualAtInterrupt - 1), lessThan(55)),
          reason: 'must continue from the interrupted position (~$visualAtInterrupt + 11), '
              'not snap to the stale pre-spring offset (55)');

      await second.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 50));

      expect(_sheetTranslateY(tester), 0.0);
      expect(find.text('Add Cash'), findsWidgets);
    });
  });

  // ── Blocker 3: validate-name bound to the validated account ─────────────

  group('3 — validate-name / account-selection race', () {
    testWidgets('(a) the payment-method row is inert while validation is in '
        'flight, and the confirmed name belongs to the validated account',
        (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await _enterAmount(tester);

      // Hold validation open so the "in flight" window is observable.
      final gate = Completer<void>();
      _wire['POST /deposit/validate-name'] = _Route(200, {'data': 'Kwame Mensah'}, gate);
      _wire['POST /deposit/fiat/initiate/moolre'] = _Route(201, {
        'data': {'reference': 'DEP-REG-1', 'status': 'PENDING'},
      });

      await tester.tap(find.text('Add Cash').last); // the CTA
      await tester.pump(const Duration(milliseconds: 100));
      // isBusy renders a spinner; the label lives on the Semantics node.
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Checking account…'), findsOneWidget);
      semantics.dispose();

      // The method row must NOT open the selector while validating —
      // switching mid-flight is the race this guard closes.
      await tester.tap(find.text('Kwame Mensah'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Payment method'), findsNothing,
          reason: 'the selector must stay closed while validation runs');
      expect(find.text('Ama Boateng'), findsNothing,
          reason: 'no account switch happened');

      // Validation resolves → the dialog shows the VALIDATED account's
      // name → confirming initiates against THAT account.
      gate.complete();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Paying to: Kwame Mensah'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      final initiate =
          _requests.where((b) => b.containsKey('amountGhs')).single;
      expect(initiate['phoneNumber'], '+233244111222');
      expect(initiate['provider'], 'MTN_MOMO');
      expect(initiate['amountGhs'], 50);
      // Let result-view entrance timers elapse before teardown.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('(b) a failed re-validation for a different account can '
        'never show or use the first account’s resolved name', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await _enterAmount(tester);

      // 1. Validate the primary (Kwame) successfully, then CANCEL.
      _wire['POST /deposit/validate-name'] = _Route(200, {'data': 'Kwame Mensah'});
      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Paying to: Kwame Mensah'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 200));

      // 2. Switch to Ama through the (now unlocked) selector sheet.
      await tester.tap(find.text('Kwame Mensah'));
      await _settleSheet(tester);
      expect(find.text('Payment method'), findsOneWidget);
      await tester.tap(find.text('Ama Boateng'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      // 3. Ama's validation FAILS — the stale-name bug would confirm
      //    Kwame's name while charging Ama.
      _wire['POST /deposit/validate-name'] =
          _Route(500, {'message': 'validation down'});
      _wire['POST /deposit/fiat/initiate/moolre'] = _Route(201, {
        'data': {'reference': 'DEP-REG-2', 'status': 'PENDING'},
      });
      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 100));

      // No confirmation dialog AT ALL — certainly not Kwame's name.
      expect(find.textContaining('Paying to:'), findsNothing,
          reason: 'a failed validation for the newly selected account must '
              'not reuse the first account’s resolved name');

      // The deposit proceeds best-effort against AMA, exactly as designed
      // (validation is optional), with her number on the wire.
      final initiate =
          _requests.where((b) => b.containsKey('amountGhs')).single;
      expect(initiate['phoneNumber'], '+233500111222');
      expect(initiate['provider'], 'TELECEL_CASH');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('(c) the initiation targets the exact account whose name '
        'was validated — selection made BEFORE validation', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(_app());
      await _openDeposit(tester);
      await _enterAmount(tester);

      // Select Ama (non-primary) first.
      await tester.tap(find.text('Kwame Mensah'));
      await _settleSheet(tester);
      await tester.tap(find.text('Ama Boateng'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      final gate = Completer<void>();
      _wire['POST /deposit/validate-name'] = _Route(200, {'data': 'Ama Boateng'}, gate);
      _wire['POST /deposit/fiat/initiate/moolre'] = _Route(201, {
        'data': {'reference': 'DEP-REG-3', 'status': 'PENDING'},
      });

      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(milliseconds: 100));

      // The validate-name call must carry AMA's number — not the primary's.
      final validate =
          _requests.where((b) => b.containsKey('phoneNumber')).single;
      expect(validate['phoneNumber'], '+233500111222');

      gate.complete();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Paying to: Ama Boateng'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      final initiate =
          _requests.where((b) => b.containsKey('amountGhs')).single;
      expect(initiate['phoneNumber'], '+233500111222');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  // ── REVIEW GAP 1 + FIX 3: initiation window + submitted continuations ────
  group('4 — initial-submit race guard + submitted continuation', () {
    // In-memory secure storage so the continuation lifecycle is asserted
    // against the REAL service over the same async API.
    final contStorage = _MemSecureStorage();
    late DepositContinuationsService contSvc;

    Widget appWithAuth() {
      contStorage.store.clear();
      contSvc = DepositContinuationsService(storage: contStorage);
      return ProviderScope(
        overrides: [
          savedMomoProvider.overrideWith(() => _FakeSavedMomo(_accounts)),
          authProvider.overrideWith(
            (ref) => _FixedAuth(User(
              id: 'user-7',
              username: 'me',
              email: 'me@example.com',
              token: 'tok',
              role: 'USER',
              azamanId: 'AZM-999999999',
            )),
          ),
          depositContinuationsProvider.overrideWith(
            (ref) => DepositContinuationsController(contSvc),
          ),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      );
    }

    testWidgets('every close gesture is guarded while the initiation is in '
        'flight — no draft, no close, honest notice', (tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(appWithAuth());
      await _openDeposit(tester);
      await _enterAmount(tester);

      final gate = Completer<void>();
      _wire['POST /deposit/validate-name'] =
          _Route(200, {'data': 'Kwame Mensah'});
      _wire['POST /deposit/fiat/initiate/moolre'] = _Route(201, {
        'data': {'reference': 'DEP-RACE-1', 'status': 'PENDING'},
      }, gate);

      await tester.tap(find.text('Add Cash').last); // CTA
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Confirm')); // name dialog
      await tester.pump(const Duration(milliseconds: 200));

      // The initiate request is now HELD at the gate — the exact window
      // in which a saved draft could not honestly represent the
      // operation. Every close gesture must be refused.
      await tester.tap(find.bySemanticsLabel('Close Add Cash'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Keep for 5 minutes'), findsNothing,
          reason: 'the exit prompt must not appear while the initiation '
              'is in flight');
      expect(find.textContaining('Setting up your deposit'), findsOneWidget);
      // Still on the surface — the operation owns the window.
      expect(find.bySemanticsLabel('Close Add Cash'), findsOneWidget);

      // No draft was saved for the race window.
      expect(_unexpectedCalls, isEmpty);

      // Outcome arrives: the reference is durable and a continuation is
      // recorded (FIX 3) — NOW closing is safely representable.
      gate.complete();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));

      final stored = await contSvc.loadForUser('user-7');
      expect(stored, hasLength(1));
      expect(stored.single.reference, 'DEP-RACE-1',
          reason: 'the submitted operation enters the continuation '
              'lifecycle the moment its reference is durable');

      await tester.tap(find.bySemanticsLabel('Close Add Cash'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Keep for 5 minutes'), findsOneWidget,
          reason: 'once the outcome is representable the close prompt '
              'returns');
    });
  });

  group('5 — REVIEW FOLLOW-UP P1: continuation persistence is part of the '
      'close guard', () {
    final contStorage = _GatedWriteStorage();
    late DepositContinuationsService contSvc;

    Widget appWithAuth() {
      // NOTE: writeGate/writeError are NOT reset here — the tests arm
      // them BEFORE the submit sequence (the write happens mid-submit,
      // right after the initiate response lands).
      contStorage.store.clear();
      contSvc = DepositContinuationsService(storage: contStorage);
      return ProviderScope(
        overrides: [
          savedMomoProvider.overrideWith(() => _FakeSavedMomo(_accounts)),
          authProvider.overrideWith(
            (ref) => _FixedAuth(User(
              id: 'user-7',
              username: 'me',
              email: 'me@example.com',
              token: 'tok',
              role: 'USER',
              azamanId: 'AZM-999999999',
            )),
          ),
          depositContinuationsProvider.overrideWith(
            (ref) => DepositContinuationsController(contSvc),
          ),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      );
    }

    Future<void> submitDeposit(WidgetTester tester, String reference) async {
      _phoneSize(tester);
      await tester.pumpWidget(appWithAuth());
      await _openDeposit(tester);
      await _enterAmount(tester);
      _wire['POST /deposit/validate-name'] =
          _Route(200, {'data': 'Kwame Mensah'});
      _wire['POST /deposit/fiat/initiate/moolre'] = _Route(201, {
        'data': {'reference': reference, 'status': 'PENDING'},
      });
      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Confirm'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('(a) a HELD secure-storage write keeps every close '
        'gesture blocked until the continuation is durably saved',
        (tester) async {
      final heldWrite = Completer<void>();
      contStorage.writeGate = heldWrite;
      await submitDeposit(tester, 'DEP-PERSIST-1');

      expect(find.text('Prompt sent'), findsOneWidget);
      expect(find.text('Keep for 5 minutes'), findsNothing,
          reason: 'the exit prompt must not bypass the durability '
              'barrier while the continuation write is in flight');
      expect(find.bySemanticsLabel('Close Add Cash'), findsOneWidget,
          reason: 'the surface stays open — closing now could lose the '
              'only local pointer to the submitted operation');
      expect(contStorage.store.isEmpty, isTrue,
          reason: 'the record is not durable yet');

      heldWrite.complete();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      final stored = await contSvc.loadForUser('user-7');
      expect(stored, hasLength(1));
      expect(stored.single.reference, 'DEP-PERSIST-1');

      await tester.tap(find.bySemanticsLabel('Close Add Cash'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Keep for 5 minutes'), findsOneWidget,
          reason: 'once the local way-back is durable, closing is safely '
              'representable again');
    });

    testWidgets('(b) a FAILED local write keeps the surface fail-closed '
        'with the exact reference and an explicit retry',
        (tester) async {
      contStorage.writeError = StateError('disk full');
      await submitDeposit(tester, 'DEP-PERSIST-2');

      expect(find.text('Keep for 5 minutes'), findsNothing,
          reason: 'a failed persistence write keeps the close guard '
              'active — the reference must not be closed away unsaved');
      // Two retry affordances: the failure snackbar's action and the
      // result view's primary button.
      expect(find.text('Save receipt'), findsNWidgets(2),
          reason: 'the retry affordance for the SAME operation replaces '
              'the normal result actions');
      expect(contStorage.store.isEmpty, isTrue);

      contStorage.writeError = null;
      await tester.pump(const Duration(seconds: 6));
      await tester.tap(find.text('Save receipt').last);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      final stored = await contSvc.loadForUser('user-7');
      expect(stored, hasLength(1));
      expect(stored.single.reference, 'DEP-PERSIST-2',
          reason: 'the retry persists the EXACT reference the backend '
              'returned — nothing is re-initiated or invented');

      await tester.tap(find.bySemanticsLabel('Close Add Cash'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Keep for 5 minutes'), findsOneWidget);
    });
  });

  group('6 — REVIEW FOLLOW-UP: OTP persistence + continuation owner '
      'identity', () {
    final contStorage = _GatedWriteStorage();
    late DepositContinuationsService contSvc;
    _MutableAuth? currentAuth;

    User makeUser(String id) => User(
          id: id,
          username: 'me',
          email: 'me@example.com',
          token: 'tok',
          role: 'USER',
          azamanId: 'AZM-999999999',
        );

    Widget appWithAuth() {
      contStorage.store.clear();
      contSvc = DepositContinuationsService(storage: contStorage);
      return ProviderScope(
        overrides: [
          savedMomoProvider.overrideWith(() => _FakeSavedMomo(_accounts)),
          authProvider.overrideWith((ref) => currentAuth!),
          depositContinuationsProvider.overrideWith(
            (ref) => DepositContinuationsController(contSvc),
          ),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      );
    }

    Future<void> openAndEnterAmount(WidgetTester tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(appWithAuth());
      await _openDeposit(tester);
      await _enterAmount(tester);
    }

    testWidgets('(c) on the OTP path a failed continuation write never '
        'lets Cancel destroy the reference', (tester) async {
      currentAuth = _MutableAuth(makeUser('user-a'));
      contStorage.writeError = StateError('disk full');
      await openAndEnterAmount(tester);
      _wire['POST /deposit/validate-name'] =
          _Route(200, {'data': 'Kwame Mensah'});
      _wire['POST /deposit/fiat/initiate/moolre'] = _Route(201, {
        'requiresOtp': true,
        'data': {'reference': 'DEP-OTP-1', 'status': 'PENDING'},
      });
      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Confirm'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));

      // OTP view is up, the local write FAILED: there is no Cancel —
      // cancelling would discard the only in-memory reference.
      expect(find.text('Enter OTP'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing,
          reason: 'a failed persistence write must not expose a Cancel '
              'that destroys the unpersisted reference');
      expect(find.text('Save receipt'), findsWidgets);
      expect(contStorage.store.isEmpty, isTrue);

      // The close guard stays active — no second initiation, no exit.
      await tester.tap(find.bySemanticsLabel('Close Add Cash'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Keep for 5 minutes'), findsNothing);

      // Retry the SAME save from the OTP state: persistence succeeds
      // under the initiating user, and only then does Cancel return.
      contStorage.writeError = null;
      // Let the queued snackbars (failure notice + close-guard notice)
      // dismiss; the retry button is then scoped to the OTP view
      // itself so no snackbar action can shadow it.
      await tester.pump(const Duration(seconds: 10));
      final otpRetry =
          find.descendant(of: find.byType(SingleChildScrollView), matching: find.text('Save receipt'));
      expect(otpRetry, findsOneWidget);
      await tester.tap(otpRetry);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      final stored = await contSvc.loadForUser('user-a');
      expect(stored, hasLength(1));
      expect(stored.single.reference, 'DEP-OTP-1');
      expect(await contSvc.loadForUser('user-b'), isEmpty);

      // With the record durable the back action returns — under its
      // honest label (LAST REVIEW: a local back can never cancel a
      // submitted instruction).
      expect(find.text('Back to Add Cash'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      await tester.tap(find.text('Back to Add Cash'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Add Cash'), findsWidgets);
    });

    testWidgets('(d) an account switch mid-initiation never rebinds the '
        "continuation owner — A's reference is saved under A only",
        (tester) async {
      currentAuth = _MutableAuth(makeUser('user-a'));
      await openAndEnterAmount(tester);
      _wire['POST /deposit/validate-name'] =
          _Route(200, {'data': 'Kwame Mensah'});
      final gate = Completer<void>();
      _wire['POST /deposit/fiat/initiate/moolre'] = _Route(201, {
        'data': {'reference': 'DEP-RACE-A', 'status': 'PENDING'},
      }, gate);

      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Confirm'));
      await tester.pump(const Duration(milliseconds: 200));

      // The initiation response is HELD; the session switches directly
      // to user B before it lands.
      currentAuth!.switchTo(makeUser('user-b'));
      gate.complete();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));

      // The reference is bound to the INITIATING identity only.
      final aList = await contSvc.loadForUser('user-a');
      expect(aList, hasLength(1));
      expect(aList.single.reference, 'DEP-RACE-A');
      expect(await contSvc.loadForUser('user-b'), isEmpty,
          reason: 'a response arriving after a switch must never store '
              "A's reference under B's key");
      // Flush short-lived timers (pulsing-dots stagger etc.).
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('(e) the same switch race during OTP confirmation and '
        'continuation persistence', (tester) async {
      currentAuth = _MutableAuth(makeUser('user-a'));
      await openAndEnterAmount(tester);
      _wire['POST /deposit/validate-name'] =
          _Route(200, {'data': 'Kwame Mensah'});
      _wire['POST /deposit/fiat/initiate/moolre'] = _Route(201, {
        'requiresOtp': true,
        'data': {'reference': 'DEP-RACE-A', 'status': 'PENDING'},
      });
      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Confirm'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Enter OTP'), findsOneWidget);

      // The initiation's continuation is already stored under A.
      expect((await contSvc.loadForUser('user-a')), hasLength(1));

      // Confirm the OTP; the response is held; the session switches to
      // B before it lands.
      await tester.enterText(find.byType(TextField), '123456');
      final gate = Completer<void>();
      _wire['POST /deposit/fiat/initiate/moolre/otp'] = _Route(200, {
        'success': true,
        'data': {'reference': 'DEP-RACE-A'},
      }, gate);
      await tester.tap(find.text('Confirm deposit'));
      await tester.pump(const Duration(milliseconds: 300));

      currentAuth!.switchTo(makeUser('user-b'));
      gate.complete();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));

      // The confirmed reference UPSERTS under the initiating identity —
      // never duplicated, never reassigned to B.
      final aList = await contSvc.loadForUser('user-a');
      expect(aList, hasLength(1));
      expect(aList.single.reference, 'DEP-RACE-A');
      expect(await contSvc.loadForUser('user-b'), isEmpty);
      // Flush short-lived timers (pulsing-dots stagger etc.).
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('(f) no capturable owner: the financial mutation is '
        'BLOCKED before the wire — nothing may later be stored under '
        'any key', (tester) async {
      currentAuth = _MutableAuth(null);
      await openAndEnterAmount(tester);
      _wire['POST /deposit/validate-name'] =
          _Route(200, {'data': 'Kwame Mensah'});
      // The initiate route is deliberately NOT wired: if the blocked
      // path ever regresses and sends the request, the harness records
      // an unexpected HTTP call and this test fails loudly.
      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Confirm'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));

      // BLOCKED BEFORE THE WIRE: no financial mutation was requested.
      expect(_unexpectedCalls, isEmpty,
          reason: 'an initiation without a capturable owner must never '
              'reach the backend');
      expect(find.text('Your session ended. Sign in again to start a '
          'deposit.'), findsOneWidget);

      // No accepted operation exists: no reference was minted, no
      // fail-closed persistence state was armed, storage stays empty.
      expect(find.text('Save receipt'), findsNothing,
          reason: 'a blocked initiation mints no reference and arms no '
              'persistence-retry state');
      expect(contStorage.store.isEmpty, isTrue);

      // User B signs in and the surface is reused: NOTHING belonging
      // to the ownerless operation may ever land under B's key.
      currentAuth!.switchTo(makeUser('user-b'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(contStorage.store.isEmpty, isTrue);
      expect(await contSvc.loadForUser('user-b'), isEmpty);
      expect(await contSvc.loadForUser('user-a'), isEmpty);
      // Flush short-lived timers (pulsing-dots stagger etc.).
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('(g) FINAL REVIEW — a retry after an account switch '
        "persists under the CAPTURED owner only: B is active when the "
        'failed write is retried and B\'s key stays empty',
        (tester) async {
      currentAuth = _MutableAuth(makeUser('user-a'));
      contStorage.writeError = StateError('disk full');
      await openAndEnterAmount(tester);
      _wire['POST /deposit/validate-name'] =
          _Route(200, {'data': 'Kwame Mensah'});
      _wire['POST /deposit/fiat/initiate/moolre'] = _Route(201, {
        'requiresOtp': true,
        'data': {'reference': 'DEP-RETRY-B', 'status': 'PENDING'},
      });
      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Confirm'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Enter OTP'), findsOneWidget);
      expect(contStorage.store.isEmpty, isTrue);

      // The write failed; user B becomes active BEFORE the retry.
      currentAuth!.switchTo(makeUser('user-b'));
      contStorage.writeError = null;
      // Let the queued snackbars (failure notice + close-guard notice)
      // dismiss; the retry button is then scoped to the OTP view.
      await tester.pump(const Duration(seconds: 10));
      final otpRetry = find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.text('Save receipt'));
      expect(otpRetry, findsOneWidget);
      await tester.tap(otpRetry);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      // The retry used the CAPTURED owner (A) — never the active one.
      final aList = await contSvc.loadForUser('user-a');
      expect(aList, hasLength(1));
      expect(aList.single.reference, 'DEP-RETRY-B');
      expect(await contSvc.loadForUser('user-b'), isEmpty,
          reason: 'a retry under a switched session must never store '
              "A's operation under B's key");
      // Flush short-lived timers (pulsing-dots stagger etc.).
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('(h) FINAL REVIEW — the result view renders the '
        'instructions exactly ONCE', (tester) async {
      currentAuth = _MutableAuth(makeUser('user-a'));
      await openAndEnterAmount(tester);
      _wire['POST /deposit/validate-name'] =
          _Route(200, {'data': 'Kwame Mensah'});
      const wireInstructions =
          'Dial *170# and approve the prompt to complete this deposit.';
      _wire['POST /deposit/fiat/initiate/moolre'] = _Route(201, {
        'data': {
          'reference': 'DEP-RESULT-1',
          'status': 'PENDING',
          'instructions': wireInstructions,
        },
      });
      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Confirm'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // The result view is up with the durable reference.
      expect(find.text('DEP-RESULT-1'), findsOneWidget);
      // A single instructions block — the duplicated render is gone.
      expect(find.text(wireInstructions), findsOneWidget,
          reason: 'the result view must render the instructions block '
              'exactly once');
      // Flush short-lived timers (demo auto-confirm, stagger etc.).
      await tester.pump(const Duration(seconds: 4));
    });
  });

  // ── LAST REVIEW: pending-result cancellation semantics + settlement ────

  group('7 — LAST REVIEW: pending-result cancellation semantics + '
      'independent settlement tracking', () {
    final contStorage = _MemSecureStorage();
    late DepositContinuationsService contSvc;
    _MutableAuth? currentAuth;

    User makeUser(String id) => User(
          id: id,
          username: 'me',
          email: 'me@example.com',
          token: 'tok',
          role: 'USER',
          azamanId: 'AZM-999999999',
        );

    Widget appWithAuth() {
      contStorage.store.clear();
      contSvc = DepositContinuationsService(storage: contStorage);
      return ProviderScope(
        overrides: [
          savedMomoProvider.overrideWith(() => _FakeSavedMomo(_accounts)),
          authProvider.overrideWith((ref) => currentAuth!),
          depositContinuationsProvider.overrideWith(
            (ref) => DepositContinuationsController(contSvc),
          ),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      );
    }

    Future<void> openAndEnterAmount(WidgetTester tester) async {
      _phoneSize(tester);
      await tester.pumpWidget(appWithAuth());
      await _openDeposit(tester);
      await _enterAmount(tester);
    }

    /// Submit one no-OTP deposit and wait for its pending result view.
    Future<void> submitDeposit(WidgetTester tester, String reference) async {
      _wire['POST /deposit/validate-name'] =
          _Route(200, {'data': 'Kwame Mensah'});
      _wire['POST /deposit/fiat/initiate/moolre'] = _Route(201, {
        'data': {'reference': reference, 'status': 'PENDING'},
      });
      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Confirm'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(reference), findsOneWidget,
          reason: 'the pending result view must be showing $reference');
    }

    /// The honest local return from a pending result view.
    Future<void> backToAddCash(WidgetTester tester) async {
      await tester.tap(find.text('Back to Add Cash'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 100));
    }

    /// Deliver a settlement through the REAL socket listener fan-out
    /// and let the async resolution chain flush.
    Future<void> settle(WidgetTester tester, String reference) async {
      SocketService.instance
          .emitDepositSuccessForTesting(50, 3.1, 'MTN_MOMO', reference);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('(a) leaving the result view does not orphan the '
        'operation — a settlement for the ORIGINAL reference resolves its '
        'continuation without reopening the status screen', (tester) async {
      currentAuth = _MutableAuth(makeUser('user-a'));
      await openAndEnterAmount(tester);
      await submitDeposit(tester, 'DEP-LEAVE-1');

      await backToAddCash(tester);
      // Back on the resting instrument — the operation is NOT on screen.
      expect(find.text('DEP-LEAVE-1'), findsNothing);
      final pending = await contSvc.loadForUser('user-a');
      expect(pending, hasLength(1),
          reason: 'the submitted operation stays durably tracked after the '
              'honest local return');
      expect(pending.single.reference, 'DEP-LEAVE-1');

      // The settlement arrives for the EXACT original reference.
      await settle(tester, 'DEP-LEAVE-1');

      // Resolved — without ever reopening the deposit status screen.
      expect(await contSvc.loadForUser('user-a'), isEmpty,
          reason: 'the continuation is authoritatively resolved by the '
              'settlement alone; no status screen was reopened');
      // And the surface says so — honest user-facing status.
      expect(find.textContaining('earlier deposit DEP-LEAVE-1 completed'),
          findsOneWidget);
      // Flush short-lived timers (pulsing-dots stagger etc.).
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('(b) the pending-state action NEVER claims or implies '
        'that the provider instruction was cancelled', (tester) async {
      currentAuth = _MutableAuth(makeUser('user-a'));
      await openAndEnterAmount(tester);

      // 1. The no-OTP pending result view: the action is a RETURN, the
      //    caption says the instruction is still in progress.
      await submitDeposit(tester, 'DEP-HONEST-1');
      expect(find.text('Back to Add Cash'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing,
          reason: 'no cancellation contract exists with the provider — '
              'the label must never present a local reset as one');
      expect(find.textContaining('Leaving will not cancel it'),
          findsOneWidget,
          reason: 'the pending action must state that the submitted '
              'instruction may still complete');
      await backToAddCash(tester);

      // 2. The OTP entry path: same honest semantics for its back action.
      await _enterAmount(tester);
      _wire['POST /deposit/validate-name'] =
          _Route(200, {'data': 'Kwame Mensah'});
      _wire['POST /deposit/fiat/initiate/moolre'] = _Route(201, {
        'requiresOtp': true,
        'data': {'reference': 'DEP-HONEST-2', 'status': 'PENDING'},
      });
      await tester.tap(find.text('Add Cash').last);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Confirm'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Enter OTP'), findsOneWidget);
      expect(find.text('Back to Add Cash'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      expect(find.textContaining('going back does not cancel it'),
          findsOneWidget);
      // Flush short-lived timers (pulsing-dots stagger etc.).
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('(c) PRODUCT POLICY — a second initiation while the '
        'first deposit is still pending is EXPLICITLY SUPPORTED: both '
        'operations tracked independently, nothing silently ended',
        (tester) async {
      currentAuth = _MutableAuth(makeUser('user-a'));
      await openAndEnterAmount(tester);

      await submitDeposit(tester, 'DEP-CON-1');
      await backToAddCash(tester);

      // The first operation is still pending — start a second one.
      await _enterAmount(tester);
      await submitDeposit(tester, 'DEP-CON-2');

      // Both initiations reached the wire: neither was silently
      // suppressed, and neither implied the first one had ended.
      final initiates =
          _requests.where((b) => b.containsKey('amountGhs')).toList();
      expect(initiates, hasLength(2),
          reason: 'the concurrent-pending policy must send BOTH '
              'instructions to the provider');

      // Both operations live in the continuation lifecycle, tracked
      // independently by their exact references.
      final pending = await contSvc.loadForUser('user-a');
      expect(pending.map((c) => c.reference),
          containsAll(['DEP-CON-1', 'DEP-CON-2']));
      // Flush short-lived timers (pulsing-dots stagger etc.).
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('(d) out-of-order settlements with two distinct pending '
        'references resolve ONLY the matching reference each time — and '
        'never another user\'s', (tester) async {
      currentAuth = _MutableAuth(makeUser('user-a'));
      await openAndEnterAmount(tester);

      await submitDeposit(tester, 'DEP-ORDER-1');
      await backToAddCash(tester);
      await _enterAmount(tester);
      await submitDeposit(tester, 'DEP-ORDER-2');
      await backToAddCash(tester);
      expect((await contSvc.loadForUser('user-a')), hasLength(2));

      // OUT OF ORDER: the SECOND deposit settles first. Only its exact
      // reference resolves — the first deposit's continuation is
      // untouched.
      await settle(tester, 'DEP-ORDER-2');
      var pending = await contSvc.loadForUser('user-a');
      expect(pending, hasLength(1));
      expect(pending.single.reference, 'DEP-ORDER-1',
          reason: 'deposit B\'s settlement must never resolve, clear or '
              'confirm deposit A');

      // An unknown reference resolves nothing.
      await settle(tester, 'DEP-UNKNOWN-9');
      expect(await contSvc.loadForUser('user-a'), hasLength(1));

      // A SECOND user's pending reference: its settlement must NOT
      // resolve under the active user's authority — only the matching
      // user's reference resolves, ever.
      await contSvc.save('user-b', 'DEP-B-1');
      await settle(tester, 'DEP-B-1');
      expect((await contSvc.loadForUser('user-b')), hasLength(1),
          reason: 'a settlement event carries no identity — it can never '
              'resolve another user\'s stored continuation');
      expect(await contSvc.loadForUser('user-a'), hasLength(1));

      // The first deposit settles last — now everything for user A is
      // resolved, and user B is still intact.
      await settle(tester, 'DEP-ORDER-1');
      expect(await contSvc.loadForUser('user-a'), isEmpty);
      expect((await contSvc.loadForUser('user-b')), hasLength(1));
      // Flush short-lived timers (pulsing-dots stagger etc.).
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('(e) a resolved reference can NEVER be resurrected — not '
        'by a retry, not by a delayed storage mutation, not by a '
        'duplicate settlement event', (tester) async {
      currentAuth = _MutableAuth(makeUser('user-a'));
      await openAndEnterAmount(tester);

      await submitDeposit(tester, 'DEP-RES-1');
      await backToAddCash(tester);
      await settle(tester, 'DEP-RES-1');
      expect(await contSvc.loadForUser('user-a'), isEmpty,
          reason: 'the operation must be resolved before the resurrection '
              'assertions run');

      // A DELAYED storage mutation (a late retry of the original save)
      // for the resolved reference is a NO-OP — terminal resolution.
      await contSvc.save('user-a', 'DEP-RES-1');
      await tester.pump(const Duration(milliseconds: 100));
      expect(await contSvc.loadForUser('user-a'), isEmpty,
          reason: 'resolution is terminal: a retry or delayed save can '
              'never resurrect the resolved reference');

      // A DUPLICATE settlement event changes nothing — idempotent.
      await settle(tester, 'DEP-RES-1');
      expect(await contSvc.loadForUser('user-a'), isEmpty);
      // And the surface does not double-notify: the completion snackbar
      // from the FIRST settlement is still the only one.
      expect(find.textContaining('earlier deposit DEP-RES-1 completed'),
          findsOneWidget);
      // Flush short-lived timers (pulsing-dots stagger etc.).
      await tester.pump(const Duration(seconds: 2));
    });
  });
}


/// In-memory FlutterSecureStorage for the continuation service — same
/// async API surface the production service calls.
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

/// [_MemSecureStorage] whose WRITES can be held open or made to fail —
/// the seam that makes the continuation durability barrier observable:
/// a durable backend reference is not enough while its local record
/// has not been written.
class _GatedWriteStorage extends _MemSecureStorage {
  Completer<void>? writeGate;
  Object? writeError;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #write) {
      if (writeError != null) return Future.error(writeError!);
      final gate = writeGate;
      if (gate != null) {
        writeGate = null;
        return gate.future.then((_) => super.noSuchMethod(invocation));
      }
    }
    return super.noSuchMethod(invocation);
  }
}

/// Real-shaped auth: a logged-in user so user-scoped persistence works.
class _FixedAuth extends AuthProvider {
  _FixedAuth(this.sessionUser);
  final User sessionUser;
  @override
  User? get user => sessionUser;
  @override
  Future<void> fetchUserDetails() async {}
}

/// Auth whose session identity can be switched (or dropped) MID-TEST —
/// the seam for the account-switch races on an in-flight deposit.
class _MutableAuth extends AuthProvider {
  _MutableAuth(this.sessionUser);
  User? sessionUser;
  @override
  User? get user => sessionUser;
  @override
  Future<void> fetchUserDetails() async {}
  void switchTo(User? next) {
    sessionUser = next;
    notifyListeners();
  }
}
