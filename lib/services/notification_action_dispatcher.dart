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
}

class NotificationAction {
  final NotificationActionResolution resolution;
  final String? route;

  const NotificationAction._(this.resolution, this.route);

  const NotificationAction.navigable(String route)
    : this._(NotificationActionResolution.navigable, route);

  const NotificationAction.unsupportedAction()
    : this._(NotificationActionResolution.unsupportedAction, null);

  const NotificationAction.informational()
    : this._(NotificationActionResolution.informational, null);
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
        // Route field as last resort.
        final route = payload['route']?.toString();
        if (route != null && route.isNotEmpty) {
          return NotificationAction.navigable(route);
        }
        return const NotificationAction.informational();
    }
  }
}
