// lib/services/notification_action_dispatcher.dart
// =============================================================================
// AZAMAN — NOTIFICATION ACTION DISPATCHER (2026-10-25, review 4.1)
//
// One canonical, PURE resolver from a notification's actionPayload to a
// route (or null). The Home notification overlay and the notification hub
// both consume it so a given payload always opens the same destination
// regardless of which surface the user tapped it from.
//
// It resolves ONLY verified routes the payload's own fields supply —
// trade/dispute/queue ids, known action names, and the legacy flat-key /
// route fallbacks the backend has historically emitted. It never invents
// an id: an OPEN_TRADE without a tradeId resolves to null, and the caller
// must show a truthful no-action fallback rather than navigating
// somewhere the payload never named.
// =============================================================================

/// The dispatch outcome for a notification tap.
enum NotificationActionResolution {
  /// The payload resolves to a canonical route — navigate to [route].
  navigable,

  /// The payload exists but names no destination this app supports.
  unsupportedAction,

  /// The payload has no action at all — a purely informational notice.
  informational,

  /// The payload names an action whose ESTABLISHED behaviour (in
  /// `handleNotificationTap`) is imperative — it needs widget state a
  /// pure route string cannot carry (e.g. OPEN_CHAT pushes
  /// FriendChatScreen with friendship fields). The dispatcher stays
  /// pure: it hands the action back to the caller with [actionName]
  /// and [payload], and the caller forwards both to the established
  /// imperative handler. The dispatcher never invents a stand-in route.
  delegated,
}

class NotificationAction {
  final NotificationActionResolution resolution;
  final String? route;

  /// For [NotificationActionResolution.delegated] only: the original
  /// action name and payload the established imperative handler needs.
  final String? actionName;
  final Map<String, dynamic>? payload;

  const NotificationAction._(this.resolution, this.route,
      [this.actionName, this.payload]);

  const NotificationAction.navigable(String route)
    : this._(NotificationActionResolution.navigable, route);

  const NotificationAction.unsupportedAction()
    : this._(NotificationActionResolution.unsupportedAction, null);

  const NotificationAction.informational()
    : this._(NotificationActionResolution.informational, null);

  const NotificationAction.delegated(
    String actionName,
    Map<String, dynamic>? payload,
  ) : this._(NotificationActionResolution.delegated, null, actionName,
       payload);
}

abstract final class NotificationActionDispatcher {
  /// Resolves [payload] (an `actionPayload` map) to a navigable action.
  ///
  /// Pure: no context, no navigation, no side effects — safe to unit test
  /// exhaustively and safe for both the overlay and the hub to call.
  static NotificationAction resolve(Map<String, dynamic>? payload) {
    if (payload == null) return const NotificationAction.informational();

    final action = payload['action']?.toString();

    switch (action) {
      // ── Trade lifecycle ──────────────────────────────────────────────
      case 'OPEN_TRADE':
      case 'PING_TOPUP':
        final tradeId = payload['tradeId']?.toString();
        if (tradeId != null && tradeId.isNotEmpty) {
          return NotificationAction.navigable('/trade/$tradeId');
        }
        return const NotificationAction.unsupportedAction();

      // ── Disputes ─────────────────────────────────────────────────────
      case 'OPEN_DISPUTE':
        final disputeId = payload['disputeId']?.toString();
        if (disputeId != null && disputeId.isNotEmpty) {
          return NotificationAction.navigable('/dispute/$disputeId');
        }
        return const NotificationAction.unsupportedAction();

      // ── Friends & DMs ────────────────────────────────────────────────
      case 'OPEN_FRIEND_REQUEST':
      case 'OPEN_FRIEND_CHAT':
      case 'OPEN_FRIEND_TRANSFER_REQUEST':
        return const NotificationAction.navigable('/friends');

      // ── Queue / Waiting Room ──────────────────────────────────────────
      case 'OPEN_QUEUE':
        final queueId = payload['queueId']?.toString() ?? '';
        final position = payload['queuePosition']?.toString() ?? '1';
        final adId = payload['adId']?.toString() ?? '';
        return NotificationAction.navigable(
          '/queue?queueId=$queueId&position=$position&adId=$adId',
        );

      // ── Wallet / balance-related ──────────────────────────────────────
      // No dedicated wallet route — the destination is the surface the
      // user is already on (MainWrapper/Home). There is nothing to push.
      case 'OPEN_WALLET':
        return const NotificationAction.informational();

      // ── KYC / account status ──────────────────────────────────────────
      case 'KYC_STATUS':
      case 'ACCOUNT_STATUS':
        return const NotificationAction.navigable('/settings');

      // ── Savings ────────────────────────────────────────────────────────
      case 'VIEW_SAVINGS':
        return const NotificationAction.navigable('/savings');

      // ── Marketplace ───────────────────────────────────────────────────
      case 'OPEN_AD':
      case 'OPEN_MARKETPLACE':
        return const NotificationAction.navigable('/marketplace');

      // ── Susu deep-link actions (restored 2026-10-25, review 4.2) ────────
      // Established behaviour (handleNotificationTap, Phase 4 susu sprint):
      // OPEN_SUSU with a susuId → the susu detail route; without → the
      // susu hub. Never an invented id: the hub IS the honest fallback.
      case 'OPEN_SUSU':
        final susuId = payload['susuId']?.toString();
        return (susuId != null && susuId.isNotEmpty)
            ? NotificationAction.navigable('/susu/$susuId')
            : const NotificationAction.navigable('/susu');

      // OPEN_SUSU_INVITE prefers the LINK-channel token (the public
      // redemption route), then the susuId detail route, then the hub —
      // the exact preference order the established handler uses.
      case 'OPEN_SUSU_INVITE':
        final token = payload['token']?.toString();
        final susuId = payload['susuId']?.toString();
        if (token != null && token.isNotEmpty) {
          return NotificationAction.navigable('/susu/invite/$token');
        }
        if (susuId != null && susuId.isNotEmpty) {
          return NotificationAction.navigable('/susu/$susuId');
        }
        return const NotificationAction.navigable('/susu');

      // OPEN_DEPOSIT_FOR_SUSU pre-fills Add Cash exactly like the
      // established handler: amount + memo 'susu:<id>' trace (Req 12.4).
      case 'OPEN_DEPOSIT_FOR_SUSU':
        final amount = payload['amount']?.toString();
        final susuId = payload['susuId']?.toString();
        final params = <String>[
          if (amount != null && amount.isNotEmpty)
            'amount=${Uri.encodeQueryComponent(amount)}',
          if (susuId != null && susuId.isNotEmpty)
            'memo=${Uri.encodeQueryComponent('susu:$susuId')}',
        ];
        return NotificationAction.navigable(
          params.isEmpty ? '/deposit' : '/deposit?${params.join('&')}',
        );

      // ── Order tracking (restored 4.2) ──────────────────────────────────
      // Established behaviour: only an orderId the payload actually
      // supplies navigates; a missing id is unsupported, never invented.
      case 'OPEN_ORDER':
        final orderId = payload['orderId']?.toString();
        if (orderId == null || orderId.isEmpty) {
          return const NotificationAction.unsupportedAction();
        }
        final orderRef = payload['orderRef']?.toString();
        return NotificationAction.navigable(
          orderRef == null || orderRef.isEmpty
              ? '/orders/$orderId/tracking'
              : '/orders/$orderId/tracking'
                  '?orderRef=${Uri.encodeQueryComponent(orderRef)}',
        );

      // ── KYC proof of residency (restored 4.2) ──────────────────────────
      case 'OPEN_PROOF_OF_RESIDENCY':
        return const NotificationAction.navigable('/proof-of-residency');

      // ── Default payload action (restored 4.2) ─────────────────────────
      // The BE's _ensureDeepLink stamps bare/default payloads with
      // { route: '/', action: 'OPEN_HOME' }; the established destination
      // is the home surface ('/').
      case 'OPEN_HOME':
        return const NotificationAction.navigable('/');

      // ── Chat (restored 4.2, imperative) ────────────────────────────────
      // OPEN_CHAT's established behaviour pushes FriendChatScreen with
      // friendship state (conversationId, friendName, friendId) that a
      // pure route cannot carry — and the hub fallback needs the same
      // logic. The dispatcher delegates: the caller forwards the action
      // to the established imperative handler. It never invents a
      // stand-in route for a chat the payload actually identified.
      case 'OPEN_CHAT':
        return NotificationAction.delegated(action!, payload);
      // ── Fallback: legacy payload shapes ──────────────────────────────
      default:
        // An action name this app does not support is reported as such.
        // The caller must NOT navigate somewhere the payload never
        // named — an unknown action's incidental tradeId is not a
        // navigation instruction, so the unsupported check comes BEFORE
        // the legacy flat-key fallback.
        if (action != null && action.isNotEmpty) {
          return const NotificationAction.unsupportedAction();
        }
        // Legacy: some older notifications used flat tradeId/disputeId
        // keys without an action field.
        final tradeId = payload['tradeId']?.toString();
        if (tradeId != null && tradeId.isNotEmpty) {
          return NotificationAction.navigable('/trade/$tradeId');
        }
        final disputeId = payload['disputeId']?.toString();
        if (disputeId != null && disputeId.isNotEmpty) {
          return NotificationAction.navigable('/dispute/$disputeId');
        }
        // Route field as last resort — but ONLY for routes the app
        // actually registers. The payload is server-ORIGINATED data, yet
        // a route string is arbitrary navigation input: an unrecognised
        // value (a typo, a retired route, a malicious injection
        // upstream) must resolve to unsupportedAction, never to a raw
        // push of whatever string arrived. The allowlist is the set of
        // top-level canonical routes the router actually mounts; it is
        // intentionally closed — new routes join it by name here, in
        // review, not by whoever authored the payload.
        final route = payload['route']?.toString();
        if (route != null && route.isNotEmpty) {
          final allowed = _isKnownTopLevelRoute(route);
          return allowed
              ? NotificationAction.navigable(route)
              : const NotificationAction.unsupportedAction();
        }
        return const NotificationAction.informational();
    }
  }

  /// The closed allowlist of top-level routes the router mounts. These
  /// are exactly the paths `lib/router/` registers at the root — a
  /// payload `route` outside this set never navigates.
  static const Set<String> _knownTopLevelRoutes = {
    '/account', '/azm-auction', '/biz', '/business', '/business-market',
    '/card-transfer', '/chat', '/close-friends', '/convert', '/deposit',
    '/discover', '/dispute', '/friends', '/leaderboard', '/loyalty-cards',
    '/marketplace', '/messages', '/my-orders',
    '/notification-preferences', '/notifications', '/orders',
    '/payment-requests', '/profile', '/proof-of-residency', '/queue',
    '/receive', '/referral', '/request', '/round-up', '/savings',
    '/search', '/send', '/settings', '/spending-insights', '/storefront',
    '/story-analytics', '/story-camera', '/story-create', '/story-editor',
    '/story-highlights', '/susu', '/trade', '/transactions', '/vault',
    '/wallet-pass', '/withdraw', '/worker',
  };

  /// True when [route] is a route the app registers at the top level —
  /// either an exact allowlist match, or `known/...` (a subpath of a
  /// known root, e.g. `/business/BIZ-123`). Query strings are stripped
  /// first. Everything else is unknown and must not navigate.
  static bool _isKnownTopLevelRoute(String route) {
    var path = route;
    final q = path.indexOf('?');
    if (q >= 0) path = path.substring(0, q);
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (_knownTopLevelRoutes.contains(path)) return true;
    final seg = path.split('/');
    if (seg.length > 2 && _knownTopLevelRoutes.contains('/${seg[1]}')) {
      return true;
    }
    return false;
  }
}
