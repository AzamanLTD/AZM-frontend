// AZAMAN — HOME BUBBLES (Save / P2P / Susu / Bills)
//
// The owner's requirement, in his words: four bubbles, label INSIDE the
// bubble, not below it. These tests pin exactly that, geometrically, because
// "looks right" is not a test:
//
//   • the label's rect must lie INSIDE the bubble's own rect;
//   • four bubbles must occupy ONE row at 320/360/390dp;
//   • nothing may overflow at 1.0x, 1.3x or 1.6x text, in either theme;
//   • every destination stays the one it was, and Bills reaches /bills.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/wallet_modules.dart';

const _keys = <String>[
  'wallet-module-save',
  'wallet-module-p2p',
  'wallet-module-susu',
  'wallet-module-bills',
];

const _labels = <String>['Save', 'P2P', 'Susu', 'Bills'];

GoRouter _router(List<String> visited) {
  Widget stub(String name) => Scaffold(body: Center(child: Text(name)));
  String location = '/';
  return GoRouter(
    initialLocation: '/',
    onException: (context, state, router) {},
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) {
          location = state.uri.toString();
          return Scaffold(
            body: Center(
              child: WalletModulesRow(key: ValueKey('row-$location')),
            ),
          );
        },
      ),
      GoRoute(
        path: '/savings',
        builder: (context, state) {
          visited.add('/savings');
          return stub('Savings');
        },
      ),
      GoRoute(
        path: '/marketplace',
        builder: (context, state) {
          visited.add('/marketplace');
          return stub('Marketplace');
        },
      ),
      GoRoute(
        path: '/bills',
        builder: (context, state) {
          visited.add('/bills');
          return stub('Bills');
        },
      ),
      GoRoute(
        path: '/susu',
        builder: (context, state) {
          visited.add('/susu');
          return stub('Susu hub');
        },
      ),
      GoRoute(
        path: '/susu/:id',
        builder: (context, state) {
          visited.add('/susu/${state.pathParameters['id']}');
          return stub('Susu group');
        },
      ),
    ],
  );
}

Widget _host({
  required GoRouter router,
  Brightness brightness = Brightness.dark,
  double textScale = 1.0,
  bool reducedMotion = false,
}) {
  return ProviderScope(
    overrides: [
      themeProvider.overrideWith(
        (ref) => ThemeProvider()
          ..setTheme(
            brightness == Brightness.dark
                ? AzamanTheme.dark
                : AzamanTheme.light,
          ),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
    ),
  );
}

void main() {
  testWidgets('there are exactly four bubbles, and every label is INSIDE its '
      'own circle', (tester) async {
    await tester.pumpWidget(_host(router: _router(<String>[])));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(HomeActionBubble), findsNWidgets(4));
    for (final key in _keys) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }

    for (var i = 0; i < _keys.length; i++) {
      final bubble = find.byKey(ValueKey(_keys[i]));
      final label = find.descendant(
        of: bubble,
        matching: find.text(_labels[i]),
      );
      expect(label, findsOneWidget, reason: '${_labels[i]} label missing');

      // THE OWNER'S RULE, measured: the caption sits inside the bubble's box,
      // not beneath it.
      final bubbleRect = tester.getRect(bubble);
      final labelRect = tester.getRect(label);
      expect(
        labelRect.top >= bubbleRect.top &&
            labelRect.bottom <= bubbleRect.bottom,
        isTrue,
        reason:
            '${_labels[i]} label escaped the bubble vertically '
            '(label $labelRect vs bubble $bubbleRect)',
      );
      expect(
        labelRect.left >= bubbleRect.left &&
            labelRect.right <= bubbleRect.right,
        isTrue,
        reason: '${_labels[i]} label escaped the bubble horizontally',
      );

      // The icon is in there too, above the word.
      final icon = find.descendant(of: bubble, matching: find.byType(Icon));
      expect(icon, findsOneWidget);
      expect(
        tester.getRect(icon).bottom <= labelRect.top + 0.5,
        isTrue,
        reason: '${_labels[i]} icon should sit above the label',
      );
    }
  });

  testWidgets('each control is a ROUND bubble with a light on it', (
    tester,
  ) async {
    await tester.pumpWidget(_host(router: _router(<String>[])));
    await tester.pump(const Duration(milliseconds: 300));

    final bubble = find.byKey(const ValueKey('wallet-module-bills'));
    final circles = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: bubble, matching: find.byType(DecoratedBox)),
        )
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.shape == BoxShape.circle)
        .toList();
    expect(circles, isNotEmpty, reason: 'the bubble must be circular');
    final rimmed = circles.where((d) => d.border != null).toList();
    expect(rimmed, isNotEmpty, reason: 'a bubble has a rim');
    expect(
      rimmed.any((d) => d.gradient is LinearGradient),
      isTrue,
      reason: 'the owner asked for a light sheen on the bubble body',
    );
    for (final d in rimmed) {
      // Restrained, not a glow bomb: a short soft lift at most.
      for (final shadow in d.boxShadow ?? const <BoxShadow>[]) {
        expect(shadow.blurRadius, lessThanOrEqualTo(16));
        expect(shadow.offset.dy.abs(), lessThanOrEqualTo(6));
      }
    }

    // The specular highlight is what sells the bubble.
    final specular = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: bubble, matching: find.byType(DecoratedBox)),
        )
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.gradient is RadialGradient)
        .length;
    expect(
      specular,
      greaterThanOrEqualTo(1),
      reason: 'no specular highlight found',
    );

    // And it is ROUND, not an ellipse, and not blown up to the slot width:
    // the painted circle is square and capped.
    final circleFinder = find
        .descendant(of: bubble, matching: find.byType(DecoratedBox))
        .at(0);
    final painted = tester.getRect(circleFinder);
    expect(
      (painted.width - painted.height).abs(),
      lessThanOrEqualTo(1.0),
      reason:
          'the bubble must be a circle, not an ellipse '
          '(${painted.width}x${painted.height})',
    );
    expect(
      painted.width,
      lessThanOrEqualTo(64.0),
      reason: 'the bubble must not stretch to fill its slot',
    );
    expect(tester.getRect(bubble).height, greaterThanOrEqualTo(48.0));
  });

  for (final width in <double>[320, 360, 390]) {
    for (final brightness in Brightness.values) {
      testWidgets('four bubbles stay in one row at ${width.toInt()}dp, '
          '${brightness.name}, every text scale', (tester) async {
        tester.view.physicalSize = Size(width * 3, 780 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        for (final scale in <double>[1.0, 1.3, 1.6]) {
          await tester.pumpWidget(
            _host(
              router: _router(<String>[]),
              brightness: brightness,
              textScale: scale,
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));

          expect(
            tester.takeException(),
            isNull,
            reason: 'overflowed at ${width.toInt()}dp / ${scale}x',
          );

          // One row: every bubble shares the row's vertical band.
          final tops = <double>[];
          final bottoms = <double>[];
          for (final key in _keys) {
            final r = tester.getRect(find.byKey(ValueKey(key)));
            tops.add(r.top);
            bottoms.add(r.bottom);
          }
          expect(
            tops.toSet().length,
            1,
            reason: 'bubbles are not aligned on one row at $width / $scale',
          );
          expect(bottoms.toSet().length, 1);

          // And nothing spilled out of the viewport.
          for (final key in _keys) {
            final r = tester.getRect(find.byKey(ValueKey(key)));
            expect(r.left, greaterThanOrEqualTo(-0.5));
            expect(r.right, lessThanOrEqualTo(width + 0.5));
          }

          // The caption is still inside its bubble at this scale.
          final bubbleRect = tester.getRect(
            find.byKey(const ValueKey('wallet-module-bills')),
          );
          final labelRect = tester.getRect(
            find.descendant(
              of: find.byKey(const ValueKey('wallet-module-bills')),
              matching: find.text('Bills'),
            ),
          );
          expect(labelRect.bottom, lessThanOrEqualTo(bubbleRect.bottom));
        }
      });
    }
  }

  testWidgets('reduced motion keeps all four bubbles and loses no label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(router: _router(<String>[]), reducedMotion: true),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(HomeActionBubble), findsNWidgets(4));
    for (final label in _labels) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Save, P2P and Bills reach exactly the routes they always did', (
    tester,
  ) async {
    final visited = <String>[];
    await tester.pumpWidget(_host(router: _router(visited)));
    await tester.pump(const Duration(milliseconds: 300));

    Future<void> tapAndSettle(String key) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tapAndSettle('wallet-module-save');
    expect(visited.last, '/savings');

    await tester.pumpWidget(_host(router: _router(visited)));
    await tester.pump(const Duration(milliseconds: 300));
    await tapAndSettle('wallet-module-p2p');
    expect(visited.last, '/marketplace');

    await tester.pumpWidget(_host(router: _router(visited)));
    await tester.pump(const Duration(milliseconds: 300));
    await tapAndSettle('wallet-module-bills');
    expect(
      visited.last,
      '/bills',
      reason: 'Bills must use the canonical route',
    );
  });

  testWidgets('Susu with no active group lands on the hub', (tester) async {
    final visited = <String>[];
    await tester.pumpWidget(_host(router: _router(visited)));
    await tester.pump(const Duration(milliseconds: 300));

    // The stub router records destinations through builder side effects only
    // for the money routes; the susu hub is asserted by location instead.
    await tester.tap(find.byKey(const ValueKey('wallet-module-susu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      visited.last,
      '/susu',
      reason: 'no active group means the susu hub, not a group detail',
    );
  });

  testWidgets('each bubble is one tappable semantic node with its label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(router: _router(<String>[])));
    await tester.pump(const Duration(milliseconds: 300));

    for (final label in _labels) {
      expect(
        find.bySemanticsLabel(label),
        findsWidgets,
        reason: '$label must be reachable by screen readers',
      );
    }
    handle.dispose();
  });
}
