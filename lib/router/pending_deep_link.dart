// lib/router/pending_deep_link.dart
// =============================================================================
// A link that arrived before the user was signed in.
//
// azaman.me links (a business, a storefront, a Susu invite, a referral) can
// open the app while nobody is signed in. The router sends the user to the
// splash/sign-in first; without this, the link was simply lost. The router
// holds the link here, and the app shell opens it once the user lands on it
// (every sign-in path — splash, password, phone, SSO — ends on the shell).
//
// A referral link (/invite/<code>) has no page of its own: its code is held
// for the sign-up screen's referral field.
// =============================================================================

/// The web domain the app's links live on (owner: azaman.me, 28 Nov 2026).
/// Every shared link is built from it; the Android intent filters and the
/// iOS associated domains point at the same host.
const String kAzamanLinkHost = 'azaman.me';
const String kAzamanLinkBase = 'https://$kAzamanLinkHost';

class PendingDeepLink {
  PendingDeepLink._();

  static String? _location;
  static String? _referralCode;

  /// The paths a shared link can open.
  static const deepLinkablePrefixes = <String>[
    '/business/',
    '/storefront/',
    '/susu/invite/',
    '/invite/',
  ];

  static bool isDeepLinkable(String path) =>
      deepLinkablePrefixes.any(path.startsWith);

  /// Hold a link to open after sign-in. A referral link keeps only its code.
  static void hold(Uri uri) {
    final path = uri.path;
    if (path.startsWith('/invite/')) {
      final code = path.substring('/invite/'.length).split('/').first.trim();
      if (code.isNotEmpty) _referralCode = code;
      return;
    }
    if (isDeepLinkable(path)) {
      _location = uri.hasQuery ? '$path?${uri.query}' : path;
    }
  }

  /// The held link, once (the shell opens it).
  static String? take() {
    final l = _location;
    _location = null;
    return l;
  }

  /// The referral code from an /invite/ link, if one arrived (not cleared:
  /// the sign-up screen may be shown more than once).
  static String? get referralCode => _referralCode;

  static void clearForTest() {
    _location = null;
    _referralCode = null;
  }
}
