// lib/providers/server_social_proof_provider.dart
// =============================================================================
// Server social proof — frontend consumer of AZM-backend PR #372
// ("Backend C", friends/friends-of-friends follow counts).
//
// A single-purpose family: watch one business, get its REAL aggregate
// proof or nothing. Presentation labels are the frontend's choice; the
// API returns only numbers. A follow is NOT a visit — nothing downstream
// may claim visitation.
//
// Honesty rules:
//  * Demo mode has NO backend: the provider resolves to unavailable —
//    the UI renders NO social-proof line. Never fabricated counts.
//  * Any failure (401 anonymous session, 404 wrong id, network) is
//    honest absence — `AsyncValue.error` of [SocialProofUnavailable].
//  * Absence of data is NEVER "0 friends follow this" — a real zero
//    (200 with zeros) and no-data are kept distinct; the UI only ever
//    shows a line when a successful response actually returns it.
// =============================================================================
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/config.dart';
import 'package:azaman/services/server_social_proof_service.dart';

/// Real social proof for one business, keyed by canonical
/// BusinessProfile.id. AutoDispose: profile screens come and go; no
/// stale cache outlives them. When the sheet is opened again the fetch
/// re-runs — the counts must track real follow/unfollow changes anyway.
final serverSocialProofProvider = FutureProvider.autoDispose
    .family<ServerSocialProof, String>((ref, businessProfileId) async {
  if (AppConfig.demoMode) {
    throw SocialProofUnavailable();
  }
  return ServerSocialProofService().fetch(businessProfileId);
});

/// The presentation seam. Returns the one-line, number-only label for
/// the identity block, or null when there is nothing honest to show:
/// loading, error, or zero counts all render NOTHING (a zero-count line
/// adds no signal and reads like a broken row).
String? socialProofLine(ServerSocialProof proof) {
  final friends = proof.friendsFollowingCount;
  final fof = proof.friendsOfFriendsFollowingCount;
  if (friends <= 0) return null; // no direct friends — no line, even
  // if friends-of-friends exist: "friends of friends" alone has no
  // social weight without the direct anchor.
  if (fof > 0) {
    return 'Followed by $friends '
        '${friends == 1 ? 'friend' : 'friends'} '
        '· $fof ${fof == 1 ? 'friend' : 'friends'} of friends';
  }
  return 'Followed by $friends ${friends == 1 ? 'friend' : 'friends'}';
}
