// =============================================================================
// AZAMAN — GATEWAYS: ROOM MEMBERSHIP RESOLVER
//
// Client-side authorisation seam for room-scoped realtime features (companion
// reactions, Susu social view, group events). Unknown room → false, always.
// A literal `=> true` must never exist, not even in demo code.
//
// Room ids are namespaced so a friendship id can never collide with a group id:
//   `friend:<friendshipId>` | `group:<groupId>`
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/group_chat_provider.dart';

/// Builds and parses namespaced room ids.
abstract final class AzRoomId {
  static const friendPrefix = 'friend';
  static const groupPrefix = 'group';

  static String friend(String friendshipId) => '$friendPrefix:$friendshipId';
  static String group(String groupId) => '$groupPrefix:$groupId';

  /// Returns `(kind, id)` or null when malformed (`''`, `'group:'`, `'x:1'`).
  static (String kind, String id)? parse(String roomId) {
    final sep = roomId.indexOf(':');
    if (sep <= 0 || sep == roomId.length - 1) return null;
    final kind = roomId.substring(0, sep);
    final id = roomId.substring(sep + 1);
    if (kind != friendPrefix && kind != groupPrefix) return null;
    return (kind, id);
  }
}

abstract interface class RoomMembershipResolver {
  /// Synchronous; reads already-loaded membership state. Unknown room → false.
  bool isMemberOf(String roomId);
}

/// Pure resolver over two lookups. The production and test adapters below are
/// thin glue around this so the decision logic has exactly one home.
class LookupRoomMembershipResolver implements RoomMembershipResolver {
  const LookupRoomMembershipResolver({
    required this.hasFriendship,
    required this.groupMemberUserIds,
    required this.myUserId,
  });

  /// True when a friendship with this id is in the loaded friend list.
  final bool Function(String friendshipId) hasFriendship;

  /// User ids of the (non-removed) members of the group, or null when the
  /// group is unknown / not loaded.
  final Iterable<int>? Function(String groupId) groupMemberUserIds;

  final int myUserId;

  @override
  bool isMemberOf(String roomId) {
    final parsed = AzRoomId.parse(roomId);
    if (parsed == null) return false;
    final (kind, id) = parsed;
    switch (kind) {
      case AzRoomId.friendPrefix:
        return hasFriendship(id);
      case AzRoomId.groupPrefix:
        final members = groupMemberUserIds(id);
        if (members == null) return false;
        return members.contains(myUserId);
      default:
        return false;
    }
  }
}

/// Production adapter: reads the EXISTING `friendProvider` (friend maps carry
/// `friendshipId`, with legacy `id` fallback — same rule as
/// `friends_hub_screen.dart`) and `groupListProvider` (`GroupSummary.members`).
class ProviderRoomMembershipResolver implements RoomMembershipResolver {
  ProviderRoomMembershipResolver(this.ref, {required this.myUserId});

  final Ref ref;
  final int myUserId;

  late final LookupRoomMembershipResolver _core = LookupRoomMembershipResolver(
    myUserId: myUserId,
    hasFriendship: (id) => ref.read(friendProvider).friends.any(
          (f) => (f['friendshipId'] ?? f['id'])?.toString() == id,
        ),
    groupMemberUserIds: (id) {
      final groups = ref.read(groupListProvider).valueOrNull;
      if (groups == null) return null;
      for (final g in groups) {
        if (g.id == id) {
          return g.members.where((m) => m.removedAt == null).map((m) => m.userId);
        }
      }
      return null;
    },
  );

  @override
  bool isMemberOf(String roomId) => _core.isMemberOf(roomId);
}

/// Demo / test adapter: an explicit allow-list, never "everything".
class FixedRoomMembershipResolver implements RoomMembershipResolver {
  const FixedRoomMembershipResolver(this.rooms);
  final Set<String> rooms;

  @override
  bool isMemberOf(String roomId) =>
      AzRoomId.parse(roomId) != null && rooms.contains(roomId);
}