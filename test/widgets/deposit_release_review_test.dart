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
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/saved_momo_provider.dart';
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
  return ProviderScope(
    overrides: [
      savedMomoProvider.overrideWith(() => _FakeSavedMomo(_accounts)),
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
}
