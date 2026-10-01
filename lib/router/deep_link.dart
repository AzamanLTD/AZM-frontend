// =============================================================================
// AZAMAN — azaman:// DEEP-LINK GRAMMAR  (NEW-A, Step 5)
//
// The product's declared deep-link scheme (AndroidManifest.xml intent
// filters) is:
//
//     azaman://<app-path>[?query]
//
// The URI directly carries the in-app path — there is no semantic host:
//
//     azaman://susu/invite/abc123        ≡  /susu/invite/abc123
//     azaman://trade/t-99?src=share      ≡  /trade/t-99?src=share
//
// NOTE on Dart URI parsing: for `azaman://susu/invite/abc123` the segment
// `susu` parses as the URI *host* and `/invite/abc123` as the *path*. The
// grammar therefore normalizes by joining host + path — never use
// `uri.path` alone. A bare `azaman://` (or `azaman://?x=1`) lands on `/`,
// matching the app's `initialLocation`.
//
// The existing web/https path structure is untouched: plain paths resolve
// exactly as before; only azaman:// URIs are rewritten (in the router's
// redirect, see app_router.dart) before route resolution, so a deep link
// resolves route identity, path parameters and query parameters through
// the exact same table a warm push uses.
// =============================================================================

/// The product's one and only deep-link scheme.
const String kAzamanDeepLinkScheme = 'azaman';

/// Normalizes a raw URI into a GoRouter location.
///
/// Returns `null` when [uri] is not an `azaman://` link — non-deep-link
/// input is never silently mangled.
String? azamanDeepLinkToLocation(Uri uri) {
  if (uri.scheme != kAzamanDeepLinkScheme) return null;

  // Join the parsed "host" back onto the path: azaman://susu/invite/x
  // parses as host "susu" + path "/invite/x".
  final hostPart = uri.host.isEmpty ? '' : uri.host;
  var path = '$hostPart${uri.path}';
  if (path.isEmpty || path == '/') {
    return uri.query.isEmpty ? '/' : '/?${uri.query}';
  }
  if (!path.startsWith('/')) path = '/$path';
  return uri.query.isEmpty ? path : '$path?${uri.query}';
}
