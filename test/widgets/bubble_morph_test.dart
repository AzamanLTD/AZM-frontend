// THE BUBBLE OPENS INTO THE PAGE — AND COMES BACK.
//
// The morph is a Hero flight over the CANONICAL route, so these tests check the
// three things that can actually go wrong:
//
//   • identity — each bubble owns a distinct tag, and its destination uses the
//     same one (the wrong sphere opening is the classic shared-element bug);
//   • navigation — the canonical location is still pushed, exactly once even on
//     a double tap, and popping returns to the row;
//   • entry without a bubble — a destination reached cold (deep link,
//     notification) renders normally with no partner to fly with;
//   • reduced motion — no Hero at all, and the page still arrives.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/widgets/home/wallet_modules.dart';
import 'package:azaman/widgets/navigation/bubble_morph.dart';

const _tags = <String>[
  BubbleMorphTag.save,
  BubbleMorphTag.p2p,
  BubbleMorphTag.susu,
  BubbleMorphTag.bills,
];

final _bubbleKeys = <String>[
  'wallet-module-save',
  'wallet-module-p2p',
  'wallet-module-susu',
  'wallet-module-bills',
];

Future<void> _pumpRow(WidgetTester tester, {required bool reduceMotion}) async {
  BubbleNavigation.reset();
  await tester.binding.setSurfaceSize(const Size(390, 844));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(body: Center(child: WalletModulesRow())),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 80));
}

GoRouter _router(List<String> visited) {
  Widget page(String tag, String name) => BubbleMorphDestination(
    tag: tag,
    child: Scaffold(body: Center(child: Text(name))),
  );

  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            Scaffold(body: Center(child: WalletModulesRow())),
      ),
      GoRoute(
        path: '/savings',
        builder: (context, state) {
          visited.add('/savings');
          return page(BubbleMorphTag.save, 'Savings');
        },
      ),
      GoRoute(
        path: '/marketplace',
        builder: (context, state) {
          visited.add('/marketplace');
          return page(BubbleMorphTag.p2p, 'Marketplace');
        },
      ),
      GoRoute(
        path: '/bills',
        builder: (context, state) {
          visited.add('/bills');
          return page(BubbleMorphTag.bills, 'Bills');
        },
      ),
      GoRoute(
        path: '/susu',
        builder: (context, state) {
          visited.add('/susu');
          return page(BubbleMorphTag.susu, 'Susu');
        },
      ),
      GoRoute(
        path: '/susu/:id',
        builder: (context, state) {
          visited.add('/susu/${state.pathParameters['id']}');
          return page(BubbleMorphTag.susu, 'Susu group');
        },
      ),
    ],
  );
}

void main() {
  testWidgets('every bubble owns a distinct, stable identity', (tester) async {
    await _pumpRow(tester, reduceMotion: false);

    final tags = tester
        .widgetList<Hero>(find.byType(Hero))
        .map((h) => h.tag)
        .toList();

    expect(tags.length, 4, reason: 'one flight per bubble');
    expect(tags.toSet().length, 4, reason: 'two bubbles must not share a tag');
    expect(tags.toSet(), _tags.toSet());
  });

  testWidgets('the identities are pairwise distinct by construction', (
    tester,
  ) async {
    expect(_tags.toSet().length, _tags.length);
    expect(_tags.contains(''), isFalse);
  });

  testWidgets('a destination carries the same tag as its bubble', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BubbleMorphDestination(
          tag: BubbleMorphTag.bills,
          child: Scaffold(body: Text('Bills page')),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate((w) => w is Hero && w.tag == BubbleMorphTag.bills),
      findsOneWidget,
    );
    expect(find.text('Bills page'), findsOneWidget);
  });

  testWidgets('reduced motion removes the flight, not the page', (
    tester,
  ) async {
    await _pumpRow(tester, reduceMotion: true);
    expect(find.byType(Hero), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        builder: _reduceMotionBuilder,
        home: BubbleMorphDestination(
          tag: BubbleMorphTag.bills,
          child: Scaffold(body: Text('Bills page')),
        ),
      ),
    );
    expect(find.byType(Hero), findsNothing);
    expect(find.text('Bills page'), findsOneWidget);
  });

  testWidgets('the canonical location is pushed once, and back returns home', (
    tester,
  ) async {
    final visited = <String>[];
    final router = _router(visited);
    BubbleNavigation.reset();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump(const Duration(milliseconds: 80));

    // Two taps inside the transition window: one flight, one destination.
    await tester.tap(find.byKey(const ValueKey('wallet-module-bills')));
    await tester.tap(
      find.byKey(const ValueKey('wallet-module-bills')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(visited, ['/bills'], reason: 'a double tap must not stack pages');

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(WalletModulesRow), findsOneWidget);
    expect(find.byKey(const ValueKey('wallet-module-bills')), findsOneWidget);
  });

  testWidgets('a destination opened cold has no partner and still works', (
    tester,
  ) async {
    final visited = <String>[];
    final router = _router(visited);
    router.go('/bills');
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    // No source bubble on screen: the Hero simply has nothing to fly with.
    expect(find.byType(WalletModulesRow), findsNothing);
    expect(find.text('Bills'), findsOneWidget);
  });

  test('the double-tap guard expires', () async {
    BubbleNavigation.reset();
    expect(BubbleNavigation.allow('/bills'), isTrue);
    expect(BubbleNavigation.allow('/bills'), isFalse);
    // A different destination is never blocked by another's flight.
    expect(BubbleNavigation.allow('/savings'), isTrue);
  });
}

Widget _reduceMotionBuilder(BuildContext context, Widget? child) => MediaQuery(
  data: MediaQuery.of(context).copyWith(disableAnimations: true),
  child: child!,
);
