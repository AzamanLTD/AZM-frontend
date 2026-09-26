// =============================================================================
// IDEMPOTENCY KEY GENERATOR — Phase H12 (2026-05-27)
//
// Generates RFC 4122 v4-style UUIDs using `Random.secure()` for use as
// `clientRequestId` on POST endpoints that move money. The BE uses the
// key to derive a stable `TransactionHistory.txHash` so a network retry
// of the same logical request hits the @unique constraint and rolls
// back instead of double-charging the user.
//
// Used by:
//   • FriendService.sendFunds / requestFunds (peer transfers)
//   • savings_goal_sheet._deposit (Phase H12)
//   • Any future financial POST that needs retry-safe idempotency
//
// Avoids pulling in the `uuid` package for one helper. Random.secure()
// uses the platform CSPRNG (`SecureRandom.getInstanceStrong()` on
// Android, /dev/urandom on iOS), so collisions across realistic
// retry windows are negligible.
// =============================================================================

import 'dart:math' as math;

class IdempotencyKey {
  IdempotencyKey._();

  static final math.Random _rand = math.Random.secure();

  /// Returns a fresh RFC 4122 v4-style UUID, e.g.
  /// `550e8400-e29b-41d4-a716-446655440000`.
  static String generate() {
    final bytes = List<int>.generate(16, (_) => _rand.nextInt(256));
    // Set version (4) and variant bits per RFC 4122.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String h(int b) => b.toRadixString(16).padLeft(2, '0');
    final s = bytes.map(h).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }
}

/// One Idempotency-Key per LOGICAL financial action — not per button press.
///
/// The backend r42 authority treats the key as the identity of a whole
/// financial operation. The failure mode this class exists to close:
///
///   1. user taps submit → key K generated → request sent;
///   2. server commits the reservation, the HTTP response is lost
///      (timeout / connection drop);
///   3. user taps submit AGAIN for the same action;
///   4. a fresh generate() inside the submit method mints key K' —
///      a brand-new operation → the money moves TWICE.
///
/// Correct lifecycle, enforced by construction:
///   - [arm] mints once per logical action and returns the SAME key for
///     every retry of that action (token-refresh retries, user-visible
///     retries after a lost response);
///   - [retire] ends the action: the next [arm] mints a fresh key. Retire
///     on a definitive business outcome the user can correct (a 4xx the
///     server actually answered — insufficient funds, validation, ...) and
///     when a genuinely new action begins;
///   - do NOT retire on network errors/timeouts or on 409 replay conflicts
///     (in-flight/committed claims) — retrying those with the same key is
///     exactly the protection the backend provides.
class LogicalActionKey {
  String? _key;

  bool get isArmed => _key != null;

  /// The key for the current logical action; arms on first use.
  String arm() => _key ??= IdempotencyKey.generate();

  /// Ends the logical action — the next [arm] mints a fresh key.
  void retire() => _key = null;
}

/// Per-target variant of [LogicalActionKey]: one key per (action, target)
/// pair. For logical actions that take an argument — accept a contract for
/// susuId X, submit a vouch for vouchRecordId Y — retries of the SAME
/// target must reuse the SAME key (a lost response may mean the server
/// committed the stake), while a different target is a different action
/// and gets its own key. Registry entries are tiny; the holder's lifetime
/// (a Riverpod Provider or a screen State) defines the retry horizon.
class KeyedActionKeys {
  final Map<String, LogicalActionKey> _keys = {};

  LogicalActionKey of(String target) =>
      _keys.putIfAbsent(target, LogicalActionKey.new);
}
