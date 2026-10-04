// =============================================================================
// AZAMAN — CANONICAL ROUTE REGISTRY  (NEW-A, Step 1)
//
// ONE source of truth for every route name and location the GoRouter table
// serves. `app_router.dart` defines the routes; this file is the vocabulary
// everything else navigates with:
//
//   * `AzRouteNames.*` — the GoRouter route names (used by pushNamed/goNamed).
//   * `AzRoutes.*`     — const locations + typed builders for every
//                        parameterized route, so no call site re-concatenates
//                        a path by hand.
//
// Paths and names here are EXACTLY the ones app_router.dart has always used
// (NEW-A must not silently change deep-link paths to make the API prettier).
// If a path changes, change it here AND in the GoRoute in app_router.dart in
// the same commit — never construct a literal route string anywhere else.
// =============================================================================

/// GoRouter route names, mirrored from the GoRoute table in app_router.dart.
///
/// Keep alphabetically grouped the same way the router table is. A rename is
/// a breaking change for every pushNamed/goNamed call site — grep before
/// renaming.
abstract final class AzRouteNames {
  // Boot & shell
  static const home = 'home';

  // Notifications
  static const notifications = 'notifications';

  // Trade lifecycle
  static const trade = 'trade';
  static const dispute = 'dispute';
  static const queue = 'queue';

  // Settings & account
  static const settings = 'settings';
  static const profileEdit = 'profile-edit';
  static const accountActivity = 'account-activity';
  static const accountDelete = 'account-delete';
  static const transactions = 'transactions';

  // Social
  static const friends = 'friends';
  static const messages = 'messages';
  static const referral = 'referral';
  static const leaderboard = 'leaderboard';
  static const azmAuction = 'azm-auction';

  // Marketplace + savings
  static const marketplace = 'marketplace';
  static const savings = 'savings';
  static const deposit = 'deposit';

  // Susu
  static const susuHub = 'susu-hub';
  static const proofOfResidency = 'proof-of-residency';
  static const susuInvite = 'susu-invite';
  static const susuDetail = 'susu-detail';
  static const susuContract = 'susu-contract';
  static const susuPositionPicker = 'susu-position-picker';
  static const susuCompletion = 'susu-completion';

  // Business marketplace
  static const businessMarketHome = 'business-market-home';
  static const checkinQr = 'checkin-qr';
  static const businessCheckin = 'business-checkin';
  static const transitTrips = 'transit-trips';
  static const businessTransitTrips = 'business-transit-trips';
  static const transitSeatSelection = 'transit-seat-selection';
  static const hotelBooking = 'hotel-booking';
  static const dineInTab = 'dine-in-tab';
  static const businessStories = 'business-stories';
  static const businessMarketOrders = 'business-market-orders';
  static const businessMarketInvoices = 'business-market-invoices';
  static const invoiceDetail = 'invoice-detail';
  static const businessMarketDashboard = 'business-market-dashboard';
  static const businessSearch = 'business-search';
  static const savedBusinesses = 'saved-businesses';
  static const cart = 'marketplace-cart';
  static const businessRegister = 'business-register';
  static const businessNotifications = 'business-notifications';
  static const businessProducts = 'business-products';
  static const businessProfile = 'business-profile';

  // Worker portal
  static const workerHub = 'worker-hub';
  static const workerShifts = 'worker-shifts';
  static const workerPayroll = 'worker-payroll';
  static const workerTeam = 'worker-team';
  static const workerTimeOff = 'worker-time-off';
  static const workerFeedback = 'worker-feedback';
  static const workerEwa = 'worker-ewa';
  static const workerSwaps = 'worker-swaps';

  // Storefront & discovery
  static const storefrontStaking = 'storefront-staking';
  static const storefront = 'storefront';
  static const storefrontDiscovery = 'storefront-discovery';
  static const storefrontOrderHistory = 'storefront-order-history';
  static const universalSearch = 'universal-search';
  static const spendingInsights = 'spending-insights';
  static const roundUpSavings = 'round-up-savings';

  // Stories
  static const storyHighlights = 'story-highlights';
  static const closeFriends = 'close-friends';
  static const storyCamera = 'story-camera';
  static const storyEditor = 'story-editor';
  static const storyAnalytics = 'story-analytics';
  static const storyCreation = 'story-creation';

  // Loyalty & preferences
  static const loyaltyCards = 'loyalty-cards';
  static const notificationPreferences = 'notification-preferences';

  // Chat / wallet / orders / vault
  static const messageSearch = 'message-search';
  static const walletPass = 'wallet-pass';
  static const orderTracking = 'order-tracking';
  static const vaultYield = 'vault-yield';
}

/// Canonical route locations and typed builders.
///
/// Every parameterized route has a builder so call sites never interpolate
/// raw strings (the `/trade/:id` '#' convention lives HERE, once, instead of
/// being re-implemented at every call site).
abstract final class AzRoutes {
  // ── Boot & shell ────────────────────────────────────────────────────────
  static const home = '/';
  static const notifications = '/notifications';

  // ── Trade lifecycle ─────────────────────────────────────────────────────
  /// `/trade/:tradeId` — the route stores the raw id; the screen wants the
  /// '#'-prefixed order ref. Single place that knows the convention.
  static String trade(String tradeId) => '/trade/$tradeId';
  static String dispute(String disputeId) => '/dispute/$disputeId';

  /// `/queue` — the waiting room's queue id, position and ad id travel as
  /// query parameters (this is how the FCM `OPEN_QUEUE` deep link addresses
  /// it, so imperative navigation uses the same shape).
  static String queue({String? queueId, int? position, String? adId}) {
    final params = <String>[
      if (queueId != null) 'queueId=${_encode(queueId)}',
      if (position != null) 'position=$position',
      if (adId != null) 'adId=${_encode(adId)}',
    ];
    return params.isEmpty ? '/queue' : '/queue?${params.join('&')}';
  }

  // ── Settings & account ──────────────────────────────────────────────────
  static const settings = '/settings';
  static const profileEdit = '/profile/edit';
  static const accountActivity = '/account/activity';
  static const accountDelete = '/account/delete';
  static const transactions = '/transactions';

  // ── Social ───────────────────────────────────────────────────────────────
  static const friends = '/friends';
  static const messages = '/messages';
  static const referral = '/referral';
  static const leaderboard = '/leaderboard';
  static const azmAuction = '/azm-auction';

  // ── Marketplace + savings ────────────────────────────────────────────────
  /// The P2P crypto market — the FCM `OPEN_AD` target.
  static const marketplace = '/marketplace';
  static const savings = '/savings';

  /// `/deposit?amount=&memo=` — Susu T-24h shortfall reminders pre-fill the
  /// Mobile Money tab with these two query parameters (Req 12.4).
  static String deposit({String? amount, String? memo}) {
    final params = <String>[
      if (amount != null) 'amount=${_encode(amount)}',
      if (memo != null) 'memo=${_encode(memo)}',
    ];
    return params.isEmpty ? '/deposit' : '/deposit?${params.join('&')}';
  }

  // ── Susu ─────────────────────────────────────────────────────────────────
  static const susuHub = '/susu';
  static const proofOfResidency = '/proof-of-residency';

  /// The **public** invite redemption route — no JWT required.
  static String susuInvite(String token) => '/susu/invite/$token';
  static String susuDetail(String susuId) => '/susu/$susuId';
  static String susuContract(String susuId) => '/susu/$susuId/contract';
  static const susuPositionPicker = '/susu/position-picker';
  static const susuCompletion = '/susu/completion';

  // ── Business marketplace ─────────────────────────────────────────────────
  static const businessMarketHome = '/business-market';
  static const businessMarketDashboard = '/business-market/dashboard';
  static const businessMarketOrders = '/business-market/orders';
  static const businessMarketInvoices = '/business-market/invoices';
  static String businessTransitTrips(String bizId) =>
      '/business-market/$bizId/transit';
  static String hotelBooking(String bizId) =>
      '/business-market/$bizId/hotel-booking';
  static String dineInTab(String tabId) => '/business-market/dine-in/$tabId';
  static String businessStories(String bizId) =>
      '/business-market/$bizId/stories';
  static String invoiceDetail(String invoiceId) =>
      '/business-market/invoices/$invoiceId';
  static const businessSearch = '/business/search';
  static const savedBusinesses = '/biz/saved';
  // Mounted under /biz/ (like saved) so it never collides with `/business/:bizId`.
  static const cart = '/biz/cart';
  static const businessRegister = '/business/register';
  static const businessNotifications = '/business/notifications';
  static String businessProducts(String bizId, {String? name}) =>
      name == null ? '/business/$bizId/products' : '/business/$bizId/products?name=${_encode(name)}';
  static String businessProfile(String bizId) => '/business/$bizId';

  // ── Worker portal ───────────────────────────────────────────────────────
  static const workerHub = '/worker';
  static const workerShifts = '/worker/shifts';
  static const workerPayroll = '/worker/payroll';
  static const workerTeam = '/worker/team';
  static const workerTimeOff = '/worker/time-off';
  static const workerFeedback = '/worker/feedback';
  static const workerEwa = '/worker/ewa';
  static const workerSwaps = '/worker/swaps';

  // ── Storefront & discovery ──────────────────────────────────────────────
  static const storefrontStaking = '/storefront/staking';
  static String storefront(String businessProfileId, {String? name}) => name ==
          null
      ? '/storefront/$businessProfileId'
      : '/storefront/$businessProfileId?name=${_encode(name)}';
  static const storefrontDiscovery = '/discover/storefronts';
  static const storefrontOrderHistory = '/my-orders';
  static const universalSearch = '/search';
  static const spendingInsights = '/spending-insights';
  static const roundUpSavings = '/round-up';

  // ── Stories ──────────────────────────────────────────────────────────────
  static const storyHighlights = '/story-highlights';
  static const closeFriends = '/close-friends';
  static const storyCamera = '/story-camera';
  static const storyEditor = '/story-editor';
  static const storyCreation = '/story-create';
  static String storyAnalytics(String businessId, {String? name}) => name ==
          null
      ? '/story-analytics/$businessId'
      : '/story-analytics/$businessId?name=${_encode(name)}';

  // ── Loyalty & preferences ────────────────────────────────────────────────
  static const loyaltyCards = '/loyalty-cards';
  static const notificationPreferences = '/notification-preferences';

  // ── Chat / wallet / orders / vault ───────────────────────────────────────
  static String messageSearch(String conversationId) =>
      '/chat/$conversationId/search';
  static String walletPass(String passType, String itemId,
          {String? title, String? subtitle}) =>
      '/wallet-pass/$passType/$itemId';
  static String orderTracking(String orderId, {String? orderRef}) => orderRef ==
          null
      ? '/orders/$orderId/tracking'
      : '/orders/$orderId/tracking?orderRef=${_encode(orderRef)}';
  static String vaultYield(String vaultId) => '/vault/$vaultId/yield';

  static String _encode(String value) => Uri.encodeQueryComponent(value);
}
