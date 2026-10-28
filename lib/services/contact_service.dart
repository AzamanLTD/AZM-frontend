import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

// =============================================================================
// AZAMAN — CONTACT DISCOVERY (P8)
//
// THE DEFECT THIS REPLACES, AND WHY IT WAS SILENT
//
// The app used to POST `{hashedPhones: sha256(digits)}` to `/contacts/sync`.
// The backend stores `User.phoneHash` as **HMAC-SHA256(E.164, server pepper)**
// (services/identity/phoneHash.js) and `/contacts/sync` matches hash-to-hash
// against exactly that column. A plain SHA-256 of the digits can therefore
// NEVER equal a peppered HMAC — so the endpoint returned 200 with matches: []
// forever. The UI showed "no one from your contacts is on Azaman yet", which
// was a truthful-looking claim produced by a contract that could not match.
//
// THE CONTRACT THAT ACTUALLY WORKS
//
//   POST /api/users/discover   (authenticated, strict rate limit)
//   body  { phones: ["+233201234567", ...] }     ← E.164, hashed server-side
//   200   { success: true, data: { matches: [{azamanId, displayName, avatar}] } }
//
// The server hashes in memory for the duration of the request; nothing is
// persisted. Its projection is deliberately minimal: azamanId, displayName,
// avatar only — no User.id, no email, no balance, no KYC, and crucially no
// echo of which submitted number matched. That is the projection this file
// parses; it must never ask for more.
//
// WHAT NEVER LEAVES THE DEVICE
//
// Numbers only, normalized to E.164. No contact names, no label ("mum",
// "work"), no email fields, no address-book identifiers, and no raw numbers
// are persisted by this service — the normalized list exists only for the
// duration of the call.
// =============================================================================

/// The E.164 assumption used when an address-book entry is a local number.
///
/// Ghana is the launch market, so a bare `0244123456` is read as +233 24 412
/// 3456. This is an explicit, overridable assumption rather than a silent
/// guess: once the signed-in user's `country` is threaded through from the
/// profile, callers should pass their own `defaultDialCode`. Getting this
/// wrong does not corrupt anything (the server refuses to match a number that
/// is not a verified user's), it simply fails to find the person.
const String kDefaultDialCode = '+233';

/// Dial codes of the markets Azaman supports, used to decide whether a bare
/// digit string already carries a country code.
const Set<String> _knownDialCodes = {
  '+233', // Ghana
  '+234', // Nigeria
  '+254', // Kenya
  '+27', // South Africa
  '+225', // Côte d'Ivoire
  '+228', // Togo
  '+1', // US/Canada
  '+44', // UK
};

/// Normalize a raw address-book number to E.164 (`+` then 7..15 digits), or
/// `null` when it cannot be interpreted. Junk is dropped here rather than
/// rejected by the server, because address books are full of `*123#`,
/// extensions and half-dialled numbers.
String? normalizeToE164(
  String raw, {
  String defaultDialCode = kDefaultDialCode,
}) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  // Keep a leading + (an explicit international number), drop everything else
  // that is not a digit: spaces, dashes, dots, parens, extensions.
  final hasPlus = s.startsWith('+');
  var digits = s.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return null;

  // 00-prefixed international form.
  if (!hasPlus && digits.startsWith('00')) {
    digits = digits.substring(2);
    if (digits.isEmpty) return null;
    return _validated('+$digits');
  }

  if (hasPlus) return _validated('+$digits');

  // Already carries a known country code?
  for (final code in _knownDialCodes) {
    final bare = code.substring(1);
    if (digits.startsWith(bare) && digits.length - bare.length >= 7) {
      return _validated('+$digits');
    }
  }

  // Local trunk prefix: 0244123456 -> +233 244123456.
  //
  // A bare digit string is only assumed to be a LOCAL number when the national
  // significant part is plausible (>= 7 digits). Without that floor, `12345`
  // would become the "valid" +23312345 — a short code dressed as a phone
  // number, uploaded to a discovery endpoint. Short codes, extensions and
  // half-dialled numbers are junk and are dropped here.
  final dial = defaultDialCode.startsWith('+')
      ? defaultDialCode.substring(1)
      : defaultDialCode;
  if (digits.startsWith('0')) digits = digits.substring(1);
  if (digits.length < 7) return null;
  return _validated('+$dial$digits');
}

String? _validated(String candidate) =>
    RegExp(r'^\+\d{7,15}$').hasMatch(candidate) ? candidate : null;

/// One matched Azaman member, exactly as the server projects it.
@immutable
class MatchedContact {
  const MatchedContact({
    required this.azamanId,
    required this.displayName,
    this.avatar,
  });

  /// The public handle (`AZM-000000123`). There is no User.id here by design.
  final String azamanId;
  final String displayName;
  final String? avatar;

  factory MatchedContact.fromDiscoverJson(Map<String, dynamic> json) {
    return MatchedContact(
      azamanId: (json['azamanId'] ?? '').toString(),
      // The server falls back to username when displayName is unset, but a
      // blank name is still possible on a half-migrated row: never render
      // an empty tile.
      displayName: (json['displayName'] ?? '').toString().trim().isEmpty
          ? 'Azaman member'
          : json['displayName'].toString(),
      avatar: json['avatar']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MatchedContact &&
      other.azamanId == azamanId &&
      other.displayName == displayName &&
      other.avatar == avatar;

  @override
  int get hashCode => Object.hash(azamanId, displayName, avatar);
}

/// Why a discovery call ended the way it did. A caller must be able to show
/// the difference between "you have not granted contacts", "your address book
/// has no numbers" and "the request failed" — all three used to look like an
/// empty match list.
enum ContactDiscoveryStatus {
  /// The call completed; [ContactDiscoveryResult.matches] may still be empty.
  ok,

  /// The user declined the OS permission (or the platform has no picker).
  permissionDenied,

  /// Nothing usable in the address book after normalization.
  noNumbers,

  /// The request failed (network, auth, server). Not a "no matches" answer.
  failed,
}

@immutable
class ContactDiscoveryResult {
  const ContactDiscoveryResult({
    required this.status,
    this.matches = const <MatchedContact>[],
    this.message,
    this.normalizedCount = 0,
  });

  final ContactDiscoveryStatus status;
  final List<MatchedContact> matches;
  final String? message;

  /// How many numbers were actually submitted (after normalization + dedupe).
  final int normalizedCount;

  bool get isOk => status == ContactDiscoveryStatus.ok;
  bool get hasMatches => matches.isNotEmpty;

  @override
  String toString() =>
      'ContactDiscoveryResult($status, matches: ${matches.length}, '
      'submitted: $normalizedCount)';
}

class ContactService {
  ContactService._({ApiClient? api}) : _api = api ?? apiClient;

  static final ContactService instance = ContactService._();

  /// Test seam: a contact service wired to an [ApiClient] built on an
  /// injected `http.Client`, so the wire body can be asserted exactly.
  @visibleForTesting
  factory ContactService.withClient(ApiClient api) =>
      ContactService._(api: api);

  final ApiClient _api;

  /// The server caps a discovery call at 1000 numbers; batches are sized to
  /// that limit rather than letting a large address book fail the whole call.
  static const int kMaxNumbersPerCall = 1000;

  /// Collect E.164 numbers from the device address book. Permission is asked
  /// HERE, but only after the caller has shown its own explanation: the OS
  /// prompt must never be the first thing a new user sees.
  Future<ContactDiscoveryResult> discoverExistingMembers({
    String defaultDialCode = kDefaultDialCode,
    int maxNumbers = 5000,
  }) async {
    PermissionStatus status;
    try {
      status = await FlutterContacts.permissions.request(PermissionType.read);
    } catch (e) {
      return ContactDiscoveryResult(
        status: ContactDiscoveryStatus.failed,
        message: 'Contacts are not available on this device.',
      );
    }
    if (status != PermissionStatus.granted) {
      return const ContactDiscoveryResult(
        status: ContactDiscoveryStatus.permissionDenied,
      );
    }

    final List<Contact> deviceContacts;
    try {
      // Phone numbers ONLY: names and emails are never read, let alone sent.
      deviceContacts = await FlutterContacts.getAll(
        properties: {ContactProperty.phone},
      );
    } catch (e) {
      return const ContactDiscoveryResult(
        status: ContactDiscoveryStatus.failed,
        message: 'Could not read contacts.',
      );
    }

    final normalized = <String>{};
    for (final c in deviceContacts) {
      for (final p in c.phones) {
        final e164 = normalizeToE164(
          p.number,
          defaultDialCode: defaultDialCode,
        );
        if (e164 != null) normalized.add(e164);
        if (normalized.length >= maxNumbers) break;
      }
      if (normalized.length >= maxNumbers) break;
    }
    if (normalized.isEmpty) {
      return const ContactDiscoveryResult(
        status: ContactDiscoveryStatus.noNumbers,
      );
    }

    // Only the numbers cross the network, in server-sized batches.
    return _discoverNumbers(normalized.toList(growable: false));
  }

  /// The transport half of discovery: batch, post, parse. Split out from
  /// [discoverExistingMembers] so the contract can be tested without an
  /// address book, a permission dialog or a device.
  @visibleForTesting
  Future<ContactDiscoveryResult> _discoverNumbers(List<String> e164) async {
    if (e164.isEmpty) {
      return const ContactDiscoveryResult(
        status: ContactDiscoveryStatus.noNumbers,
      );
    }
    final found = <String, MatchedContact>{};
    try {
      for (var i = 0; i < e164.length; i += kMaxNumbersPerCall) {
        final end = (i + kMaxNumbersPerCall) > e164.length
            ? e164.length
            : i + kMaxNumbersPerCall;
        final res = await _api.post('/users/discover', {
          'phones': e164.sublist(i, end),
        });
        if (res.statusCode != 200) {
          return ContactDiscoveryResult(
            status: ContactDiscoveryStatus.failed,
            message: _messageForStatus(res.statusCode),
            normalizedCount: e164.length,
          );
        }
        final body = jsonDecode(res.body);
        if (body is! Map || body['success'] != true) {
          return ContactDiscoveryResult(
            status: ContactDiscoveryStatus.failed,
            message: 'Contact discovery was refused.',
            normalizedCount: e164.length,
          );
        }
        final rawMatches =
            (body['data'] is Map ? body['data']['matches'] : null) as List? ??
            const [];
        for (final m in rawMatches) {
          if (m is! Map) continue;
          final match = MatchedContact.fromDiscoverJson(
            Map<String, dynamic>.from(m),
          );
          // De-duplicate across batches: the same person may share two
          // numbers that are both in the address book.
          if (match.azamanId.isNotEmpty) found[match.azamanId] = match;
        }
      }
    } on ApiException catch (e) {
      // ApiClient turns every non-2xx into a thrown ApiException, so the
      // status has to be read from the exception, not from a response object.
      // Without this, a 401/429/500 all collapsed into 'could not reach' —
      // three different truths reported as one guess.
      return ContactDiscoveryResult(
        status: ContactDiscoveryStatus.failed,
        message: _messageForStatus(e.statusCode),
        normalizedCount: e164.length,
      );
    } catch (_) {
      return ContactDiscoveryResult(
        status: ContactDiscoveryStatus.failed,
        message: 'Could not reach Azaman. Try again.',
        normalizedCount: e164.length,
      );
    }
    return ContactDiscoveryResult(
      status: ContactDiscoveryStatus.ok,
      matches: found.values.toList(growable: false),
      normalizedCount: e164.length,
    );
  }

  /// Test seam for the network half with explicit input.
  @visibleForTesting
  Future<ContactDiscoveryResult> discoverNumbersForTest(List<String> e164) =>
      _discoverNumbers(e164);

  @visibleForTesting
  static String messageForStatusForTest(int code) => _messageForStatus(code);

  static String _messageForStatus(int code) {
    if (code == 401 || code == 403) return 'Sign in again to find your people.';
    if (code == 429) return 'Too many attempts. Try again in a minute.';
    if (code >= 500) return 'Azaman is having trouble right now.';
    return 'Contact discovery failed.';
  }

  /// Legacy on-device hash. Kept ONLY so nothing else silently re-introduces
  /// a second hashing scheme: it is never sent to `/contacts/sync` any more,
  /// because a plain SHA-256 can never match the server's peppered HMAC.
  @Deprecated(
    'Discovery matches on E.164 via /users/discover; do not send hashes.',
  )
  String hashPhoneForLegacySync(String rawPhone) {
    final normalized = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  Future<List<RecentContact>> getRecent() async {
    try {
      final res = await _api.get('/contacts/recent');
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['recent'] as List? ?? [])
          .map((r) => RecentContact.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<String> getInviteLink() async {
    try {
      final res = await _api.get('/contacts/invite');
      final decoded = jsonDecode(res.body);
      if (decoded is Map) return decoded['link']?.toString() ?? '';
      return '';
    } catch (_) {
      return '';
    }
  }
}

class RecentContact {
  const RecentContact({
    required this.friendshipId,
    required this.userId,
    required this.username,
    required this.updatedAt,
    this.profilePictureUrl,
  });

  final String friendshipId;
  final String userId;
  final String username;
  final String? profilePictureUrl;
  final DateTime updatedAt;

  factory RecentContact.fromJson(Map<String, dynamic> json) => RecentContact(
    friendshipId: json['friendshipId'].toString(),
    userId: json['userId'].toString(),
    username: json['username'].toString(),
    profilePictureUrl: json['profilePictureUrl']?.toString(),
    updatedAt:
        DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
        DateTime.now(),
  );
}

/// Unused import guard: [http] is referenced so the injectable client type in
/// tests stays in this file's public surface documentation.
typedef AzHttpClient = http.Client;
