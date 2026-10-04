import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/gateways/room_membership_resolver.dart';

void main() {
  group('AzRoomId', () {
    test('builds namespaced ids', () {
      expect(AzRoomId.friend('f1'), 'friend:f1');
      expect(AzRoomId.group('g1'), 'group:g1');
    });

    test('parses well-formed ids', () {
      expect(AzRoomId.parse('friend:abc'), ('friend', 'abc'));
      expect(AzRoomId.parse('group:uuid:with:colons'),
          ('group', 'uuid:with:colons'));
    });

    test('rejects malformed ids', () {
      expect(AzRoomId.parse(''), isNull);
      expect(AzRoomId.parse('group:'), isNull);
      expect(AzRoomId.parse(':1'), isNull);
      expect(AzRoomId.parse('x:1'), isNull);
      expect(AzRoomId.parse('friend'), isNull);
    });
  });

  group('LookupRoomMembershipResolver', () {
    final resolver = LookupRoomMembershipResolver(
      myUserId: 42,
      hasFriendship: (id) => const {'f-1', 'f-2'}.contains(id),
      groupMemberUserIds: (id) => switch (id) {
            'g-mine' => const [1, 42, 7],
            'g-other' => const [1, 7],
            _ => null,
          },
    );

    test('friend room present → true, absent → false', () {
      expect(resolver.isMemberOf('friend:f-1'), isTrue);
      expect(resolver.isMemberOf('friend:f-9'), isFalse);
    });

    test('group room where I am a member → true', () {
      expect(resolver.isMemberOf('group:g-mine'), isTrue);
    });

    test('group room where I am not a member → false', () {
      expect(resolver.isMemberOf('group:g-other'), isFalse);
    });

    test('unknown / unloaded group → false', () {
      expect(resolver.isMemberOf('group:g-unknown'), isFalse);
    });

    test('malformed ids → false', () {
      for (final bad in ['', 'group:', 'x:1', 'f-1', 'friend']) {
        expect(resolver.isMemberOf(bad), isFalse, reason: bad);
      }
    });

    test('a friendship id never authorises a group room and vice versa', () {
      expect(resolver.isMemberOf('group:f-1'), isFalse);
      expect(resolver.isMemberOf('friend:g-mine'), isFalse);
    });
  });

  group('FixedRoomMembershipResolver', () {
    const fixed = FixedRoomMembershipResolver({'friend:a', 'group:b'});

    test('allows only rooms in its set', () {
      expect(fixed.isMemberOf('friend:a'), isTrue);
      expect(fixed.isMemberOf('group:b'), isTrue);
      expect(fixed.isMemberOf('friend:b'), isFalse);
      expect(fixed.isMemberOf('group:a'), isFalse);
    });

    test('rejects malformed ids even if literally present in the set', () {
      const sloppy = FixedRoomMembershipResolver({'x:1', ''});
      expect(sloppy.isMemberOf('x:1'), isFalse);
      expect(sloppy.isMemberOf(''), isFalse);
    });
  });
}