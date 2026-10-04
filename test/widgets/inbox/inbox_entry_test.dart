import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/widgets/inbox/inbox_entry.dart';

GroupSummary _group({String? susuStatus, String? description}) => GroupSummary(
      id: 'g1',
      name: 'Market Mamas',
      description: description,
      status: 'ACTIVE',
      susuGroupId: susuStatus == null ? null : 's1',
      susuStatus: susuStatus,
      members: [
        GroupMember(id: 'm1', userId: 1, username: 'ama', role: 'ADMIN', joinedAt: DateTime(2026)),
        GroupMember(id: 'm2', userId: 2, username: 'kofi', role: 'MEMBER', joinedAt: DateTime(2026)),
      ],
      updatedAt: DateTime(2026, 10, 1),
    );

void main() {
  group('fromFriend', () {
    test('reads the live /friends keys', () {
      final e = InboxEntry.fromFriend({
        'friendshipId': 'f-9',
        'unreadCount': '3',
        'friend': {
          'id': 42,
          'username': 'kofi',
          'profilePictureUrl': 'https://x/p.png',
          'isOnline': true,
          'isVerifiedVendor': true,
        },
        'latestMessage': {
          'content': 'hey @ama',
          'createdAt': '2026-10-03T10:00:00Z',
          'kind': 'MONEY',
          'isMe': false,
        },
      }, currentUsername: 'ama');
      expect(e.kind, InboxKind.friend);
      expect(e.id, 'f-9');
      expect(e.title, 'kofi');
      expect(e.friendId, 42);
      expect(e.unread, 3);
      expect(e.avatarUrl, 'https://x/p.png');
      expect(e.isOnline, isTrue);
      expect(e.isVerifiedVendor, isTrue);
      expect(e.preview, 'hey @ama');
      expect(e.mentioned, isTrue);
      expect(e.signal, InboxSignal.moneyIn);
      expect(e.lastAt, DateTime.utc(2026, 10, 3, 10));
    });

    test('money sent by me is moneyOut; REQUEST maps to request', () {
      expect(
        InboxEntry.fromFriend({'latestMessage': {'kind': 'TRANSFER', 'isMe': true}}).signal,
        InboxSignal.moneyOut,
      );
      expect(InboxEntry.fromFriend({'latestMessage': {'kind': 'REQUEST'}}).signal, InboxSignal.request);
    });

    test('missing keys default — never invent', () {
      final e = InboxEntry.fromFriend({'id': 'legacy', 'lastMessage': 'yo', 'lastMessageTime': 'not-a-date'});
      expect(e.id, 'legacy');
      expect(e.title, 'Unknown');
      expect(e.preview, 'yo');
      expect(e.unread, 0);
      expect(e.friendId, isNull);
      expect(e.lastAt, isNull);
      expect(e.signal, InboxSignal.none);
      expect(e.mentioned, isFalse);
      expect(e.pinned, isFalse);
      expect(e.muted, isFalse);
    });
  });

  group('fromGroup', () {
    test('Susu status drives the signal; preview falls back to member count', () {
      expect(InboxEntry.fromGroup(_group(susuStatus: 'ACTIVE')).signal, InboxSignal.susuActive);
      expect(InboxEntry.fromGroup(_group(susuStatus: 'CONFIGURING')).signal, InboxSignal.susuConfiguring);
      final plain = InboxEntry.fromGroup(_group());
      expect(plain.signal, InboxSignal.none);
      expect(plain.preview, '2 members');
      expect(InboxEntry.fromGroup(_group(description: 'Weekly savings')).preview, 'Weekly savings');
      expect(plain.kind, InboxKind.group);
      expect(plain.group, isNotNull);
    });
  });

  test('compare: pinned first, then recency, undated last', () {
    final a = InboxEntry(kind: InboxKind.friend, id: 'a', title: 'a', lastAt: DateTime(2026, 1, 1));
    final b = InboxEntry(kind: InboxKind.friend, id: 'b', title: 'b', lastAt: DateTime(2026, 1, 5));
    const c = InboxEntry(kind: InboxKind.friend, id: 'c', title: 'c');
    final d = InboxEntry(kind: InboxKind.group, id: 'd', title: 'd', lastAt: DateTime(2025), pinned: true);
    final sorted = [a, b, c, d]..sort(InboxEntry.compare);
    expect(sorted.map((e) => e.id), ['d', 'b', 'a', 'c']);
  });

  test('relativeTime keeps the inbox format', () {
    final now = DateTime(2026, 10, 10, 12);
    expect(InboxEntry.relativeTime(null), '');
    expect(InboxEntry.relativeTime(now.subtract(const Duration(seconds: 20)), now: now), 'now');
    expect(InboxEntry.relativeTime(now.subtract(const Duration(minutes: 5)), now: now), '5m');
    expect(InboxEntry.relativeTime(now.subtract(const Duration(hours: 3)), now: now), '3h');
    expect(InboxEntry.relativeTime(now.subtract(const Duration(days: 2)), now: now), '2d');
    expect(InboxEntry.relativeTime(DateTime(2026, 9, 1), now: now), '1/9');
  });
}