// Business tray: story → store continuity (Overhaul 05 §7).
// Renders ONLY when the linked business resolves; tap opens the EXISTING
// business profile route and pauses playback until it returns.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/business_models.dart';
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

  testWidgets('tap pauses playback, opens the profile route, resumes on return',
      (tester) async {
    var pauses = 0;
    var resumes = 0;
    await tester.pumpWidget(
        _host(_hotel(), onPause: () => pauses++, onResume: () => resumes++));
    await tester.pump();
    await tester.tap(find.text('Coast Lodge'));
    await tester.pump();
    expect(pauses, 1, reason: 'playback pauses before the route opens');
    await tester.pumpAndSettle();
    expect(find.text('PROFILE ROUTE'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(resumes, 1, reason: 'resumes whatever the route outcome was');
    expect(pauses, 1);
  });
}
