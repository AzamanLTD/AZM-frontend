// =============================================================================
// AZAMAN — GOROUTER AUTH GUARD
//
// Global flag updated by AuthProvider when auth state changes.
// The GoRouter redirect callback reads this synchronously to gate
// deep-linked routes. Public routes (splash, susu invite) are exempt
// (see the redirect in app_router.dart).
// =============================================================================

/// This is the only way to give the global GoRouter synchronous access
/// to auth state without converting it to a Riverpod provider.
class AuthGuard {
  /// Global auth flag — set by AuthProvider on login/logout.
  static bool isAuthenticated = false;
}
