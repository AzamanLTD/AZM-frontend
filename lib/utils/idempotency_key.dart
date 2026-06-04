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
