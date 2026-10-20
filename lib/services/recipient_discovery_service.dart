// =============================================================================
// AZAMAN — SEND RECIPIENT MODEL + DISCOVERY SERVICE
//
// The unified Send composer resolves WHO gets paid through THIS file only.
// Every resolution goes through a live backend contract — nothing here can
// invent, mask or guess a recipient:
//
//   • Accepted friends   GET /api/friends                 (friendshipId +
//                        username + avatar; the financial key is the
//                        friendshipId, matched to the user's OWN friend
//                        list — the authoritative relationship source)
//   • Username directory GET /api/friends/search?q=       (User.id +
//                        username; cross-matched against the friend list
//                        to recover friendshipId when one exists)
//   • AZM-ID lookup      GET /api/users/lookup/:azamanId  ({azamanId,
//                        displayName, avatar} ONLY — the privacy contract
//                        projects no User.id, so an AZM-ID hit CANNOT be
//                        matched to a friendship; it is honestly reported
//                        as not-send-capable unless it resolves through
//                        the directory too)
//
// The canonical peer-transfer rail (POST /api/friends/transfer/send) is
// FRIENDSHIP-BASED: it accepts `friendshipId` of an ACCEPTED friendship
// only. A recipient without a friendshipId is displayed with an honest
// "not connected" state and the money action stays disabled — no silent
// friendship creation, no unverified identifier on the wire.
//
// PLACEHOLDER GUARD: presentation masks ("AZM-•••", "AZM-—", empty
// strings, avatar initials) are DISPLAY-ONLY and can never be constructed
// as an azamanId here — the constructor rejects anything that is not a
// well-formed live AZM ID. (The old send screen's masked fallback is gone.)
// =============================================================================

import 'dart:convert';

import 'package:azaman/services/api_client.dart';

/// A live AZM ID, exactly as the backend's identity service formats it
/// (`AZM-` + 9 digits, see services/identity/identity.service.js).
final RegExp _azmIdPattern = RegExp(r'^AZM-\d{9}$');

/// Presentation masks that must never become a wire value.
const Set<String> _forbiddenAzmIds = {'AZM-•••', 'AZM-—', 'AZM-…'};

/// How the recipient was resolved. Always a live contract path.
enum SendRecipientSource {
  /// Accepted friend from the user's own friend list (send-capable).
  friend,

  /// Directory hit via /friends/search, matched to an accepted friendship
  /// (send-capable).
  directoryFriend,

  /// Directory hit with NO accepted friendship (not send-capable).
  directoryUser,

  /// AZM-ID lookup hit. The identity service projects no User.id, so this
  /// can never be matched to a friendship — honestly not send-capable.
  azmLookup,
}

/// The audited person-identity QR contract: `azaman://user/{username}`
/// (or a bare `@username`). Reservation check-in QRs, dine-in table QRs
/// and every other payload resolve to null — they are NEVER accepted as
/// a personal payment identity.
String? personalQrUsername(String raw) {
  if (raw.startsWith('azaman://user/')) {
    var username = raw.substring('azaman://user/'.length).trim();
    if (username.startsWith('@')) username = username.substring(1);
    return username.isNotEmpty ? username : null;
  }
  if (raw.startsWith('@')) {
    final username = raw.substring(1).trim();
    return username.isNotEmpty ? username : null;
  }
  return null;
}

class SendRecipient {
  /// Canonical username — the directory's stable handle for a user.
  final String username;

  /// Optional display/full name (from identity lookup or friend profile).
  final String? displayName;

  /// The recipient's public AZM ID. Null when unknown — NEVER a mask:
  /// the constructor rejects anything that is not a well-formed live ID.
  final String? azamanId;

  /// Stable numeric user id when the resolution surface exposed one
  /// (directory search, friend rows). Null for AZM-ID lookups by design.
  final int? userId;

  /// The financial key for the canonical peer rail. Non-null ONLY when the
  /// backend-authorized friendship exists (the user's own friend list is
  /// the source of truth).
  final String? friendshipId;

  final String? avatarUrl;

  final SendRecipientSource source;

  /// Friend seed (chat entry / accepted-contact selection): the
  /// friendship is the backend-authorized financial key.
  SendRecipient.friend({
    required String username,
    required String friendshipId,
    String? avatarUrl,
  }) : this(
          username: username,
          source: SendRecipientSource.friend,
          friendshipId: friendshipId,
          avatarUrl: avatarUrl,
        );

  SendRecipient({
    required this.username,
    required this.source,
    this.displayName,
    this.azamanId,
    this.userId,
    this.friendshipId,
    this.avatarUrl,
  })  : assert(username.trim().isNotEmpty,
            'a financial recipient needs a canonical username — '
            'guest fallbacks and placeholder rows are display-only'),
        assert(
            azamanId == null ||
                (_azmIdPattern.hasMatch(azamanId) &&
                    !_forbiddenAzmIds.contains(azamanId)),
            'azamanId must be a well-formed live AZM ID or null — '
            'presentation masks and placeholders can never enter a '
            'financial recipient');

  /// True only when the canonical peer-transfer rail can serve this
  /// recipient (an accepted friendship exists).
  bool get canReceive {
    final f = friendshipId;
    return f != null && f.isNotEmpty;
  }

  /// The name the UI leads with. Username is the canonical handle; a
  /// display name is extra identity evidence, never a substitute.
  String get name => displayName ?? username;

  SendRecipient copyWith({String? friendshipId, SendRecipientSource? source}) =>
      SendRecipient(
        username: username,
        displayName: displayName,
        azamanId: azamanId,
        userId: userId,
        friendshipId: friendshipId ?? this.friendshipId,
        avatarUrl: avatarUrl,
        source: source ?? this.source,
      );
}

/// AZM-ID lookup outcomes. Every failure is honest and typed — the UI
/// never renders a generic "not found" for a self-lookup or a malformed
/// query.
enum AzmLookupStatus {
  found,
  malformed,
  self,
  notFound,
  network,
}

class AzmLookupOutcome {
  final AzmLookupStatus status;
  final SendRecipient? recipient;
  const AzmLookupOutcome.found(SendRecipient r)
      : status = AzmLookupStatus.found,
        recipient = r;
  const AzmLookupOutcome(this.status) : recipient = null;
}

/// Directory search outcome (username / numeric user id).
class DirectorySearchOutcome {
  final List<SendRecipient> results;
  final bool networkFailed;
  const DirectorySearchOutcome(this.results, {this.networkFailed = false});
}

/// Parses a personal AZAM profile QR payload. The ONLY accepted contract is
/// `azaman://user/{username}` (or the plain `@username` shorthand the
/// profile scanner already accepts) — the audited person-identity QR from
/// qr_profile_popup.dart. Reservation check-in codes, dine-in table codes
/// and any other payload return null: they are NOT a payment identity.
String? parsePersonalQrPayload(String raw) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('azaman://user/')) {
    final username = trimmed.substring('azaman://user/'.length).trim();
    return username.isNotEmpty ? username : null;
  }
  if (trimmed.startsWith('@')) {
    final username = trimmed.substring(1).trim();
    return username.isNotEmpty ? username : null;
  }
  return null;
}

/// Resolves send recipients through the live backend contracts. Injectable
/// (tests pass a mock-client ApiClient); production uses the shared
/// [apiClient].
class RecipientDiscoveryService {
  final ApiClient _api;
  RecipientDiscoveryService({ApiClient? api}) : _api = api ?? apiClient;

  /// Maps the user's accepted-friend rows (GET /api/friends shape:
  /// {friendshipId, friend: {id, username, profilePictureUrl, ...}}) to
  /// send-capable recipients. The friendshipId is the wire's financial key.
  static List<SendRecipient> fromFriendRows(List<Map<String, dynamic>> rows) {
    final out = <SendRecipient>[];
    for (final row in rows) {
      final friendshipId = row['friendshipId']?.toString();
      final friend = row['friend'] is Map<String, dynamic>
          ? row['friend'] as Map<String, dynamic>
          : const <String, dynamic>{};
      final username = friend['username']?.toString();
      if (friendshipId == null ||
          friendshipId.isEmpty ||
          username == null ||
          username.isEmpty) {
        continue; // a row without a canonical identity is never a recipient
      }
      final friendId = friend['id'];
      out.add(SendRecipient(
        username: username,
        displayName: friend['fullName']?.toString(),
        // The friends projection carries no azamanId (backend privacy
        // contract) — null, never a mask.
        azamanId: null,
        userId: friendId is int
            ? friendId
            : int.tryParse(friendId?.toString() ?? ''),
        friendshipId: friendshipId,
        avatarUrl: friend['profilePictureUrl']?.toString(),
        source: SendRecipientSource.friend,
      ));
    }
    return out;
  }

  /// GET /api/users/lookup/:azamanId — the strict identity contract.
  /// Rejects malformed input and self-lookup client-side BEFORE the call,
  /// exactly as the backend does (AZAMAN_ID_INVALID / AZAMAN_ID_SELF),
  /// so the honest error appears instantly with no round-trip.
  Future<AzmLookupOutcome> lookupByAzamanId(
    String raw, {
    String? myAzamanId,
  }) async {
    final azamanId = raw.trim();
    if (!_azmIdPattern.hasMatch(azamanId)) {
      return const AzmLookupOutcome(AzmLookupStatus.malformed);
    }
    if (myAzamanId != null && myAzamanId.trim() == azamanId) {
      return const AzmLookupOutcome(AzmLookupStatus.self);
    }
    try {
      final res =
          await _api.get('/users/lookup/${Uri.encodeComponent(azamanId)}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>?;
        final user = data?['user'] as Map<String, dynamic>?;
        if (user != null &&
            user['azamanId'] != null &&
            _azmIdPattern.hasMatch(user['azamanId'].toString())) {
          final recipient = SendRecipient(
            username: user['username']?.toString() ??
                user['displayName']?.toString() ??
                '', // identity service projects displayName; username may
            // be absent — the sheet still shows a resolvable identity via
            // displayName + AZM ID, never sends on it.
            displayName: user['displayName']?.toString(),
            azamanId: user['azamanId'].toString(),
            avatarUrl: user['avatar']?.toString(),
            source: SendRecipientSource.azmLookup,
          );
          if (recipient.username.isEmpty) {
            return const AzmLookupOutcome(AzmLookupStatus.notFound);
          }
          return AzmLookupOutcome.found(recipient);
        }
        return const AzmLookupOutcome(AzmLookupStatus.notFound);
      }
      return const AzmLookupOutcome(AzmLookupStatus.network);
    } on ApiException catch (e) {
      // ApiClient throws ApiException for every non-2xx — classify via the
      // backend's typed codes (identity service: AZAMAN_ID_SELF /
      // USER_NOT_FOUND / AZAMAN_ID_INVALID).
      if (e.statusCode == 400 || e.statusCode == 404) {
        if (e.code == 'AZAMAN_ID_SELF') {
          return const AzmLookupOutcome(AzmLookupStatus.self);
        }
        return const AzmLookupOutcome(AzmLookupStatus.notFound);
      }
      return const AzmLookupOutcome(AzmLookupStatus.network);
    } catch (_) {
      return const AzmLookupOutcome(AzmLookupStatus.network);
    }
  }

  /// GET /api/friends/search?q= — the username / numeric-id directory.
  /// Results carry User.id, so each hit is cross-matched against the
  /// user's own accepted-friend rows to recover the friendshipId when a
  /// friendship exists. Unmatched hits are honestly not send-capable.
  Future<DirectorySearchOutcome> searchDirectory(
    String query, {
    List<Map<String, dynamic>> friendRows = const [],
  }) async {
    final q = query.trim();
    if (q.length < 2) {
      return const DirectorySearchOutcome([]);
    }
    final friendshipsByUserId = <int, String>{};
    for (final r in fromFriendRows(friendRows)) {
      if (r.userId != null && r.friendshipId != null) {
        friendshipsByUserId[r.userId!] = r.friendshipId!;
      }
    }
    try {
      // Query text is USER INPUT — it is always encoded as a component,
      // never interpolated raw into the path or query.
      final res = await _api
          .get('/friends/search?q=${Uri.encodeQueryComponent(q)}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>?;
        final users = (data?['users'] as List?) ?? const [];
        final results = <SendRecipient>[];
        for (final u in users) {
          if (u is! Map<String, dynamic>) continue;
          final username = u['username']?.toString();
          final id = u['id'] is int
              ? u['id'] as int
              : int.tryParse(u['id']?.toString() ?? '');
          if (username == null ||
              username.isEmpty ||
              id == null) {
            continue; // no canonical identity — not a selectable recipient
          }
          final friendshipId = friendshipsByUserId[id];
          results.add(SendRecipient(
            username: username,
            userId: id,
            friendshipId: friendshipId,
            avatarUrl: u['profilePictureUrl']?.toString(),
            source: friendshipId != null
                ? SendRecipientSource.directoryFriend
                : SendRecipientSource.directoryUser,
          ));
        }
        return DirectorySearchOutcome(results);
      }
      return const DirectorySearchOutcome([], networkFailed: true);
    } catch (_) {
      return const DirectorySearchOutcome([], networkFailed: true);
    }
  }
}
