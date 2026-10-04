// Business tray: story → store continuity (Overhaul 05 §7).
// Renders ONLY when the linked business resolves; tap opens the EXISTING
// business profile route and pauses playback until it returns.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/screens/marketplace/business_profile_screen.dart';
import 'package:azaman/widgets/stories/viewer/story_business_tray.dart';

BusinessProfile _hotel() => BusinessProfile(
      id: 'bp-1',
      bizId: 'BIZ-1',
      businessName: 'Coast Lodge',
      category: 'HOSPITALITY',
      isVerified: true,
      isSuspended: false,
      kybStatus: 'VERIFIED',
      totalEscrows: 0,
      completedEscrows: 0,
      userId: 1,
      totalVolume: 0,
      averageRating: 4.7,
      username: 'coast-lodge',
      products: const [],
    );

Widget _host(BusinessProfile? resolved, {required VoidCallback onPause, required VoidCallback onResume}) =>
    ProviderScope(
      overrides: [
        linkedBusinessProvider('BIZ-1').overrideWith((ref) async {
          if (resolved == null) return null;
          return resolved;
        }),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Stack(children: [
                const SizedBox.expand(),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: StoryBusinessTray(
                    bizId: 'BIZ-1',
                    onPause: onPause,
                    onResume: onResume,
                  ),
                ),
              ]),
            ),
          ),
          GoRoute(
            path: '/business/:bizId',
            builder: (context, state) => Scaffold(
              appBar: AppBar(title: const Text('PROFILE ROUTE')),
            ),
          ),
        ]),
      ),
    );

void main() {
  testWidgets('hidden entirely when the business does not resolve',
      (tester) async {
    await tester.pumpWidget(_host(null, onPause: () {}, onResume: () {}));
    await tester.pump();
    expect(find.byType(StoryBusinessTray), findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(StoryBusinessTray),
          matching: find.byType(Text)),
      findsNothing,
      reason: 'no placeholder chip pretending a store exists',
    );
  });

  testWidgets('renders the business name and the vertical action label',
      (tester) async {
    await tester.pumpWidget(_host(_hotel(), onPause: () {}, onResume: () {}));
    await tester.pump();
    expect(find.text('Coast Lodge'), findsOneWidget);
    // HOSPITALITY label from the existing marketplace catalog.
    expect(find.text('See rooms'), findsOneWidget);
  });

  // REVIEW NOTE (2026-10-04): the former 'tap pauses playback, opens the
  // profile route' test asserted go_router navigation (a 'PROFILE ROUTE'
  // scaffold behind a '/business/:bizId' route). It encoded the DEFECT the
  // review pass found: in production the viewer is an imperative route on
  // top of the router, and context.push opened the profile UNDER it. The
  // production-stack test below ('tap from a viewer pushed imperatively…')
  // supersedes it: same pause/resume contract, honest stack geometry.

  // ── Review pass 2: the production stack is an IMPERATIVE route on top ──
  // go_router owns the root navigator; StoryViewerScreen.open pushes a plain
  // PageRouteBuilder ABOVE it. context.push would add the profile to the
  // go_router stack BELOW the opaque viewer — invisible, and playback stays
  // paused forever. The tray must push imperatively like the viewer itself.

  testWidgets(
      'tap from a viewer pushed imperatively opens the profile ABOVE it',
      (tester) async {
    var pauses = 0;
    var resumes = 0;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => Scaffold(
                  body: StoryBusinessTray(
                    bizId: 'BIZ-1',
                    onPause: () => pauses++,
                    onResume: () => resumes++,
                  ),
                ),
              )),
              child: const Text('OPEN VIEWER'),
            ),
          ),
        ),
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        linkedBusinessProvider('BIZ-1')
            .overrideWith((ref) async => _hotel()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.tap(find.text('OPEN VIEWER'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Coast Lodge'), findsOneWidget);

    await tester.tap(find.text('Coast Lodge'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(BusinessProfileScreen), findsOneWidget,
        reason: 'the profile must land ON TOP of the imperative viewer, '
            'not inside the go_router stack beneath it');
    expect(pauses, 1);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(resumes, 1, reason: 'playback resumes when the profile closes');
  });
}
