// People search → profiles: the friendship mapping the search rows use, and
// the public profile a stranger opens on.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/screens/person_profile_screen.dart';
import 'package:azaman/widgets/inbox/search_friendship.dart';

void main() {
  group('searchFriendshipState reads what the backend sends', () {
    test('an accepted friendship is Friends (it used to show Add)', () {
      expect(searchFriendshipState({'id': 1, 'friendshipStatus': 'ACCEPTED'}), SearchFriendship.friends);
    });
    test('a pending request I sent is Request sent', () {
      expect(
        searchFriendshipState({'friendshipStatus': 'PENDING', 'isFriendRequestSender': true}),
        SearchFriendship.requestSent,
      );
    });
    test('a pending request they sent is Requested you', () {
      expect(
        searchFriendshipState({'friendshipStatus': 'PENDING', 'isFriendRequestSender': false}),
        SearchFriendship.requestedYou,
      );
    });
    test('blocked is unavailable; nothing is none', () {
      expect(searchFriendshipState({'friendshipStatus': 'BLOCKED'}), SearchFriendship.unavailable);
      expect(searchFriendshipState({'id': 2}), SearchFriendship.none);
    });
    test('the local flag set right after sending still counts', () {
      expect(searchFriendshipState({'requestSent': true}), SearchFriendship.requestSent);
    });
  });

  group('PublicProfile', () {
    test('parses the backend shape and labels completion either way', () {
      final p = PublicProfile.fromJson({
        'id': 7, 'username': 'esi', 'tradesCompleted': 4, 'completionRate': 0.92,
        'positiveReviews': 3, 'isVerified': true, 'memberSince': '2026-01-10T00:00:00Z',
      });
      expect(p.username, 'esi');
      expect(p.completionLabel, '92%');
      expect(PublicProfile.fromJson({'id': 1, 'username': 'a', 'tradesCompleted': 2, 'completionRate': 75}).completionLabel, '75%');
      expect(PublicProfile.fromJson({'id': 1, 'username': 'a'}).completionLabel, '—');
    });
  });

  Future<void> pumpPerson(WidgetTester tester, {required bool requestSent, VoidCallback? onAdd, PublicProfileLoader? loader}) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: PersonProfileScreen(
          userId: 7,
          username: 'esi',
          requestSent: requestSent,
          onAddFriend: onAdd,
          loader: loader ??
              (id) async => const PublicProfile(id: 7, username: 'esi', tradesCompleted: 4, completionRate: 0.5, isVerified: true),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('a stranger opens on their public profile with Add friend', (tester) async {
    var added = false;
    await pumpPerson(tester, requestSent: false, onAdd: () => added = true);
    expect(find.text('@esi'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('person-add-friend')));
    expect(added, isTrue);
  });

  testWidgets('a pending request reads Request sent and does nothing on tap', (tester) async {
    var added = false;
    await pumpPerson(tester, requestSent: true, onAdd: () => added = true);
    expect(find.text('Request sent'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('person-add-friend')));
    expect(added, isFalse);
  });

  testWidgets('a failed load says so and can retry', (tester) async {
    var calls = 0;
    await pumpPerson(tester, requestSent: false, loader: (id) async {
      calls++;
      throw Exception('nope');
    });
    expect(find.text('Could not load this profile.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(calls, 2);
  });
}
