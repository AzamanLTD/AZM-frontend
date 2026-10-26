// =============================================================================
// I1 — Marketplace Follow Onboarding: widget-level tests.
//
// Pins the spotlight card's honest state machine and the selection
// sheet's real behaviour against fake HTTP + fake storage:
//   • the card renders ONLY in the proven-eligible state
//   • "Maybe later" persists per user and the card never repeats
//   • selecting rows NEVER follows anything prematurely
//   • confirm fires one real POST per selected business (canonical
//     ids); confirmed counts are exact
//   • partial failure is reported exactly, retry re-fires ONLY the
//     failed rows, and a pending request can never be duplicated
//   • fewer than five eligible businesses never traps the user
//   • light/dark and narrow layouts render without overflow
// =============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/follow_onboarding_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/services/follow_onboarding_dismissal_store.dart';
import 'package:azaman/widgets/marketplace/follow_onboarding_sheet.dart';
import 'package:azaman/widgets/marketplace/follow_onboarding_spotlight.dart';

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

// ── Fake seams ───────────────────────────────────────────────────────────────

class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data[key] = value ?? '';
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data.containsKey(key);

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.clear();
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.of(_data);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fake follow-list backend: the authoritative eligibility endpoint.
class _FakeEligibilityClient extends ApiClient {
  final int status;
  final dynamic following;
  _FakeEligibilityClient({this.status = 200, this.following = const []});

  @override
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    if (endpoint.startsWith('/follows/following')) {
      return _json(status, {'success': true, 'following': following});
    }
    return _json(404, {'success': false});
  }
}

/// Fake catalogue + follow backend for the SHEET. Records every
/// POST /follows (canonical ids) and can fail chosen businesses or
/// hold requests until the test releases them.
class _FakeSheetClient extends ApiClient {
  final List<String> followCalls = [];
  final Set<String> failIds;
  final Duration delay;
  _FakeSheetClient({this.failIds = const {}, this.delay = Duration.zero});

  @override
  Future<http.Response> post(
    String endpoint,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    bool requireAuth = true,
    String? idempotencyKey,
  }) async {
    if (endpoint == '/follows') {
      final id = body['businessProfileId'].toString();
      followCalls.add(id);
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      return failIds.contains(id)
          ? _json(500, {'success': false})
          : _json(201, {'success': true});
    }
    return _json(404, {'success': false});
  }
}

class _FakeBusinessService extends BusinessService {
  _FakeBusinessService(this.results, {this.ownBusinessId});
  final List<BusinessProfile> results;
  final String? ownBusinessId;

  @override
  Future<BusinessPage> searchBusinesses({
    String? q,
    String? category,
    bool? verified,
    String? subcategory,
    int limit = 20,
    String? cursor,
  }) async => (
    businesses: results.take(limit).toList(growable: false),
    hasMore: false,
    nextCursor: null,
  );

  @override
  Future<BusinessProfile?> getMyBusiness() async {
    if (ownBusinessId == null) return null;
    return results.firstWhere((b) => b.id == ownBusinessId!);
  }
}

BusinessProfile _biz(
  String id,
  int n, {
  bool suspended = false,
  bool verified = true,
}) => BusinessProfile(
  id: id,
  bizId: 'BIZ-00$n',
  businessName: 'Business $n',
  category: 'FOOD_BEVERAGE',
  description: 'Test business $n',
  isVerified: verified,
  isSuspended: suspended,
  kybStatus: 'VERIFIED',
  totalEscrows: 0,
  completedEscrows: 0,
  userId: n + 100,
  totalVolume: 0,
  averageRating: 4.5,
  username: 'biz-$n',
  reviewCount: 0,
  products: const [],
);

List<BusinessProfile> _catalogue(int n) => [
  for (var i = 1; i <= n; i++) _biz('bp-$i', i),
];

// ── Harness ──────────────────────────────────────────────────────────────────

Future<void> _pumpSpotlight(
  WidgetTester tester, {
  String? userId = 'user-1',
  required ApiClient eligibilityClient,
  required FlutterSecureStorage storage,
  Widget? child,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(eligibilityClient),
        followOnboardingDismissalStoreProvider.overrideWithValue(
          FollowOnboardingDismissalStore(storage: storage),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              child ??
                  FollowOnboardingSpotlight(userId: userId, onStart: () {}),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Selects a catalogue row safely: scrolls it into view first (rows
/// can sit below the sheet's fold on small test surfaces).
Future<void> _selectRow(WidgetTester tester, String id) async {
  final row = find.byKey(ValueKey('follow-onboarding-pick-$id'));
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pump();
}

Future<void> _openSheet(
  WidgetTester tester, {
  required ApiClient sheetClient,
  required BusinessService service,
  Brightness brightness = Brightness.light,
  Size surface = const Size(390, 900),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(sheetClient)],
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => FollowOnboardingSheet.open(
                  context,
                  api: sheetClient,
                  service: service,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

// ── Spotlight ────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('spotlight card — honest state machine', () {
    testWidgets('renders with real actions ONLY when the authoritative '
        'list proves eligibility', (tester) async {
      await _pumpSpotlight(
        tester,
        eligibilityClient: _FakeEligibilityClient(following: []),
        storage: _FakeSecureStorage(),
      );

      expect(
        find.byKey(const ValueKey('follow-onboarding-spotlight')),
        findsOneWidget,
      );
      expect(find.text('Follow businesses you care about.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('follow-onboarding-start')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('follow-onboarding-maybe-later')),
        findsOneWidget,
      );
      expect(
        find.textContaining('"Your follows" rail'),
        findsOneWidget,
        reason:
            'the copy references the EXISTING discovery rail and '
            'promises nothing else',
      );
    });

    testWidgets('non-empty follow list -> no card', (tester) async {
      await _pumpSpotlight(
        tester,
        eligibilityClient: _FakeEligibilityClient(
          following: [
            {'businessProfileId': 'bp-7'},
          ],
        ),
        storage: _FakeSecureStorage(),
      );
      expect(
        find.byKey(const ValueKey('follow-onboarding-spotlight')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('follow-onboarding-none')),
        findsOneWidget,
      );
    });

    testWidgets('failed request / malformed body -> no card (NEVER '
        'eligible-by-accident)', (tester) async {
      await _pumpSpotlight(
        tester,
        eligibilityClient: _FakeEligibilityClient(status: 500),
        storage: _FakeSecureStorage(),
      );
      expect(
        find.byKey(const ValueKey('follow-onboarding-spotlight')),
        findsNothing,
      );

      await _pumpSpotlight(
        tester,
        eligibilityClient: _FakeEligibilityClient(following: 'garbage'),
        storage: _FakeSecureStorage(),
      );
      expect(
        find.byKey(const ValueKey('follow-onboarding-spotlight')),
        findsNothing,
      );
    });

    testWidgets('unauthenticated -> no card', (tester) async {
      await _pumpSpotlight(
        tester,
        userId: null,
        eligibilityClient: _FakeEligibilityClient(following: []),
        storage: _FakeSecureStorage(),
      );
      expect(
        find.byKey(const ValueKey('follow-onboarding-spotlight')),
        findsNothing,
      );
    });

    testWidgets('Maybe later persists per user and the card never '
        'repeats', (tester) async {
      final storage = _FakeSecureStorage();
      await _pumpSpotlight(
        tester,
        eligibilityClient: _FakeEligibilityClient(following: []),
        storage: storage,
      );

      await tester.tap(
        find.byKey(const ValueKey('follow-onboarding-maybe-later')),
      );
      await tester.pumpAndSettle();

      // Gone immediately.
      expect(
        find.byKey(const ValueKey('follow-onboarding-spotlight')),
        findsNothing,
      );
      // Persisted for THIS user.
      final raw = await storage.read(
        key: 'azm.marketplace.followOnboarding.user-1',
      );
      expect(raw, isNotNull, reason: 'the dismissal is durable');

      // Never repeats on a fresh pump (same store).
      await _pumpSpotlight(
        tester,
        eligibilityClient: _FakeEligibilityClient(following: []),
        storage: storage,
      );
      expect(
        find.byKey(const ValueKey('follow-onboarding-spotlight')),
        findsNothing,
        reason: 'the persisted dismissal survives relaunch',
      );
    });

    testWidgets('Choose businesses opens the selection sheet', (tester) async {
      final sheetClient = _FakeSheetClient();
      final service = _FakeBusinessService(_catalogue(3));
      await _pumpSpotlight(
        tester,
        eligibilityClient: _FakeEligibilityClient(following: []),
        storage: _FakeSecureStorage(),
        child: Builder(
          builder: (context) => FollowOnboardingSpotlight(
            userId: 'user-1',
            onStart: () => FollowOnboardingSheet.open(
              context,
              api: sheetClient,
              service: service,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('follow-onboarding-start')));
      await tester.pumpAndSettle();

      expect(find.text('Follow 1 business'), findsNothing);
      expect(
        find.byKey(const ValueKey('follow-onboarding-pick-bp-1')),
        findsOneWidget,
      );
    });
  });

  // ── Selection sheet ───────────────────────────────────────────────────────

  group('selection sheet — selection is not following', () {
    testWidgets('select/deselect never fires a follow request', (tester) async {
      final client = _FakeSheetClient();
      await _openSheet(
        tester,
        sheetClient: client,
        service: _FakeBusinessService(_catalogue(6)),
      );

      await _selectRow(tester, 'bp-1');
      await _selectRow(tester, 'bp-2');

      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('Follow 2 businesses'), findsOneWidget);
      expect(
        client.followCalls,
        isEmpty,
        reason:
            'selecting a row is NOT a follow — nothing mutates '
            'before the explicit confirm',
      );

      await _selectRow(tester, 'bp-2');
      expect(find.text('1 selected'), findsOneWidget);
      expect(client.followCalls, isEmpty);
    });
  });

  group('selection sheet — confirm, exact counts, completion', () {
    testWidgets('confirm follows each selected business exactly once '
        'with canonical ids and reports the confirmed count', (tester) async {
      final client = _FakeSheetClient();
      await _openSheet(
        tester,
        sheetClient: client,
        service: _FakeBusinessService(_catalogue(6)),
      );

      for (final n in [1, 2, 3, 4, 5]) {
        await _selectRow(tester, 'bp-$n');
      }
      await tester.tap(
        find.byKey(const ValueKey('follow-onboarding-sheet-confirm')),
      );
      await tester.pumpAndSettle();

      expect(client.followCalls.length, 5);
      expect(
        client.followCalls.toSet(),
        {'bp-1', 'bp-2', 'bp-3', 'bp-4', 'bp-5'},
        reason:
            'each business was requested exactly once, keyed by '
            'canonical id',
      );
      expect(
        find.byKey(const ValueKey('follow-onboarding-sheet-done')),
        findsOneWidget,
      );
      expect(find.text('Following 5 businesses — done'), findsOneWidget);
    });

    testWidgets('duplicate prevention: a pending request can never be '
        're-requested (no double-follow)', (tester) async {
      final client = _FakeSheetClient(delay: const Duration(milliseconds: 400));
      await _openSheet(
        tester,
        sheetClient: client,
        service: _FakeBusinessService(_catalogue(2)),
      );

      await _selectRow(tester, 'bp-1');
      await tester.tap(
        find.byKey(const ValueKey('follow-onboarding-sheet-confirm')),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Confirm is dead while the request is in flight; hammering it
      // must not duplicate the follow.
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('follow-onboarding-sheet-confirm')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.byKey(const ValueKey('follow-onboarding-sheet-confirm')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(
        client.followCalls,
        ['bp-1'],
        reason:
            'one business, exactly one request, no matter how '
            'many times confirm is hammered',
      );
    });
  });

  group('selection sheet — partial failure and retry', () {
    testWidgets('partial success is reported exactly; retry re-fires '
        'ONLY the failed rows and never touches the confirmed ones', (
      tester,
    ) async {
      final client = _FakeSheetClient(failIds: {'bp-2', 'bp-4'});
      await _openSheet(
        tester,
        sheetClient: client,
        service: _FakeBusinessService(_catalogue(5)),
      );

      for (final n in [1, 2, 3, 4, 5]) {
        await _selectRow(tester, 'bp-$n');
      }
      await tester.tap(
        find.byKey(const ValueKey('follow-onboarding-sheet-confirm')),
      );
      await tester.pumpAndSettle();

      // 3 of 5 real follows happened; the summary is exact.
      expect(
        find.text('Followed 3 of 5 — the rest can be retried.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('follow-onboarding-sheet-retry')),
        findsOneWidget,
      );
      expect(find.text('Retry 2 failed'), findsOneWidget);

      // The confirmed rows are already checked — retry cannot touch
      // them.
      expect(client.followCalls.toSet(), {
        'bp-1',
        'bp-2',
        'bp-3',
        'bp-4',
        'bp-5',
      });

      // Second attempt: the backend now accepts the two that failed.
      client.failIds.clear();
      await tester.tap(
        find.byKey(const ValueKey('follow-onboarding-sheet-retry')),
      );
      await tester.pumpAndSettle();

      // Only the two failures were re-requested.
      expect(client.followCalls.length, 7);
      expect(
        client.followCalls.where((id) => id == 'bp-1').length,
        1,
        reason: 'a confirmed follow is never re-requested',
      );
      expect(client.followCalls.where((id) => id == 'bp-3').length, 1);
      expect(client.followCalls.where((id) => id == 'bp-5').length, 1);
      expect(client.followCalls.where((id) => id == 'bp-2').length, 2);
      expect(client.followCalls.where((id) => id == 'bp-4').length, 2);

      // After the retry everything is confirmed: completion state.
      expect(find.text('Following 5 businesses — done'), findsOneWidget);
    });
  });

  group('selection sheet — fewer than five eligible businesses', () {
    testWidgets('three eligible businesses: any honest selection '
        'completes; the user is never trapped', (tester) async {
      final client = _FakeSheetClient();
      await _openSheet(
        tester,
        sheetClient: client,
        service: _FakeBusinessService(_catalogue(3)),
      );

      expect(
        find.textContaining('Few businesses are listed yet'),
        findsOneWidget,
        reason:
            'the copy explains the real catalogue, never fakes '
            'a larger selection',
      );

      for (final n in [1, 2, 3]) {
        await _selectRow(tester, 'bp-$n');
      }
      await tester.tap(
        find.byKey(const ValueKey('follow-onboarding-sheet-confirm')),
      );
      await tester.pumpAndSettle();

      expect(client.followCalls.length, 3);
      expect(
        find.text('Following 3 businesses — done'),
        findsOneWidget,
        reason: 'completion at min(5, eligible) confirmed follows',
      );
    });

    testWidgets('one of three followed: an honest under-five '
        'selection completes — the catalogue size never traps the '
        'user', (tester) async {
      final client = _FakeSheetClient();
      await _openSheet(
        tester,
        sheetClient: client,
        service: _FakeBusinessService(_catalogue(3)),
      );

      await _selectRow(tester, 'bp-1');
      await tester.tap(
        find.byKey(const ValueKey('follow-onboarding-sheet-confirm')),
      );
      await tester.pumpAndSettle();

      expect(client.followCalls, ['bp-1']);
      expect(
        find.text('Following 1 business — done'),
        findsOneWidget,
        reason:
            'with fewer than five eligible businesses the user '
            'own honest selection is the completion target — '
            'requiring ALL rows would trap anyone who does not '
            'care about the rest',
      );
    });

    testWidgets('a persistently failing row under five: retry stays '
        'honest and the browse-the-marketplace fallback is always '
        'offered — never trapped', (tester) async {
      final client = _FakeSheetClient(failIds: {'bp-2'});
      await _openSheet(
        tester,
        sheetClient: client,
        service: _FakeBusinessService(_catalogue(3)),
      );

      for (final n in [1, 2, 3]) {
        await _selectRow(tester, 'bp-$n');
      }
      await tester.tap(
        find.byKey(const ValueKey('follow-onboarding-sheet-confirm')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Followed 2 of 3 — the rest can be retried.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('follow-onboarding-sheet-retry')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('follow-onboarding-sheet-browse')),
        findsOneWidget,
        reason:
            'the spec-promised discovery fallback must exist when '
            'a row can keep failing forever',
      );
      expect(
        find.byKey(const ValueKey('follow-onboarding-sheet-done')),
        findsNothing,
        reason: 'a failed follow can never masquerade as done',
      );

      // Retry re-fires ONLY the failed row — still failing here.
      await tester.tap(
        find.byKey(const ValueKey('follow-onboarding-sheet-retry')),
      );
      await tester.pumpAndSettle();
      expect(client.followCalls.length, 4,
          reason: 'bp-1/bp-3 once each, bp-2 twice (confirm + retry)');
      expect(
        find.byKey(const ValueKey('follow-onboarding-sheet-browse')),
        findsOneWidget,
        reason: 'the fallback survives a failed retry',
      );

      // The fallback is an honest exit: confirmed follows are real,
      // nothing else is mutated, the sheet closes.
      await tester.tap(
        find.byKey(const ValueKey('follow-onboarding-sheet-browse')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('follow-onboarding-pick-bp-1')),
        findsNothing,
        reason: 'the sheet is gone; the two real follows persist',
      );
    });

    testWidgets('empty catalogue: honest absence, no invented '
        'businesses', (tester) async {
      final client = _FakeSheetClient();
      await _openSheet(
        tester,
        sheetClient: client,
        service: _FakeBusinessService([]),
      );

      expect(find.text('No businesses are listed yet.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('follow-onboarding-sheet-confirm')),
        findsNothing,
      );
    });

    testWidgets('suspended and own businesses are not offered', (tester) async {
      final client = _FakeSheetClient();
      await _openSheet(
        tester,
        sheetClient: client,
        service: _FakeBusinessService([
          _biz('bp-1', 1),
          _biz('bp-2', 2, suspended: true),
          _biz('bp-3', 3),
          _biz('bp-own', 4),
        ], ownBusinessId: 'bp-own'),
      );

      expect(
        find.byKey(const ValueKey('follow-onboarding-pick-bp-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('follow-onboarding-pick-bp-2')),
        findsNothing,
        reason: 'a suspended business can never be offered',
      );
      expect(
        find.byKey(const ValueKey('follow-onboarding-pick-bp-3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('follow-onboarding-pick-bp-own')),
        findsNothing,
        reason:
            'the backend rejects self-follows — the sheet must '
            'not offer a row that can only fail',
      );
    });
  });

  group('selection sheet — responsive layout and themes', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets(
        'renders without overflow in $brightness on a 360dp surface',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await _openSheet(
            tester,
            sheetClient: _FakeSheetClient(),
            service: _FakeBusinessService(_catalogue(6)),
            brightness: brightness,
          );

          expect(
            tester.takeException(),
            isNull,
            reason: 'no layout overflow in $brightness',
          );
          expect(
            find.byKey(const ValueKey('follow-onboarding-pick-bp-1')),
            findsOneWidget,
          );
        },
      );
    }
  });
}
