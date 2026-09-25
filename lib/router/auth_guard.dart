// =============================================================================
// AZAMAN — GOROUTER AUTH GUARD
//
// Global flag updated by AuthProvider when auth state changes.
// The GoRouter redirect callback reads this synchronously to gate
// deep-linked routes. Public routes (splash, susu invite) are exempt.
// =============================================================================

/// Global auth flag — set by AuthProvider on login/logout.
/// This is the only way to give the global GoRouter synchronous access
/// to auth state without converting it to a Riverpod provider.
class AuthGuard {
  static bool _isAuthenticated = false;
  static bool get isAuthenticated => _isAuthenticated;
  static set isAuthenticated(bool v) => _isAuthenticated = v;
}

/// Routes that don't require authentication (splash, login, public invite).
const _publicRoutes = <String>{
  '/',
  '/susu/invite',
};
