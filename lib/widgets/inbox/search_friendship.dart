// lib/widgets/inbox/search_friendship.dart
// =============================================================================
// Where you stand with someone in people search.
//
// The backend's /friends/search enriches each result with
// `friendshipStatus` (PENDING | ACCEPTED | REJECTED | BLOCKED | null) and
// `isFriendRequestSender`. The search rows used to read `isFriend` /
// `requestSent`, which the backend never sends, so existing friends were
// offered "Add". The local flag `requestSent` (set right after you send a
// request in this session) still counts.
// =============================================================================

enum SearchFriendship { none, friends, requestSent, requestedYou, unavailable }

SearchFriendship searchFriendshipState(Map<String, dynamic> user) {
  if (user['isFriend'] == true) return SearchFriendship.friends;
  final status = user['friendshipStatus']?.toString().toUpperCase();
  final iSent = user['isFriendRequestSender'] == true;
  switch (status) {
    case 'ACCEPTED':
      return SearchFriendship.friends;
    case 'PENDING':
      return iSent ? SearchFriendship.requestSent : SearchFriendship.requestedYou;
    case 'BLOCKED':
      return SearchFriendship.unavailable;
  }
  if (user['requestSent'] == true) return SearchFriendship.requestSent;
  return SearchFriendship.none;
}
