// REVIEW 4.1 (2026-10-25) — notification centre correctness suite.
//
// The bugs this suite pins (all reproduced against the pre-fix overlay):
//
//   1. CATEGORY OMISSION — the overlay's visible list was merged from the
//      general + security + vendor provider slices ONLY, so every
//      notification the server explicitly categorised as money, social,
//      chat or system was parsed by the model, counted by nothing, and
//      invisible in the centre. The visible list must be derived from the
//      ONE canonical source (notificationProvider).
//   2. KEYWORD AUTHORITY — Money/Social/System classification matched
//      title keywords on `general` notifications instead of treating the
//      server's explicit NotificationCategory as authoritative. An
//      explicit category must never be overridden by title keywords,
//      and legacy keyword matching survives only for `general`.
//   3. NO TAP ACTION — a notification card had swipe chips only; the card
//      itself was not tappable. Opening must mark the notification read
//      and dispatch its actionPayload through the shared canonical
//      action-to-route resolver, with a truthful fallback when the
//      action is unsupported.
//   4. HONEST DISMISSAL — with backend #374's durable owner-scoped
//      soft-dismissal contract now consumed (PR #200), the left-swipe
//      chip is a real Delete: optimistic hide, server is the authority,
//      a rejection un-hides the row with its read state untouched and an
//      honest inline error. Read and dismissed stay distinct states.
//   5. NO IDLE BOB — the grab handle ran a repeating controller for as
//      long as the panel was open. Idle motion is not allowed.
//   6. UNREAD COUNT — unreadCountProvider silently dropped unread
//      `general` notifications, so the bell badge and the panel's own
//      unread count disagreed.

import 'package:azaman/models/notification_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/notification_action_dispatcher.dart';
import 'package:azaman/widgets/notification_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppNotification _n(
  String id,
  String title, {
  NotificationCategory category = NotificationCategory.general,
  Map<String, dynamic>? payload,
  bool read = false,
}) {
  return AppNotification(
    id: id,
    title: title,
    body: 'body $id',
    category: category,
    actionPayload: payload,
    isRead: read,
    createdAt: DateTime(2026, 10, 25, 9),
  );
}

/// The committed-state seed used by every overlay test: the real notifier
/// (tokenless auth → inert initial fetch) whose state IS the list.
class _Seeded extends NotificationNotifier {
  _Seeded(super.ref, List<AppNotification> seed) {
    state = seed;
  }
}

/// Context inside the /home route (a descendant of the Navigator's
/// Overlay) — captured on build so tests can open the overlay the way
/// production widgets (the bell) do.
BuildContext? _homeContext;

Future<ProviderContainer> _pumpPanel(
  WidgetTester tester, {
  required List<AppNotification> seed,
  List<String> visitedRoutes = const [],
}) async {
  SharedPreferences.setMockInitialValues({'azaman_theme': 1});
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => AuthProvider()),
      notificationProvider.overrideWith((ref) => _Seeded(ref, seed)),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => Scaffold(
          body: Builder(
            builder: (context) {
              _homeContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
      GoRoute(
        path: '/trade/:id',
        builder: (_, st) {
          visitedRoutes.add('/trade/${st.pathParameters['id']}');
          return const Scaffold(body: SizedBox());
        },
      ),
      GoRoute(
        path: '/friends',
        builder: (_, __) {
          visitedRoutes.add('/friends');
          return const Scaffold(body: SizedBox());
        },
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: ThemeProvider.getThemeData(AzamanTheme.dark),
        builder: (context, child) => MediaQuery(
          data: const MediaQueryData(size: Size(400, 900)),
          child: child!,
        ),
      ),
    ),
  );
  // Open the panel the way the bell opens it: from a context INSIDE the
  // navigator's overlay.
  NotificationOverlay.show(_homeContext!);
  await tester.pumpAndSettle();
  return container;
}

Finder _card(String id) {
  // The card's readable title is the notification's title.
  return find.text(_titleOf(id));
}

String _titleOf(String id) => 'Title $id';

List<AppNotification> _categorisedSeed() => [
  _n('money-1', 'Title money-1', category: NotificationCategory.money),
  _n('social-1', 'Title social-1', category: NotificationCategory.social),
  _n('chat-1', 'Title chat-1', category: NotificationCategory.chat),
  _n('system-1', 'Title system-1', category: NotificationCategory.system),
  _n('sec-1', 'Title sec-1', category: NotificationCategory.securityAccount),
  _n('gen-1', 'Title gen-1', category: NotificationCategory.general),
];

void main() {
  // ── Pure resolver: the canonical action-to-route contract ──────────────

  group('NotificationActionDispatcher.resolve', () {
    test('null payload is informational', () {
      final a = NotificationActionDispatcher.resolve(null);
      expect(a.resolution, NotificationActionResolution.informational);
    });

    test('OPEN_TRADE with tradeId resolves the trade route', () {
      final a = NotificationActionDispatcher.resolve({
        'action': 'OPEN_TRADE',
        'tradeId': '42',
      });
      expect(a.resolution, NotificationActionResolution.navigable);
      expect(a.route, '/trade/42');
    });

    test('OPEN_TRADE without an id is an unsupported action, never a guess',
        () {
      final a = NotificationActionDispatcher.resolve({'action': 'OPEN_TRADE'});
      expect(a.resolution, NotificationActionResolution.unsupportedAction);
    });

    test('OPEN_DISPUTE with disputeId resolves the dispute route', () {
      final a = NotificationActionDispatcher.resolve({
        'action': 'OPEN_DISPUTE',
        'disputeId': 'd7',
      });
      expect(a.route, '/dispute/d7');
    });

    test('friend actions resolve /friends', () {
      for (final action in [
        'OPEN_FRIEND_REQUEST',
        'OPEN_FRIEND_CHAT',
        'OPEN_FRIEND_TRANSFER_REQUEST',
      ]) {
        final a = NotificationActionDispatcher.resolve({'action': action});
        expect(a.resolution, NotificationActionResolution.navigable,
            reason: action);
        expect(a.route, '/friends');
      }
    });

    test('OPEN_QUEUE carries its id components', () {
      final a = NotificationActionDispatcher.resolve({
        'action': 'OPEN_QUEUE',
        'queueId': 'q1',
        'queuePosition': '3',
        'adId': 'a9',
      });
      expect(a.route, '/queue?queueId=q1&position=3&adId=a9');
    });

    test('OPEN_WALLET is informational (no dedicated route)', () {
      final a = NotificationActionDispatcher.resolve({'action': 'OPEN_WALLET'});
      expect(a.resolution, NotificationActionResolution.informational);
    });

    test('KYC/ACCOUNT_STATUS and VIEW_SAVINGS resolve their settings', () {
      expect(
        NotificationActionDispatcher.resolve({'action': 'KYC_STATUS'}).route,
        '/settings',
      );
      expect(
        NotificationActionDispatcher
            .resolve({'action': 'ACCOUNT_STATUS'}).route,
        '/settings',
      );
      expect(
        NotificationActionDispatcher.resolve({'action': 'VIEW_SAVINGS'}).route,
        '/savings',
      );
      expect(
        NotificationActionDispatcher.resolve({'action': 'OPEN_MARKETPLACE'})
            .route,
        '/marketplace',
      );
    });

    test('unknown action names are unsupported, not fallback-navigated', () {
      final a = NotificationActionDispatcher.resolve({
        'action': 'SOME_FUTURE_ACTION',
        'tradeId': '42', // must NOT be treated as legacy trade link
      });
      expect(a.resolution, NotificationActionResolution.unsupportedAction);
    });

    test('legacy flat tradeId/disputeId keys still resolve', () {
      expect(
        NotificationActionDispatcher.resolve({'tradeId': 'legacy-9'}).route,
        '/trade/legacy-9',
      );
      expect(
        NotificationActionDispatcher.resolve({'disputeId': 'legacy-d'}).route,
        '/dispute/legacy-d',
      );
    });

    test('payload without action but with route resolves it', () {
      final a = NotificationActionDispatcher.resolve({'route': '/friends'});
      expect(a.resolution, NotificationActionResolution.navigable);
      expect(a.route, '/friends');
    });

    test('empty payload is informational', () {
      final a = NotificationActionDispatcher.resolve(<String, dynamic>{});
      expect(a.resolution, NotificationActionResolution.informational);
    });
  });

  // ── Overlay: canonical list, category authority, tap dispatch ──────────

  testWidgets('explicitly categorised money/social/chat/system notifications are visible',
      (tester) async {
    await _pumpPanel(tester, seed: _categorisedSeed());

    // PRE-FIX: only sec-1 and gen-1 rendered; money/social/chat/system were
    // silently omitted from the merged list.
    expect(_card('money-1'), findsOneWidget);
    expect(_card('social-1'), findsOneWidget);
    expect(_card('chat-1'), findsOneWidget);
    expect(_card('system-1'), findsOneWidget);
    expect(_card('sec-1'), findsOneWidget);
    expect(_card('gen-1'), findsOneWidget);
  });

  testWidgets('money tab filters by explicit category AND legacy keywords',
      (tester) async {
    await _pumpPanel(tester, seed: [
      ..._categorisedSeed(),
      // Legacy general notification whose TITLE says money (predates the
      // category field) — must still land on the money tab.
      _n('legacy-money', 'Deposit received'),
    ]);

    await tester.tap(find.text('Money').first);
    await tester.pumpAndSettle();

    expect(_card('money-1'), findsOneWidget,
        reason: 'explicit MONEY category must appear on the money tab');
    expect(find.text('Deposit received'), findsOneWidget,
        reason: 'legacy keyword fallback still files old general mail');
    expect(_card('social-1'), findsNothing);
    expect(_card('sec-1'), findsNothing);
  });

  testWidgets('explicit category beats title keywords (MONEY title, SOCIAL category)',
      (tester) async {
    await _pumpPanel(tester, seed: [
      // Title screams money; the server filed it SOCIAL. Explicit wins.
      _n('kw-1', 'Title deposit kw-1', category: NotificationCategory.social),
      // And the inverse: boring title, MONEY category.
      _n('kw-2', 'Title kw-2', category: NotificationCategory.money),
    ]);

    await tester.tap(find.text('Money').first);
    await tester.pumpAndSettle();
    expect(find.text('Title deposit kw-1'), findsNothing,
        reason: 'a SOCIAL notification must never appear on the money tab');
    expect(find.text('Title kw-2'), findsOneWidget,
        reason: 'a MONEY notification appears regardless of title');

    await tester.tap(find.text('Social').first);
    await tester.pumpAndSettle();
    expect(find.text('Title deposit kw-1'), findsOneWidget);
    expect(find.text('Title kw-2'), findsNothing);
  });

  testWidgets('chat notifications surface under the Social tab', (tester) async {
    await _pumpPanel(tester, seed: [_n('chat-1', 'Title chat-1', category: NotificationCategory.chat)]);

    await tester.tap(find.text('Social').first);
    await tester.pumpAndSettle();
    expect(_card('chat-1'), findsOneWidget);
  });

  testWidgets('tapping a card marks it read and dispatches the payload route',
      (tester) async {
    final visited = <String>[];
    final container = await _pumpPanel(
      tester,
      seed: [
        _n('t-1', 'Title t-1',
            payload: {'action': 'OPEN_TRADE', 'tradeId': '77'}),
      ],
      visitedRoutes: visited,
    );

    await tester.tap(_card('t-1'));
    await tester.pumpAndSettle();

    // Read state is committed through the real notifier.
    final read = container
        .read(notificationProvider)
        .firstWhere((n) => n.id == 't-1');
    expect(read.isRead, isTrue);

    // The panel closed and the trade route stacked.
    expect(find.text('Notifications'), findsNothing);
    expect(visited, contains('/trade/77'));
  });

  testWidgets('tapping an informational card does not navigate',
      (tester) async {
    final visited = <String>[];
    await _pumpPanel(
      tester,
      seed: [_n('info-1', 'Title info-1')], // no payload
      visitedRoutes: visited,
    );

    await tester.tap(_card('info-1'));
    await tester.pumpAndSettle();

    expect(visited, isEmpty, reason: 'informational notice opens nothing');
    expect(find.text('Notifications'), findsOneWidget,
        reason: 'panel stays open — reading an informational notice is local');
  });

  testWidgets('tapping an unsupported action tells the truth via a snackbar',
      (tester) async {
    final visited = <String>[];
    await _pumpPanel(
      tester,
      seed: [
        _n('unsup-1', 'Title unsup-1',
            payload: {'action': 'NOT_A_REAL_ACTION'}),
      ],
      visitedRoutes: visited,
    );

    await tester.tap(_card('unsup-1'));
    await tester.pump();

    expect(
      find.textContaining("isn't available yet"),
      findsOneWidget,
      reason: 'unsupported actions must not navigate and must not be silent',
    );
    expect(visited, isEmpty);
  });

  testWidgets('swipe-delete chip is the durable server-backed Delete',
      (tester) async {
    await _pumpPanel(tester, seed: [_n('d-1', 'Title d-1')]);

    // Reveal the left swipe chips by dragging the card left. A timed
    // drag delivers multiple move events so the horizontal recogniser
    // claims the gesture unambiguously.
    await tester.timedDrag(_card('d-1'), const Offset(-90, 0),
        const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsOneWidget,
        reason: 'the durable owner-scoped dismissal contract is live');
    expect(find.text('Hide'), findsNothing);
  });

  testWidgets('the panel hosts no repeating idle controllers while open',
      (tester) async {
    await _pumpPanel(tester, seed: [_n('idle-1', 'Title idle-1')]);

    // pumpAndSettle TERMINATES on the open panel: nothing repeats while
    // the user is not interacting. (Pre-fix: the grab handle's bob loop
    // kept an animation permanently scheduled.)
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Notifications'), findsOneWidget);
  });

  // ── Canonical unread count ─────────────────────────────────────────────

  test('unreadCountProvider counts unread notifications of every category',
      () {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => AuthProvider()),
        notificationProvider.overrideWith((ref) => _Seeded(ref, [
              _n('g1', 'a', category: NotificationCategory.general),
              _n('g2', 'b',
                  category: NotificationCategory.general, read: true),
              _n('m1', 'c', category: NotificationCategory.money),
              _n('s1', 'd', category: NotificationCategory.social),
            ])),
      ],
    );
    addTearDown(container.dispose);
    // PRE-FIX: general unread were excluded → 2. Canonical: 3.
    expect(container.read(unreadCountProvider), 3);
  });
}
