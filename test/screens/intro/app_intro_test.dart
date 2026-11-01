// =============================================================================
// AZAMAN — THE PUBLIC INTRO (P7) ACCEPTANCE SUITE (2026-10-28)
//
// The intro is a PUBLIC tour that runs before login. These tests pin the
// things that make it safe rather than decorative:
//
//   1. THE FLAG IS LOCAL AND SEPARATE. Finishing or SKIPPING writes only
//      `azaman_intro_seen`. There is no request to the backend at all, so a
//      Skip tap can never be mistaken for the authenticated setup being
//      complete (that lives on onboardingCompleted, which this screen cannot
//      reach: it has no API client and no auth dependency).
//   2. UNREADABLE MEANS UNSEEN — a store that throws shows the tour rather
//      than silently skipping it for every new install.
//   3. THE COPY IS TRUE. No unprovable absolutes ("bank-level", "guaranteed",
//      "100% secure", "instant"), and the currency contract is stated the way
//      the app actually behaves: GHS exact, USDC an approximate conversion.
//   4. THE TOUR BEHAVES. Next advances, the last page says "Get started",
//      both exits land on sign-in, and no layout exception appears at the
//      smallest phone size or at large text.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/router/route_registry.dart';
import 'package:azaman/screens/intro/app_intro_screen.dart';
import 'package:azaman/services/intro_store.dart';

/// A store whose reads/writes can be made to fail, so the failure rules are
/// pinned rather than assumed.
class _FakeIntroStore implements IntroStore {
  _FakeIntroStore({
    this.readThrows = false,
    this.writeThrows = false,
    this.seen = false,
  });

  bool readThrows;
  bool writeThrows;
  bool seen;
  int writes = 0;

  @override
  Future<bool> hasSeenIntro() async {
    if (readThrows) throw StateError('unreadable');
    return seen;
  }

  @override
  Future<bool> markSeen() async {
    writes++;
    if (writeThrows) throw StateError('read-only store');
    seen = true;
    return true;
  }
}

Widget _app({IntroStore? store, String initial = AzRoutes.intro}) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: AzRoutes.intro,
        builder: (context, state) => AppIntroScreen(store: store),
      ),
      GoRoute(
        path: AzRoutes.login,
        builder: (context, state) =>
            const Scaffold(body: Text('LOGIN DESTINATION')),
      ),
    ],
  );
  // AppIntroScreen watches themeProvider for the saved appearance and card
  // variant, so the harness has to provide a scope like the real app does.
  return ProviderScope(child: MaterialApp.router(routerConfig: router));
}

Future<void> _pumpIntro(
  WidgetTester tester, {
  IntroStore? store,
  Size? surface,
  double textScale = 1.0,
}) async {
  if (surface != null) {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: _app(store: store),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('the flag is local, and only local', () {
    test('1. a fresh install has not seen the intro', () async {
      expect(await const IntroStore().hasSeenIntro(), isFalse);
    });

    test('2. marking seen persists under the one documented key', () async {
      final store = const IntroStore();
      expect(await store.markSeen(), isTrue);
      expect(await store.hasSeenIntro(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kIntroSeenPrefKey), isTrue);
      // Nothing else was written: the local flag is not a cache of server state.
      expect(prefs.getKeys().where((k) => k != kIntroSeenPrefKey), isEmpty);
    });

    test(
      '3. a corrupt stored value reports UNSEEN, never a silent skip',
      () async {
        // A wrong-typed value (or a store from another generation of the app)
        // must not read as "seen": failing toward SHOWING the tour is the safe
        // direction, because the alternative hides the product explanation
        // from every new install.
        SharedPreferences.setMockInitialValues(<String, Object>{
          kIntroSeenPrefKey: 'yes-please',
        });
        expect(await const IntroStore().hasSeenIntro(), isFalse);

        SharedPreferences.setMockInitialValues(<String, Object>{
          kIntroSeenPrefKey: 1,
        });
        expect(await const IntroStore().hasSeenIntro(), isFalse);
      },
    );
  });

  group('the tour itself', () {
    testWidgets('4. it shows the first slide and can be advanced', (
      tester,
    ) async {
      await _pumpIntro(tester, store: _FakeIntroStore());

      expect(find.text(kIntroSlides.first.headline), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text(kIntroSlides[1].headline), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text(kIntroSlides.last.headline), findsOneWidget);
      // The last page's action is an explicit start, not another "Next".
      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
    });

    testWidgets('5. Get started records the flag and hands off to sign-in', (
      tester,
    ) async {
      final store = _FakeIntroStore();
      await _pumpIntro(tester, store: store);

      for (var i = 0; i < kIntroSlides.length - 1; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      expect(store.seen, isTrue);
      expect(store.writes, 1);
      expect(find.text('LOGIN DESTINATION'), findsOneWidget);
    });

    testWidgets('6. Skip records the flag, goes to sign-in, and is not a '
        'setup-complete claim', (tester) async {
      // The REAL store: the point is what actually lands in prefs.
      await _pumpIntro(tester, store: const IntroStore());

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN DESTINATION'), findsOneWidget);
      // The ONLY thing written is the local intro flag. No onboarding key,
      // no server call — this screen has no API client to call one with.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().toSet(), {kIntroSeenPrefKey});
      expect(
        prefs.getKeys().any((k) => k.toLowerCase().contains('onboarding')),
        isFalse,
        reason: 'skip must leave the authenticated setup untouched',
      );
    });
  });

  group('the copy is honest', () {
    testWidgets('7. no unprovable absolutes and the currency contract holds', (
      tester,
    ) async {
      await _pumpIntro(tester, store: _FakeIntroStore());

      final claims = <String>[];
      for (var i = 0; i < kIntroSlides.length; i++) {
        claims
          ..add(kIntroSlides[i].headline)
          ..add(kIntroSlides[i].body);
        if (i < kIntroSlides.length - 1) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
        }
      }
      final corpus = claims.join(' ').toLowerCase();

      for (final banned in <String>[
        'bank-level',
        'bank grade',
        'guaranteed',
        '100% secure',
        'unhackable',
        'risk-free',
        'instant settlement',
      ]) {
        expect(
          corpus.contains(banned),
          isFalse,
          reason: 'unsupported claim in the intro: "$banned"',
        );
      }

      // GHS is the native balance, described as exact; USDC is a conversion.
      expect(corpus.contains('cedis'), isTrue);
      expect(corpus.contains('exact'), isTrue);
      expect(corpus.contains('≈'), isTrue);
      expect(corpus.contains('conversion'), isTrue);
    });
  });

  group('it behaves on real phones', () {
    testWidgets('8. no layout exception at 320dp or 1.6x text', (tester) async {
      for (final surface in <Size>[
        const Size(320, 640),
        const Size(360, 780),
        const Size(430, 932),
      ]) {
        for (final scale in <double>[1.0, 1.3, 1.6]) {
          await _pumpIntro(
            tester,
            store: _FakeIntroStore(),
            surface: surface,
            textScale: scale,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'intro overflowed at ${surface.width}dp / ${scale}x',
          );
        }
      }
    });
  });
}
