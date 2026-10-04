// Details sheet (Overhaul 05 §6.3): everything capability-gated. With the
// REAL gateway the shell never opens it (viewers/react have no endpoint
// today); a fake gateway proves the sheet only ever shows what the backend
// can actually honor.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/gateways/az_gateway_result.dart';
import 'package:azaman/experience/gateways/story_gateway.dart';
import 'package:azaman/models/story_model.dart';
import 'package:azaman/widgets/stories/viewer/story_details_sheet.dart';

class _FakeGateway implements StoryGateway {
  _FakeGateway(this.caps, {this.reactResult});

  @override
  final Set<StoryCapability> caps;

  final AzGatewayResult<void>? reactResult;
  final List<String> reactedWith = [];

  @override
  Set<StoryCapability> get capabilities => caps;

  @override
  Future<void> markViewed(String storyId) async {}

  @override
  Future<AzGatewayResult<void>> reply(String storyId, String message) async =>
      const AzUnsupported('reply');

  @override
  Future<AzGatewayResult<void>> boost(String storyId, int amount) async =>
      const AzUnsupported('boost');

  @override
  Future<AzGatewayResult<void>> react(String storyId, String emoji) async {
    reactedWith.add(emoji);
    return reactResult ?? const AzUnsupported('react');
  }

  @override
  Future<AzGatewayResult<void>> shareLink(String storyId) async =>
      const AzUnsupported('share');
}

StoryItem _story() => StoryItem(
      id: 's1',
      mediaUrl: 'https://cdn.example.com/s1.jpg',
      mediaType: 'IMAGE',
      durationSeconds: 5,
      boosted: false,
      seen: false,
      createdAt: DateTime(2026, 10, 1),
    );

Widget _host(StoryGateway gateway) => ProviderScope(
      overrides: [storyGatewayProvider.overrideWithValue(gateway)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                // The sheet lives on a pushed route so a server-confirmed
                // reaction can actually pop it.
                builder: (_) => Scaffold(
                  body: StoryDetailsSheet(
                    story: _story(),
                    authorId: 7,
                    currentUserId: 99,
                  ),
                ),
              )),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('real gateway caps → the honest empty state, no dead rows',
      (tester) async {
    // Exactly what HttpStoryGateway advertises today.
    final gateway = _FakeGateway({StoryCapability.view, StoryCapability.boost});
    await tester.pumpWidget(_host(gateway));
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.textContaining("aren't available"), findsOneWidget);
    expect(find.text('Viewers'), findsNothing);
    expect(find.text('Send a reaction'), findsNothing);
    expect(gateway.reactedWith, isEmpty);
  });

  testWidgets('own story with viewers cap → viewers boundary, no reactions',
      (tester) async {
    final gateway = _FakeGateway({StoryCapability.view, StoryCapability.viewers});
    await tester.pumpWidget(ProviderScope(
      overrides: [storyGatewayProvider.overrideWithValue(gateway)],
      child: MaterialApp(
        home: Scaffold(
          body: StoryDetailsSheet(
            story: _story(),
            authorId: 99, // same as currentUserId
            currentUserId: 99,
          ),
        ),
      ),
    ));
    expect(find.text('Viewers'), findsOneWidget);
    expect(find.text('Send a reaction'), findsNothing);
  });

  testWidgets('reaction send: unsupported result surfaces, sheet stays open',
      (tester) async {
    final gateway = _FakeGateway({StoryCapability.view, StoryCapability.react},
        reactResult: const AzUnsupported(
            'POST /api/stories/:id/react — no endpoint exists yet'));
    await tester.pumpWidget(_host(gateway));
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.text('Send a reaction'), findsOneWidget);

    await tester.tap(find.text('❤️'));
    await tester.pump();
    // The reason from the gateway, not a fabricated success; sheet stays up.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('no endpoint exists yet'), findsOneWidget);
    expect(find.text('Send a reaction'), findsOneWidget);
    expect(find.text('OPEN'), findsNothing);
  });

  testWidgets('reaction send: server-confirmed result pops the sheet',
      (tester) async {
    final gateway = _FakeGateway({StoryCapability.view, StoryCapability.react},
        reactResult: const AzOk<void>(null));
    await tester.pumpWidget(_host(gateway));
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.text('Send a reaction'), findsOneWidget);

    await tester.tap(find.text('🔥'));
    await tester.pump();
    expect(gateway.reactedWith, ['🔥']);
    await tester.pumpAndSettle();
    expect(find.text('Send a reaction'), findsNothing,
        reason: 'only a server-confirmed reaction closes the sheet');
  });
}
