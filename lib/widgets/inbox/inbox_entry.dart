/// Typed inbox row model (Overhaul 04 §3.5).
///
/// Friends arrive from `friendProvider` as raw `Map`s; [InboxEntry.fromFriend]
/// is the single conversion point. No widget reads `friend['...']`.
library;

import 'package:azaman/providers/group_chat_provider.dart';

enum InboxKind { friend, group }

enum InboxSignal { none, moneyIn, moneyOut, request, susuActive, susuConfiguring }

class InboxEntry {
  final InboxKind kind;

  /// `friendshipId` for friends, `groupId` for groups.
  final String id;
  final String title;
  final String? avatarUrl;
  final String preview;
  final DateTime? lastAt;
  final int unread;

  /// From the chat-actions gateway (07); false until G1 lands.
  final bool pinned;
  final bool muted;
  final InboxSignal signal;

  /// The latest message mentions the current user by `@username`.
  final bool mentioned;

  // Friend rows only.
  final int? friendId;
  final bool isOnline;
  final bool isVerifiedVendor;

  // Group rows only.
  final GroupSummary? group;

  const InboxEntry({
    required this.kind,
    required this.id,
    required this.title,
    this.avatarUrl,
    this.preview = '',
    this.lastAt,
    this.unread = 0,
    this.pinned = false,
    this.muted = false,
    this.signal = InboxSignal.none,
    this.mentioned = false,
    this.friendId,
    this.isOnline = false,
    this.isVerifiedVendor = false,
    this.group,
  });

  bool get hasUnread => unread > 0;

  /// Keys mirror the existing `_buildFriendTile` / `_friendSortTime` reads on
  /// the live `/friends` payload. A missing key defaults — never invents.
  static InboxEntry fromFriend(Map<String, dynamic> friend, {String currentUsername = ''}) {
    final f = friend['friend'] is Map<String, dynamic>
        ? friend['friend'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final latest = friend['latestMessage'] is Map<String, dynamic>
        ? friend['latestMessage'] as Map<String, dynamic>
        : null;

    final title = (f['username'] ?? friend['username'] ?? friend['friendUsername'] ?? 'Unknown').toString();
    final preview = (latest?['content'] ?? friend['lastMessage'] ?? '').toString();
    final rawAt = latest?['createdAt'] ?? friend['lastMessageTime'];
    final lastAt = rawAt is DateTime ? rawAt : DateTime.tryParse(rawAt?.toString() ?? '');

    final unreadRaw = friend['unreadCount'];
    final unread = unreadRaw is int ? unreadRaw : int.tryParse('$unreadRaw') ?? 0;

    final friendIdRaw = f['id'] ?? friend['friendId'] ?? friend['userId'];
    final friendId = friendIdRaw is int ? friendIdRaw : int.tryParse('$friendIdRaw');

    final kind = latest?['kind']?.toString().toUpperCase();
    final isMe = latest?['isMe'] == true;
    final signal = switch (kind) {
      'MONEY' || 'TRANSFER' => isMe ? InboxSignal.moneyOut : InboxSignal.moneyIn,
      'REQUEST' => InboxSignal.request,
      _ => InboxSignal.none,
    };

    return InboxEntry(
      kind: InboxKind.friend,
      id: friend['friendshipId']?.toString() ?? friend['id']?.toString() ?? '',
      title: title,
      avatarUrl: f['profilePictureUrl']?.toString(),
      preview: preview,
      lastAt: lastAt,
      unread: unread,
      signal: signal,
      mentioned: currentUsername.isNotEmpty && preview.contains('@$currentUsername'),
      friendId: friendId,
      isOnline: f['isOnline'] == true,
      isVerifiedVendor: f['isVerifiedVendor'] == true,
    );
  }

  static InboxEntry fromGroup(GroupSummary g) => InboxEntry(
        kind: InboxKind.group,
        id: g.id,
        title: g.name,
        avatarUrl: g.avatarUrl,
        preview: g.description ?? '${g.members.length} members',
        lastAt: g.updatedAt,
        signal: g.isSusuActive
            ? InboxSignal.susuActive
            : (g.isSusuConfiguring ? InboxSignal.susuConfiguring : InboxSignal.none),
        group: g,
      );

  /// Pinned first, then most-recent activity; undated rows sink.
  static int compare(InboxEntry a, InboxEntry b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final at = a.lastAt, bt = b.lastAt;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  }

  /// Relative time as the inbox has always shown it: now / 5m / 3h / 2d / d/m.
  static String relativeTime(DateTime? dt, {DateTime? now}) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final diff = (now ?? DateTime.now()).difference(local);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${local.day}/${local.month}';
  }
}