// §C launcher-drafts tests: the transient continuation system's
// contract — stable (user, surface) identity, wall-clock expiry at
// every read, explicit-Keep-only renewal, user scoping, logout
// clearing, and the guard's empty-form / Keep / Discard paths.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/services/launcher_drafts.dart';
import 'package:azaman/widgets/launcher_exit_prompt.dart';

/// In-memory FlutterSecureStorage. The real one has no test double on
/// this platform, and the drafts service must be exercised against the
/// SAME async API surface it uses in production.
class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> store = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final named = invocation.namedArguments;
    switch (invocation.memberName) {
      case #read:
        final key = named[#key] as String;
        return Future.value(store[key]);
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
      case #containsKey:
        return Future.value(store.containsKey(named[#key] as String));
      case #readAll:
        return Future.value(Map.of(store));
      default:
        throw UnimplementedError('${invocation.memberName}');
    }
  }
}

void main() {
  late _FakeSecureStorage storage;
  late LauncherDraftsService service;
  const uid = 'user-1';
  const otherUid = 'user-2';

  LauncherDraft draft({
    required LauncherSurface surface,
    required int savedAtMs,
    Map<String, dynamic> payload = const {'amountRaw': '50'},
    String? userId,
  }) => LauncherDraft(
    id: LauncherDraftsController.draftId(userId ?? uid, surface),
    surface: surface,
    savedAtMs: savedAtMs,
    payload: payload,
  );

  setUp(() {
    storage = _FakeSecureStorage();
    service = LauncherDraftsService(storage: storage);
  });

  group('LauncherDraft expiry model', () {
    test('a draft is alive at the TTL boundary, dead one ms after', () {
      const savedAt = 1000000;
      final d = draft(surface: LauncherSurface.send, savedAtMs: savedAt);
      final ttlMs = kLauncherDraftTtl.inMilliseconds;
      // The model judges with a strict >: at exactly five minutes the
      // draft still reads alive; one ms later it is gone for good.
      expect(d.isExpiredAt(savedAt + ttlMs - 1), isFalse);
      expect(d.isExpiredAt(savedAt + ttlMs), isFalse);
      expect(d.isExpiredAt(savedAt + ttlMs + 1), isTrue);
    });

    test('minutesLeftAt never reports a negative remainder', () {
      final d = draft(
        surface: LauncherSurface.convert,
        savedAtMs: 0,
        payload: {'amountRaw': '10', 'reversed': true},
      );
      expect(
        d.minutesLeftAt(d.savedAtMs + kLauncherDraftTtl.inMilliseconds),
        'expiring',
      );
      expect(d.minutesLeftAt(d.savedAtMs + 60000), '4m left');
    });

    test('json round-trips surface, payload and identity', () {
      final d = draft(
        surface: LauncherSurface.withdraw,
        savedAtMs: 123,
        payload: {'amountRaw': '75.50', 'entryIndex': 2},
      );
      final back = LauncherDraft.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(d.toJson())) as Map),
      );
      expect(back, isNotNull);
      expect(back!.surface, LauncherSurface.withdraw);
      expect(back.payload['amountRaw'], '75.50');
      expect(back.id, d.id);
    });

    test('corrupt or foreign json is dropped, never thrown', () {
      expect(LauncherDraft.fromJson({'id': 'x'}), isNull);
      expect(
        LauncherDraft.fromJson({
          'id': 'send.$uid',
          'surface': 'nonsense',
          'savedAtMs': 5,
          'payload': <String, dynamic>{},
        }),
        isNull,
      );
    });
  });

  group('LauncherDraftsService', () {
    test('keep then load returns the draft with payload intact', () async {
      await service.keep(
        uid,
        draft(
          surface: LauncherSurface.send,
          savedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      final loaded = await service.loadForUser(uid);
      expect(loaded, hasLength(1));
      expect(loaded.single.surface, LauncherSurface.send);
      expect(loaded.single.payload['amountRaw'], '50');
    });

    test('re-Keep UPSERTS: one card per (user, surface)', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await service.keep(
        uid,
        draft(surface: LauncherSurface.send, savedAtMs: now - 60000),
      );
      await service.keep(
        uid,
        draft(
          surface: LauncherSurface.send,
          savedAtMs: now,
          payload: {'amountRaw': '99'},
        ),
      );
      final loaded = await service.loadForUser(uid);
      expect(loaded, hasLength(1));
      expect(loaded.single.payload['amountRaw'], '99');
    });

    test('distinct surfaces coexist as distinct drafts', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await service.keep(
        uid,
        draft(surface: LauncherSurface.send, savedAtMs: now),
      );
      await service.keep(
        uid,
        draft(surface: LauncherSurface.addCash, savedAtMs: now),
      );
      expect(await service.loadForUser(uid), hasLength(2));
    });

    test(
      'expiry is enforced AT READ: an expired draft is gone for good',
      () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        await service.keep(
          uid,
          draft(
            surface: LauncherSurface.send,
            savedAtMs: now - kLauncherDraftTtl.inMilliseconds - 1,
          ),
        );
        expect(await service.loadForUser(uid), isEmpty);
        expect(await service.loadForUser(uid), isEmpty);
        expect(storage.store['azm.launcher.drafts.$uid'], isNull);
      },
    );

    test(
      'a fresh draft survives; only the expired sibling is removed',
      () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        await service.keep(
          uid,
          draft(
            surface: LauncherSurface.send,
            savedAtMs: now - kLauncherDraftTtl.inMilliseconds - 1,
          ),
        );
        await service.keep(
          uid,
          draft(surface: LauncherSurface.convert, savedAtMs: now),
        );
        final loaded = await service.loadForUser(uid);
        expect(loaded, hasLength(1));
        expect(loaded.single.surface, LauncherSurface.convert);
      },
    );

    test('discard is permanent', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final d = draft(surface: LauncherSurface.withdraw, savedAtMs: now);
      await service.keep(uid, d);
      await service.discard(uid, d.id);
      expect(await service.loadForUser(uid), isEmpty);
    });

    test('drafts are user-scoped: no cross-user bleed', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await service.keep(
        uid,
        draft(surface: LauncherSurface.send, savedAtMs: now),
      );
      expect(await service.loadForUser(otherUid), isEmpty);
    });

    test('clearAll wipes the user block (logout/account switch)', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await service.keep(
        uid,
        draft(surface: LauncherSurface.send, savedAtMs: now),
      );
      await service.clearAll(uid);
      expect(await service.loadForUser(uid), isEmpty);
      expect(storage.store.containsKey('azm.launcher.drafts.$uid'), isFalse);
    });

    test('a corrupt blob reads as empty, never throws', () async {
      await storage.write(key: 'azm.launcher.drafts.$uid', value: '{not json');
      expect(await service.loadForUser(uid), isEmpty);
    });
  });

  group('LauncherDraftsController', () {
    test('draftId is stable per (user, surface)', () {
      expect(
        LauncherDraftsController.draftId(uid, LauncherSurface.send),
        LauncherDraftsController.draftId(uid, LauncherSurface.send),
      );
      expect(
        LauncherDraftsController.draftId(uid, LauncherSurface.send),
        isNot(LauncherDraftsController.draftId(uid, LauncherSurface.convert)),
      );
      expect(
        LauncherDraftsController.draftId(uid, LauncherSurface.send),
        isNot(LauncherDraftsController.draftId(otherUid, LauncherSurface.send)),
      );
    });

    test('controller: keep -> load -> discard lifecycle', () async {
      final overridden = ProviderContainer(
        overrides: [
          launcherDraftsProvider.overrideWith(
            (ref) => LauncherDraftsController(
              LauncherDraftsService(storage: storage),
            ),
          ),
        ],
      );
      addTearDown(overridden.dispose);
      final c = overridden.read(launcherDraftsProvider.notifier);
      final now = DateTime.now().millisecondsSinceEpoch;
      await c.loadForUser(uid);
      await c.keepDraft(draft(surface: LauncherSurface.send, savedAtMs: now));
      expect(overridden.read(launcherDraftsProvider).drafts, hasLength(1));
      await c.discardDraft(
        LauncherDraftsController.draftId(uid, LauncherSurface.send),
      );
      expect(overridden.read(launcherDraftsProvider).drafts, isEmpty);
    });

    test('loadForUser(null) resets state without touching storage', () async {
      final overridden = ProviderContainer(
        overrides: [
          launcherDraftsProvider.overrideWith(
            (ref) => LauncherDraftsController(
              LauncherDraftsService(storage: storage),
            ),
          ),
        ],
      );
      addTearDown(overridden.dispose);
      final c = overridden.read(launcherDraftsProvider.notifier);
      await c.loadForUser(null);
      expect(overridden.read(launcherDraftsProvider).userId, isNull);
      expect(storage.store, isEmpty);
    });

    test('clearForLogout wipes state and the stored block', () async {
      final overridden = ProviderContainer(
        overrides: [
          launcherDraftsProvider.overrideWith(
            (ref) => LauncherDraftsController(
              LauncherDraftsService(storage: storage),
            ),
          ),
        ],
      );
      addTearDown(overridden.dispose);
      final c = overridden.read(launcherDraftsProvider.notifier);
      final now = DateTime.now().millisecondsSinceEpoch;
      await c.loadForUser(uid);
      await c.keepDraft(
        draft(surface: LauncherSurface.convert, savedAtMs: now),
      );
      await c.clearForLogout();
      expect(overridden.read(launcherDraftsProvider).drafts, isEmpty);
      expect(storage.store['azm.launcher.drafts.$uid'], isNull);
    });
  });

  group('guardLauncherClose', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('empty form: no prompt, stale draft discarded, closes', (
      tester,
    ) async {
      final svc = LauncherDraftsService(storage: storage);
      await svc.keep(
        uid,
        draft(
          surface: LauncherSurface.send,
          savedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          launcherDraftsProvider.overrideWith(
            (ref) => LauncherDraftsController(svc),
          ),
        ],
      );
      addTearDown(container.dispose);
      // The notification centre loads drafts on open; the guard's
      // controller-side discards assume that load has happened.
      await container.read(launcherDraftsProvider.notifier).loadForUser(uid);

      var closed = false;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: host(const SizedBox()),
        ),
      );

      await guardLauncherClose(
        context: tester.element(find.byType(Scaffold)),
        ref: _RefShim(container),
        userId: uid,
        surface: LauncherSurface.send,
        hasMeaningfulInput: false,
        capture: () => {'amountRaw': '1'},
        doClose: () => closed = true,
      );

      expect(closed, isTrue);
      expect(await svc.loadForUser(uid), isEmpty);
    });

    testWidgets('meaningful form + Keep persists the draft and closes', (
      tester,
    ) async {
      final svc = LauncherDraftsService(storage: storage);
      final container = ProviderContainer(
        overrides: [
          launcherDraftsProvider.overrideWith(
            (ref) => LauncherDraftsController(svc),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(launcherDraftsProvider.notifier).loadForUser(uid);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: host(const SizedBox()),
        ),
      );

      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpAndSettle();

      var closed = false;
      final future = guardLauncherClose(
        context: tester.element(find.byType(Scaffold)),
        ref: _RefShim(container),
        userId: uid,
        surface: LauncherSurface.send,
        hasMeaningfulInput: true,
        capture: () => {'amountRaw': '42', 'recipient': 'Ama'},
        doClose: () => closed = true,
      );
      await tester.pumpAndSettle();
      final keepFinder = find.text('Keep for 5 minutes');
      expect(keepFinder, findsOneWidget);
      await tester.tap(keepFinder);
      await future;
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      final drafts = await svc.loadForUser(uid);
      expect(drafts, hasLength(1));
      expect(drafts.single.payload['recipient'], 'Ama');
    });

    testWidgets('meaningful form + Discard drops the draft and closes', (
      tester,
    ) async {
      final svc = LauncherDraftsService(storage: storage);
      final container = ProviderContainer(
        overrides: [
          launcherDraftsProvider.overrideWith(
            (ref) => LauncherDraftsController(svc),
          ),
        ],
      );
      addTearDown(container.dispose);

      final now = DateTime.now().millisecondsSinceEpoch;
      await svc.keep(uid, draft(surface: LauncherSurface.send, savedAtMs: now));
      await container.read(launcherDraftsProvider.notifier).loadForUser(uid);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: host(const SizedBox()),
        ),
      );

      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpAndSettle();

      var closed = false;
      final future = guardLauncherClose(
        context: tester.element(find.byType(Scaffold)),
        ref: _RefShim(container),
        userId: uid,
        surface: LauncherSurface.send,
        hasMeaningfulInput: true,
        capture: () => {'amountRaw': '7'},
        doClose: () => closed = true,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard draft'));
      await future;
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(await svc.loadForUser(uid), isEmpty);
    });

    testWidgets(
      'unauthenticated Keep degrades to a plain close — nothing persists',
      (tester) async {
        final svc = LauncherDraftsService(storage: storage);
        final container = ProviderContainer(
          overrides: [
            launcherDraftsProvider.overrideWith(
              (ref) => LauncherDraftsController(svc),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: host(const SizedBox()),
          ),
        );

        await tester.binding.setSurfaceSize(const Size(430, 932));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpAndSettle();

        var closed = false;
        final future = guardLauncherClose(
          context: tester.element(find.byType(Scaffold)),
          ref: _RefShim(container),
          userId: null,
          surface: LauncherSurface.send,
          hasMeaningfulInput: true,
          capture: () => {'amountRaw': '9'},
          doClose: () => closed = true,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keep for 5 minutes'));
        await future;
        await tester.pumpAndSettle();

        expect(closed, isTrue);
        expect(storage.store, isEmpty);
      },
    );
  });

  // ── Deposit-lifecycle identity boundaries (PR #202 item 1) ───────────
  //
  // The Add Cash draft now carries a pendingReference while a deposit
  // is in flight. That reference is the identity of real money moving
  // at the provider — it must stay inside the authenticated user's
  // scoped draft block and can never persist for an unauthenticated
  // close.
  group('deposit draft identity boundaries', () {
    test('an in-flight reference round-trips inside the user-scoped draft '
        'and resumes as the exact payload', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await service.keep(
        uid,
        draft(
          surface: LauncherSurface.addCash,
          savedAtMs: now,
          payload: {
            'amountRaw': '50',
            'accountId': 'acct-a',
            'pendingReference': 'MOOLRE_DEP_12_1712345678_a1b2c3d4',
          },
        ),
      );

      final loaded = await service.loadForUser(uid);
      expect(loaded, hasLength(1));
      expect(loaded.single.surface, LauncherSurface.addCash);
      // Resume pushes the stored payload verbatim as route extra — the
      // recovery service then reconciles the reference against THIS
      // user's ledger (DepositRecoveryService).
      expect(
        loaded.single.payload['pendingReference'],
        'MOOLRE_DEP_12_1712345678_a1b2c3d4',
      );
      expect(loaded.single.payload['amountRaw'], '50');

      // The reference lives ONLY under this user's key: a different
      // authenticated user reads nothing of it.
      expect(await service.loadForUser(otherUid), isEmpty);
    });

    testWidgets('unauthenticated Keep with an in-flight deposit degrades to a '
        'plain close — the reference never persists', (tester) async {
      final svc = LauncherDraftsService(storage: storage);
      final container = ProviderContainer(
        overrides: [
          launcherDraftsProvider.overrideWith(
            (ref) => LauncherDraftsController(svc),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: Scaffold(body: const SizedBox())),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpAndSettle();

      var closed = false;
      final future = guardLauncherClose(
        context: tester.element(find.byType(Scaffold)),
        ref: _RefShim(container),
        userId: null,
        surface: LauncherSurface.addCash,
        hasMeaningfulInput: true,
        capture: () => {
          'amountRaw': '50',
          'pendingReference': 'MOOLRE_DEP_12_1712345678_a1b2c3d4',
        },
        doClose: () => closed = true,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep for 5 minutes'));
      await future;
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(
        storage.store,
        isEmpty,
        reason: 'a payment reference must never persist anonymously',
      );
    });
  });
}

/// The guard only calls `ref.read`; a ProviderContainer satisfies that
/// without a real build context.
class _RefShim implements WidgetRef {
  _RefShim(this.container);
  final ProviderContainer container;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final member = invocation.memberName;
    if (member == #read) {
      final provider = invocation.positionalArguments.single;
      return container.read(provider as dynamic);
    }
    throw UnimplementedError('guardLauncherClose only uses ref.read');
  }
}
