import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/motion/az_identity_morph.dart';

void main() {
  test('identity tags are namespaced per entity kind', () {
    expect(AzIdentityTag.business('b1'), 'az-identity-biz-b1');
    expect(AzIdentityTag.user(7), 'az-identity-user-7');
    expect(AzIdentityTag.group('g9'), 'az-identity-group-g9');
    expect(AzIdentityTag.story(3), 'az-identity-story-3');
    // A user and a story author with the same numeric id never collide.
    expect(AzIdentityTag.user(3), isNot(AzIdentityTag.story(3)));
  });

  testWidgets('wraps the child in a Hero when travel is allowed',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AzIdentityMorph(
            tag: 'az-identity-biz-x',
            travel: true,
            child: FlutterLogo(),
          ),
        ),
      ),
    );
    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.tag, 'az-identity-biz-x');
    expect(find.byType(FlutterLogo), findsOneWidget);
  });

  testWidgets('skips the Hero under reduced motion (plain cut)',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AzIdentityMorph(
            tag: 'az-identity-biz-x',
            travel: false,
            child: FlutterLogo(),
          ),
        ),
      ),
    );
    expect(find.byType(Hero), findsNothing);
    expect(find.byType(FlutterLogo), findsOneWidget);
  });
}