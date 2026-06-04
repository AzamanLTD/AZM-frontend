# Azaman Frontend — Full Audit (May 2026)

> Read-only audit. No code has been changed. This is the frontend
> companion to `AUDIT.md` in the backend repo. Read this file end-to-end
> to understand what is built, what is not wired up, what is broken on
> mobile, and the proposed order of fixes.
>
> Same priority scale as the backend audit:
>
> - **P0 — Broken / unsafe.** App-level functionality is unreachable or causes data loss / wrong UI. Must fix before "premium" polish.
> - **P1 — Half-wired.** Code exists but is never reached, or is reached but doesn't behave as named. The "we built it but you can't see it" class.
> - **P2 — Polish.** Spacing, mobile layout, payload handling, premium-feel touches, dead code removal.

---

## CHANGELOG

### Phase UI-POLISH-FE — Voice Notes + Vault Polish (2026-05-26, in review, FE)

**Frontend-only polish pass.** Closes the four deferred items from the
UI-1 through UI-5 sprint summary: in-bubble inline audio playback, an
in-app hold-to-record audio recorder, a Tickets/Receipts tab counter
badge, and cursor-based pagination for the Receipts vault.

**What this PR does:**

1. **In-bubble inline audio playback.** `_AudioBubble` in
   `chat_media_bubble.dart` rewritten from a stateless launcher into a
   stateful inline player backed by `audioplayers: ^6.1.0`. Tap the play
   circle to play / pause; waveform bars colour-fill in proportion to
   the playback position; the duration label flips between elapsed and
   total time. Tap or drag horizontally on the waveform to seek. A
   process-wide singleton (`_AudioBubblePlayerRegistry`) pauses every
   other registered audio bubble when a new one starts, mirroring
   WhatsApp / iMessage. Falls back to the legacy `_openInSystemViewer`
   path for codecs `audioplayers` can't decode.

2. **Hold-to-record voice notes.** New `lib/widgets/audio_recorder_button.dart`
   is the canonical mic widget used by both `friend_chat_screen.dart`
   and `ticket_workspace_screen.dart`. Behaviour:
   - **Idle** — circular mic button.
   - **Long-press** — haptic, recording starts, the input swaps to a
     red "recording strip" with a pulsing dot, elapsed time, and a
     slide-to-cancel hint.
   - **Slide left ≥ 80px** — indicator turns red; releasing past the
     threshold cancels and discards the file.
   - **Release short (< 700ms)** — treated as accidental tap; file
     discarded.
   - **Release long** — calls `onRecorded(file, duration, peaks)`.
     Caller uploads via `ChatMediaService.uploadAudio()` then sends an
     AUDIO-typed message with the seven media fields populated.
   `record` package configured for AAC LC at 96kbps / 44.1kHz.
   `onAmplitudeChanged` is sampled to 50 buckets max so the payload
   matches the Phase UI-3 BE waveformPeaks contract.

3. **Input bar swap (mic vs send).** `friend_chat_screen.dart`'s
   `_buildInputBar` and `ticket_workspace_screen.dart`'s `_InputBar`
   now show the mic when the text field is empty and swap to the send
   arrow as soon as the user types. New `_isUploadingAudio` state on
   each screen locks the mic while a voice-note upload is in flight so
   a fast second hold can't kick off a parallel upload.

4. **AUDIO + IMAGE + VIDEO + DOCUMENT + LINK rendering wired into
   friend chat.** `friend_chat_screen.dart`'s message dispatcher now
   routes any of those five types through `ChatMediaBubble`, so a
   voice note (or any other media) sent from one device renders
   correctly on the other side. The ticket workspace already used
   `ChatMediaBubble` from UI-4; this brings friend chat to parity.

5. **`FriendService.sendMessage` extended** with optional Phase UI-3
   media kwargs (`messageType`, `mediaUrl`, `mediaType`, `mediaMimeType`,
   `mediaSize`, `mediaDuration`, `mediaWaveformPeaks`, `linkPreview`,
   `metadata`). The BE half (`directMessageController.sendMessage`)
   already accepted these in Phase UI-3; this PR closes the FE-side gap
   so the recorder can post AUDIO-typed messages.

6. **Tickets / Receipts vault tab counter badges.**
   `chat_profile_screen.dart` Tickets and Receipts tab labels now render
   with a count chip when count > 0 (capped at "99+") so users can see
   at a glance how much history exists in each tab. Implemented via a
   new `_CountedTab` widget that reads `ticketDashboardProvider` for
   tickets and the local profile state for receipts.

7. **Receipts cursor pagination.** `chat_profile_provider.dart` extended
   with `receiptsHasMore`, `receiptsNextCursor`, `receiptsLoadingMore`
   state, plus a new `loadMoreReceipts()` method that calls the BE with
   the next cursor and appends to the list. The Receipts tab now
   renders a "Load more" outlined button as the last list item when
   more pages exist; tapping it appends the next 50. The BE already
   served `nextCursor` + `hasMore` from Phase UI-5; the FE was capping
   at the first 50 until now.

**`pubspec.yaml`** adds `audioplayers: ^6.1.0`. `record` is unchanged
(used for capture only).

**No regressions.** All UI-1 through UI-5 surfaces continue to work.
Audio bubbles in older threads now play inline instead of opening the
system viewer; if the codec isn't supported the bubble falls back to
the legacy launcher. The mic-vs-send swap doesn't change the send
button's hit target when the user has typed text.

Files (3 NEW + 6 modified + 1 pubspec + 2 docs):
`lib/widgets/audio_recorder_button.dart` (NEW),
`lib/widgets/chat_media_bubble.dart`,
`lib/screens/friends/friend_chat_screen.dart`,
`lib/screens/tickets/ticket_workspace_screen.dart`,
`lib/screens/chat_profile_screen.dart`,
`lib/providers/chat_profile_provider.dart`,
`lib/services/friend_service.dart`,
`pubspec.yaml`. Plus `FRONTEND_AUDIT.md` + `AZAMAN_MASTER_SOUL.md`.

---

### Phase UI-5-FE — Chat Profile + Transaction Vault (2026-05-26, in review, FE)

**Frontend half of the Chat Profile + Vault.** Companion BE PR ships
five aggregator endpoints + a new transfer-receipt PDF generator.
This PR provides the typed service layer, Riverpod state, the full
profile screen, and the wire-up from the friend chat AppBar.

**What this PR does:**

1. **`lib/services/chat_profile_service.dart` (NEW).** Typed REST
   client. Models: `ChatProfileResponse`, `ChatProfileFriend`,
   `VaultItem` (source-agnostic — drives both Media and Docs/Links
   tabs), `ReceiptItem`, `VaultListResponse<T>`. Methods:
   `getProfile`, `setNickname`, `getMedia`, `getDocsAndLinks`,
   `getReceipts`. All routed through `apiClient` so JWT attaches
   automatically.

2. **`lib/providers/chat_profile_provider.dart` (NEW).** Riverpod
   `StateNotifierProvider.family.autoDispose` keyed by
   `friendshipId`. Owns four datasets in one state shape (profile +
   media + docs/links + receipts). `primeAll()` fires all four
   fetches in parallel on first load. Per-tab `refreshX()` methods
   power pull-to-refresh. `setNickname` is optimistic-with-rollback
   — the local nickname flips immediately, then the server call
   either confirms or restores the previous profile on failure.

3. **`lib/screens/chat_profile_screen.dart` (NEW).** Two-tier layout:
   - **Identity tier** — bordered card with avatar, displayed name
     (local nickname when set; otherwise the friend's username, with
     a `@username` subtitle when a nickname overrides it), "Friends
     since {Mon Year}", KYC verified badge, three stat pills
     (Mutual trades / Their trades / Completion %). Pencil icon
     opens an edit-nickname dialog with save/clear/cancel actions.
   - **Tabbed vault** — Material `TabBar` with four tabs:
     * **Media** — 3-column `GridView` mixing DirectMessage +
       TicketMessage rows. Image tiles use `Image.network` with
       error fallback; video tiles render a poster-tinted card with
       a centered play overlay; ticket-source items display a green
       "TICKET" ribbon in the corner. Tap launches the URL
       externally for now.
     * **Docs & Links** — `ListView` with mime-aware icon plates
       (PDF / Word / Excel / PPT / text), filename, byte-size,
       download chevron. LINK rows render with an open-in-new icon
       and route via `url_launcher`. Document rows download via
       `http` + `getTemporaryDirectory` + `OpenFilex.open`.
     * **Tickets** — reuses Phase UI-4 `ticketDashboardProvider`.
       Merges all three buckets (open / closed / cancelled) sorted
       by `lastActivityAt DESC`. Each row tappable into
       `TicketWorkspaceScreen`.
     * **Receipts** — list of PeerTransfer rows with up/down
       direction arrows, amount + currency, status chip, optional
       memo line, relative-time stamp. COMPLETED rows show a
       download button that fetches the BE's
       `/api/receipts/transfer/:id` PDF endpoint via `apiClient.get`,
       writes to temp dir, and opens with `open_filex`.

4. **`lib/screens/friends/friend_chat_screen.dart` rewired:** the
   AppBar title row (avatar + username) is now wrapped in a
   `GestureDetector` that pushes `ChatProfileScreen`. Touch target
   stays the same; only behaviour changed. The Phase UI-4 Ticket
   button next to it is untouched.

**No regressions.** The profile screen is reachable only by avatar
tap; older surfaces / older builds that don't know about it never
see it. Existing transfer / nickname / typing flows are unchanged.

Files (3 NEW + 1 modified + 2 docs): `lib/services/chat_profile_service.dart`
(NEW), `lib/providers/chat_profile_provider.dart` (NEW),
`lib/screens/chat_profile_screen.dart` (NEW),
`lib/screens/friends/friend_chat_screen.dart`. Plus `FRONTEND_AUDIT.md`
+ `AZAMAN_MASTER_SOUL.md`.

---

### Phase UI-4-FE — Tickets Engine (2026-05-26, in review, FE)

**Frontend half of the Tickets Engine.** Companion BE PR ships schema,
six REST endpoints, and the socket service. This PR provides the dashboard,
creation flow, isolated workspace surface, and the integration into the
friend chat screen (header button, event-card rendering, presence banner).

**What this PR does:**

1. **`lib/services/ticket_service.dart` (NEW).** Typed REST client.
   `Ticket`, `TicketMessageRow`, `TicketListResponse`, `TicketDetailResponse`
   models with full `fromJson` parsing. `TicketType` and `TicketStatus`
   enums with `.wire` and `.label` extensions for clean round-tripping.

2. **`lib/providers/ticket_provider.dart` (NEW).** Two Riverpod families:
   - `ticketDashboardProvider(friendshipId)` (StateNotifier) — buckets
     for Open / Closed / Cancelled, active tab tracking, parallel
     `refresh()`, optimistic injection on `createTicket`, bridge methods
     for socket events.
   - `ticketWorkspaceProvider(ticketId)` (StateNotifier.autoDispose) —
     ticket detail + chronological messages, optimistic `sendText`,
     `close()` / `cancel()` / `reopen()`, presence state.

3. **`lib/screens/tickets/ticket_dashboard_screen.dart` (NEW).** Three
   pill-style tabs (Open | Closed | Cancelled) over a tile list, pull-to-
   refresh, skeleton loader, empty/error states. `FloatingActionButton.
   extended` "New Ticket" CTA at the bottom-right opens the create sheet.
   Each tile shows the ticket icon, name, type, target amount + currency,
   memo preview, and a status-coloured chip.

4. **`lib/screens/tickets/ticket_create_sheet.dart` (NEW).** Bottom-sheet
   form with the four required fields plus optional memo. ChoiceChip row
   for transaction type (Buy / Sell / Escrow / Service Swap), decimal-
   safe amount input, currency dropdown (USD, GHS, USDC, USDT, AZM, EUR,
   GBP, NGN), 4-line memo with 500-char cap. On submit, calls the
   provider's `createTicket()` which fires the BE create, injects the
   ticket optimistically into the Open bucket, and returns the row so
   the caller can immediately push the workspace.

5. **`lib/screens/tickets/ticket_workspace_screen.dart` (NEW).** The
   isolated chat surface for one ticket:
   - Header card with type badge, target amount + currency, memo banner.
   - Counterparty presence banner below the header (when applicable).
   - Chronological message list. Media types route through the Phase UI-3
     `ChatMediaBubble` widget; SYSTEM messages render as ghost-italic
     centered text; TEXT messages render in standard left/right bubbles.
   - Text input with send button at the bottom (locked when ticket is
     not OPEN — replaced by a "This ticket is closed/cancelled" footer
     with a hint to reopen).
   - AppBar popup menu: when OPEN, "Close ticket" + "Cancel ticket"
     entries; when CLOSED/CANCELLED, a single "Reopen ticket" entry.
     Each transition fires a confirmation dialog before committing.
   - On mount: emits `join_ticket` over socket and fires REST
     `pingPresence(viewing: true)` so the counterparty's banner lights
     up. Lifecycle observer also handles foreground/background flips —
     pausing the app emits `leave_ticket` so the banner clears.

6. **`lib/screens/friends/friend_chat_screen.dart` rewired:**
   - **AppBar action SWAPPED.** The legacy `Icons.swap_horiz_rounded`
     "Transfer" icon was replaced by a prominent
     `Icons.confirmation_number_rounded` Ticket button that opens the
     dashboard. Send-money still reachable via the existing in-chat
     `+` send funds button on the input bar.
   - **TICKET_LINK event card renderer.** When a message arrives with
     `messageType: 'TICKET_LINK'`, a new branch in the bubble dispatcher
     reads the `metadata` envelope and renders a tappable status-coloured
     tile with the ticket name, type, target amount + currency, status,
     and an "Open ticket →" CTA. Tapping deep-links to the workspace.
   - **Counterparty presence banner.** New socket listener for
     `ticket_presence_update`. While the friend has any ticket workspace
     open under this friendship, a soft banner appears above the input
     bar with *"<friendName> is currently viewing the ticket window."*
     Auto-clears on `viewing: false` or after a 60s safety timeout.

**Backwards compat.** Older clients that don't know `TICKET_LINK` fall
through to the existing TEXT-bubble path and render the event card's
human-readable `content` string. No socket-level coordination required —
the new events are additive.

**No changes to existing transfer flow.** Transfer messages, the transfer
modal, fulfill/decline actions all keep working untouched. The Ticket
button is a sibling, not a replacement, for the in-chat send-money
affordance.

Files (5 NEW + 1 modified + 2 docs):
`lib/services/ticket_service.dart` (NEW),
`lib/providers/ticket_provider.dart` (NEW),
`lib/screens/tickets/ticket_create_sheet.dart` (NEW),
`lib/screens/tickets/ticket_dashboard_screen.dart` (NEW),
`lib/screens/tickets/ticket_workspace_screen.dart` (NEW),
`lib/screens/friends/friend_chat_screen.dart`. Plus `FRONTEND_AUDIT.md`
+ `AZAMAN_MASTER_SOUL.md`.

---

### Phase UI-3-FE — Chat Media Infrastructure (2026-05-26, in review, FE)

**Frontend half of the chat-media expansion.** Companion BE PR ships
schema, migration, four typed upload endpoints, link-preview endpoint,
and `directMessageController.sendMessage` extension. This PR provides
the Flutter service layer and the canonical render widget that every
chat surface (direct, trade, ticket workspace from UI-4, vault grids
from UI-5) plugs into without re-implementing media handling.

**What this PR does:**

1. **`lib/services/chat_media_service.dart` (NEW).** Singleton that wraps
   the four typed upload endpoints + link preview endpoint with
   `ChatMediaUploadResult` and `LinkPreview` envelopes. `multipart()` calls
   go through `apiClient` so JWT auth is attached automatically. `MediaType`
   guesses from extension feed Content-Type to the multipart parts so the
   server's mime filters get the right signal.

2. **`lib/widgets/chat_media_bubble.dart` (NEW).** Stateless `ChatMediaBubble`
   that knows how to render all five media kinds:
   - **IMAGE** — 240×240 thumbnail, tap opens system viewer via URL launcher.
   - **VIDEO** — 16:9 thumbnail with play overlay + duration badge, tap
     downloads to temp dir and opens with `open_filex`.
   - **AUDIO** — playback row with play button, 50-bar waveform (peaks
     supplied by server or fallback flat array), duration label. Currently
     opens system audio viewer; in-bubble inline playback deferred to a
     polish PR.
   - **DOCUMENT** — file row with mime-aware icon (PDF / Word / Excel /
     PPT / text), filename, byte-size, download chevron.
   - **LINK** — Open Graph preview card with hero image, site name, title,
     description; falls back to a plain underlined-link tile if the server
     couldn't resolve metadata.
   `ChatMediaPayload.fromMessageJson` is the wire-format adapter — pass any
   `DirectMessage` JSON in, get a typed payload out. Same widget drops into
   the trade chat (`Message` table) since both tables share the wire format.

3. **`pubspec.yaml` — added `file_picker: ^8.1.4`.** For document
   selection. Image picking continues via `image_picker`, audio via
   `record`, video via `image_picker` (handles both photo and video
   capture). All four pickers feed the same upload pipeline.

**Audio recorder UI deferred.** The `record` package is already in pubspec;
the upload endpoint accepts pre-computed waveform peaks so a future polish
PR can drop the recorder in without any BE changes.

**No regression for existing chats.** `ChatMediaBubble` only renders when
a message's `messageType` matches one of the five new values; legacy TEXT
messages render through their existing path unchanged.

Files (3 + 2 docs): `lib/services/chat_media_service.dart` (NEW),
`lib/widgets/chat_media_bubble.dart` (NEW), `pubspec.yaml`.
Plus `FRONTEND_AUDIT.md` + `AZAMAN_MASTER_SOUL.md`.

---

### Phase UI-2-FE — Drawer Payout/Deposit Realignment (2026-05-26, in review, FE)

**Pure FE nav restructure — no backend touches.** Continues the UI-1 cleanup
into the drawer payment area: deposits and withdrawals now sit side-by-side as
a coherent "Payment Addresses" pair, and global-fiat trade accounts are pulled
out of the user-facing settings tree so they live exclusively in the vendor
dashboard.

**What this PR does:**

1. **`lib/widgets/settings_drawer.dart` — "PAYMENT ADDRESSES" pair.** The
   former "MERCHANT PROTOCOLS" section is renamed and now hosts two slender
   tiles in a single bordered container:
   - **Deposit Addresses** → routes to `DepositScreen` (existing dual-tab
     screen with Crypto + Mobile Money panels). Icon: `Icons.south_rounded`
     in success-green.
   - **Withdrawal Addresses** → routes to `SavedWalletsScreen`. Icon:
     `Icons.north_rounded` in warning-amber.
   Visual semantics: down arrow = funds-in (deposit), up arrow = funds-out
   (withdraw). One section, one card, two tiles separated by a hairline.
   The duplicate "Withdrawal Addresses" entry that previously lived under
   the "RECOMMENDED" section is removed (was the only door in until UI-2).

2. **`lib/screens/settings_screen.dart` — "Trade Accounts" tile REMOVED.**
   The user-facing Settings → Payment row that linked to `TradeAccountsScreen`
   conflated payout destinations (where Azaman sends money to the user) with
   vendor-side ad-receipt accounts (where ad counterparties send money to the
   vendor). Trade Accounts hold global fiat handles — Zelle, CashApp, Venmo,
   PayPal, Apple Pay, Google Pay, Wise, Revolut, Gift Cards, Western Union,
   Wire Transfer — that are EXCLUSIVELY used by vendors for P2P ad placements.
   The vendor dashboard already has a "MANAGE TRADE ACCOUNTS" button; that is
   now the only entry point. The unused `trade_accounts_screen.dart` import
   is also dropped.

3. **`lib/screens/saved_wallets_screen.dart` — filter hardened.** The
   `_isValidPayoutWallet` helper now runs an explicit BLOCKLIST first that
   rejects all 11 global-fiat trade-account method types by name (in case a
   legacy conflated row somehow has a `network` value that would otherwise
   pass the allow-list). The header doc-comment was updated to enumerate the
   forbidden types verbatim, and the on-screen helper text now reads "Global
   fiat handles (Zelle, CashApp, etc.) live in the Vendor Dashboard's Trade
   Accounts area, not here." instead of pointing the user at a Settings →
   Trade Accounts link that no longer exists.

**Effect for the user:**
- Drawer is the single home for managing every external account they use to
  fund their platform operations (deposits) and receive payouts (withdrawals).
- A regular user can't accidentally land on `TradeAccountsScreen` from the
  user-side surfaces; vendors still have full access from the vendor dashboard.
- Even old conflated SavedWallet rows (created back when the screens were
  mixed) won't render in the Withdrawal Addresses screen — the BLOCKLIST
  catches them.

**No backend changes.** The `/api/wallet/saved` and `/api/trade-accounts/*`
endpoints are unchanged; this PR is purely a navigational and visual tightening.

Files (3 + 2 docs): `lib/widgets/settings_drawer.dart`,
`lib/screens/settings_screen.dart`, `lib/screens/saved_wallets_screen.dart`.
Plus `FRONTEND_AUDIT.md` + `AZAMAN_MASTER_SOUL.md`.

---

### Phase UI-1-FE — De-cluttering Sweep (2026-05-26, in review, FE)

**Pure cosmetic cleanup pass — no behaviour changes, no backend touches.** Pulls
four redundant or bulky UI elements off the surface so the app reads sleeker
without losing any function.

**What this PR does:**

1. **Header chat icon removed (`lib/main.dart`).** The `Icons.chat_bubble_outline_rounded`
   IconButton sat between the AZAMAN title and the notification bell. It opened
   the Friends Hub. The bottom nav bar's "Chat" tab opens the same hub. Two doors
   into one room — the AppBar door is gone. The friend-unread `Stack` + badge
   block is retired with it; the bottom-nav Chat tab already carries its own
   unread indicator (Phase B2 wired).

2. **Vendor pull-tab popup rewritten (`lib/widgets/vendor_pull_tab.dart`).** The
   first-pull "You're Not a Vendor Yet" bottom sheet had a green "Start Application"
   ElevatedButton that immediately bypassed the deliberate 3-pull gate. Replaced
   with a clean text block: *"For full vendor program details, FAQ, and success
   stories, visit azaman.me/vendors. To begin your application, dismiss this and
   pull the side tab 2 more times within 5 seconds."* The 3-pull confirmation
   flow is now the only in-app path to the registration form.

3. **"Trade Now" button removed from ad cards (`lib/widgets/vendor_ad_card.dart`).**
   Phase F2 introduced the `ad_detail_flip_card` overlay — tapping a marketplace
   ad now flips it open with a 3D X-axis animation and shows the trade form on
   the back face. The standalone "Trade Now" button on the front face was a
   bulky redundant exit point. Card-tap is the only interaction gateway now.
   Queue state still surfaces via the existing chip; tapping a queued card still
   routes through the flip overlay (which gates the form internally).

4. **Drawer payment tiles slimmed (`lib/widgets/settings_drawer.dart`).** The
   "MERCHANT PROTOCOLS" section's `_buildPortalTile` was a 16-pad card with a
   40×40 icon plate, multi-line subtitle, and a `verified_user` trailing icon.
   Replaced with a new `_buildSlenderTile`: 12-pad row, 32×32 icon plate, single
   line title, single-line subtitle, hairline `chevron_right`. Same hit target,
   ~40% less vertical chrome. Pattern set up so Task 2 (mirror Deposit Addresses
   into the drawer) can reuse the same tile shape.

**Master sprint framework for Tasks 2-5** (Drawer Realignment, Chat Media
Infrastructure, Tickets Engine, Chat Profile + Vault) is documented in
§15 of `AZAMAN_MASTER_SOUL.md`. This PR is Task 1 only.

Files (4 + 2 docs): `lib/main.dart`, `lib/widgets/vendor_pull_tab.dart`,
`lib/widgets/vendor_ad_card.dart`, `lib/widgets/settings_drawer.dart`.
Plus `FRONTEND_AUDIT.md` + `AZAMAN_MASTER_SOUL.md`.

---

### Phase POLISH-FE — Inter Custom Font (2026-05-25, in review, FE)

**App-wide typography upgrade to Inter via `google_fonts` package.** Replaces the
default Roboto/San Francisco system fonts with Inter — a purpose-built UI typeface
with excellent readability at small sizes, optimized x-height, and tabular
numerals for financial data display.

**What this PR does:**

1. **`pubspec.yaml`:** Added `google_fonts: ^6.2.1` dependency. The package
   handles font fetching/caching automatically at runtime and bundles the font
   in release builds via the asset manifest.

2. **`lib/providers/theme_provider.dart`:** Imported `google_fonts` and set
   `fontFamily: GoogleFonts.inter().fontFamily` in the `ThemeData` returned by
   `getThemeData()`. This propagates Inter to ALL Material text styles app-wide
   (AppBar titles, body text, buttons, inputs, snackbars) without touching
   individual screen files.

**Effect:** Every text widget in the app now renders in Inter. No per-screen
changes needed — the ThemeData `fontFamily` cascades through the entire widget
tree. All 12 theme variants (dark, light, cyber blue, etc.) inherit the font.

Files (2 + 2 docs): `pubspec.yaml`, `lib/providers/theme_provider.dart`.
Plus `FRONTEND_AUDIT.md` + `AZAMAN_MASTER_SOUL.md`.

---

### Phase Q11-FE — Receipt Download Button (2026-05-25, in review, FE)

**PDF receipt download for completed trades and withdrawals.** Consumes
`GET /api/receipts/trade/:tradeId` and `GET /api/receipts/withdrawal/:id`
(Phase Q11 BE endpoints). Both return binary PDF with Content-Disposition attachment.

**What this PR does:**

1. **New `lib/services/receipt_service.dart`:** Static service with
   `downloadTradeReceipt(tradeId)` and `downloadWithdrawalReceipt(id)`.
   Fetches binary PDF with auth header, saves to temp directory via
   `path_provider`, opens with system PDF viewer via `open_filex`.
   Throws on non-200 with parsed error message.

2. **`lib/screens/trade_summary_screen.dart` (modified):** New "Download
   Receipt" `OutlinedButton.icon` positioned between the receipt card and
   the review section. Loading spinner while downloading. Success/error
   snackbars. Only shown on the trade summary screen (which is only
   reachable for COMPLETED trades by definition).

3. **`lib/screens/withdrawal_screen.dart` (modified):** New "Recent Completed
   Withdrawals" expandable section at the bottom of the form. Tap to load
   fetches `GET /wallet/history`, filters to COMPLETED status, shows max 5
   entries. Each entry has a compact "Receipt" download chip button with
   per-item loading state.

4. **`pubspec.yaml`:** Added `open_filex: ^4.5.0` for opening downloaded
   PDFs with the system viewer.

**No backend code change.** Consumes the existing Phase Q11 BE receipt endpoints.

Files (1 new + 3 modified + 2 docs): `lib/services/receipt_service.dart` (NEW),
`lib/screens/trade_summary_screen.dart`, `lib/screens/withdrawal_screen.dart`,
`pubspec.yaml`. Plus `FRONTEND_AUDIT.md` + `AZAMAN_MASTER_SOUL.md`.

---

### Phase Q12-FE — Rate Alert UI (2026-05-25, in review, FE)

**Rate alert system wired into the home screen LiveMarketSection.** Users can
set price alerts for the USD→GHS rate and get notified when the rate hits their
target. Consumes `POST/GET/DELETE /api/oracle/alerts` (Phase Q12 BE).

**What this PR does:**

1. **New `lib/services/rate_alert_service.dart`:** Singleton wrapping the three
   oracle alert endpoints. Models: `RateAlert` (id, targetRate, direction, note,
   status, triggeredAt/Rate, createdAt) and `RateAlertListResponse`. Full CRUD.

2. **New `lib/providers/rate_alert_provider.dart`:** Riverpod ChangeNotifier with
   `fetchAlerts()`, `createAlert()`, `deleteAlert()`, `refresh()`. Exposes
   `activeAlerts`, `triggeredAlerts`, `currentRate`, loading/error states.

3. **New `lib/widgets/rate_alert_sheet.dart`:** DraggableScrollableSheet with:
   - Create form: target rate input, ABOVE/BELOW toggle chips, optional label,
     "Create Alert" CTA
   - Active alerts list with direction icons, target rates, triggered badges,
     delete buttons
   - Current rate badge in header

4. **`lib/widgets/live_market_section.dart` (modified):** Below the GHS hero card,
   a new "Set Rate Alert" button with active alert count badge. Active alerts
   shown as colored chips (green for ABOVE, red for BELOW, max 3 + "+N more").

5. **`lib/services/api_client.dart` (modified):** Added `delete()` method for
   HTTP DELETE requests (was missing, needed by rate alert deletion).

**No backend code change.** Consumes the existing Phase Q12 BE endpoints.

Files (3 new + 2 modified + 2 docs): `rate_alert_service.dart` (NEW),
`rate_alert_provider.dart` (NEW), `rate_alert_sheet.dart` (NEW),
`live_market_section.dart`, `api_client.dart`.

---

### Phase Q16-FE — Vendor Analytics Screen (2026-05-25, in review, FE)

**New vendor analytics dashboard reachable from vendor portal → analytics icon.**
Consumes `GET /api/vendor/analytics?period=7d|30d|90d` (Phase Q16 BE endpoint).
Shows aggregated vendor performance data with period selection, summary stats,
volume chart, and payment method breakdown.

**What this PR does:**

1. **New `lib/services/vendor_analytics_service.dart`:** Singleton service wrapping
   the `/vendor/analytics` endpoint via `ApiClient.get()`. Models: `VendorAnalyticsSummary`
   (totalTrades, totalVolume, totalRevenue, avgCompletionMinutes, disputeRate,
   disputesInPeriod, allTimeTrades), `VolumeDataPoint` (date, volume, trades, revenue),
   `MethodBreakdownEntry` (method, volume, trades, revenue), `VendorAnalyticsData`
   (period, days, summary, volumeTimeline, methodBreakdown). All with `fromJson` factories.

2. **New `lib/providers/vendor_analytics_provider.dart`:** Riverpod
   `ChangeNotifier.autoDispose` with `AnalyticsPeriod` enum (sevenDays/thirtyDays/
   ninetyDays → queryValue + displayLabel). Exposes: `data`, `activePeriod`,
   `isLoading`, `error`, `hasFetched`, `summary`, `volumeTimeline`, `methodBreakdown`.
   Methods: `fetchAnalytics({force})`, `switchPeriod(period)`, `refresh()`.

3. **New `lib/screens/vendor_analytics_screen.dart`:** Full analytics page:
   - **Period selector:** Animated container tabs (7D / 30D / 90D) in a pill row.
     Tap switches period and re-fetches.
   - **Summary cards:** 5 stats in a 3+2 row layout (Trades, Volume, Revenue /
     Avg Time, Dispute Rate). Each card has an icon, bold value, and label. Dispute
     rate is color-coded: green (<2%), yellow (2-5%), red (>5%).
   - **Volume chart:** `fl_chart` `LineChart` with curved line, filled area below,
     left-axis labels (K-formatted), bottom-axis date labels (day/month),
     touch tooltips showing exact volume + trade count per day.
   - **Payment method breakdown:** List of methods sorted by volume (highest first).
     Each row shows method name (SCREAMING_CASE → Title Case), dollar volume,
     `LinearProgressIndicator` bar normalized to the largest method, and trade
     count + revenue subtitle.
   - **Skeleton loading:** Shimmer-style placeholder boxes matching the card/chart/
     list layout during first fetch.
   - **Error state:** Icon + message + "Retry" button.
   - **Pull-to-refresh:** `RefreshIndicator` wrapping `CustomScrollView`.

4. **`lib/screens/vendor_dashboard.dart` (modified):** New `Icons.analytics_outlined`
   `IconButton` in the AppBar row, positioned before the existing settings gear.
   Navigates to `VendorAnalyticsScreen` via `Navigator.push`.

**No backend code change.** Consumes the existing Phase Q16 BE endpoint.

Files (3 new + 1 modified + 2 docs): `lib/services/vendor_analytics_service.dart` (NEW),
`lib/providers/vendor_analytics_provider.dart` (NEW),
`lib/screens/vendor_analytics_screen.dart` (NEW),
`lib/screens/vendor_dashboard.dart` (~5 lines).
Plus `FRONTEND_AUDIT.md` + `AZAMAN_MASTER_SOUL.md`.

---

### Phase Q15-FE — Force Update Screen (2026-05-25, in review, FE)

**App version gate: blocks outdated builds from proceeding past splash.**
On startup, the splash screen calls `GET /health` (no auth) and inspects
`versionGate.minVersion`. If the client version (from `AppConfig.appVersion`)
is less than the backend's minimum, a blocking "Update Required" screen is
shown with the backend's message and an "Update Now" button linking to the
store URL.

**What this PR does:**

1. **New `lib/services/version_gate_service.dart`:** Singleton service that
   calls `/health` (unauthenticated), parses `versionGate` from the response,
   and performs a simple semver comparison (split on ".", compare numerically).
   Fail-open design: if the endpoint is unreachable, the app proceeds normally.

2. **New `lib/screens/force_update_screen.dart`:** Blocking fullscreen overlay.
   Back button disabled via `PopScope(canPop: false)`. Shows update icon,
   message from backend, minimum version label, and an "Update Now" ElevatedButton
   that opens the store URL via `url_launcher`. Fully themed via
   `ref.watch(themeProvider).colors`.

3. **`lib/screens/splash_screen.dart` (modified):** Version gate check inserted
   BEFORE the auth flow. If update is required, navigates to `ForceUpdateScreen`
   and returns early — no auth check happens for outdated clients.

4. **`pubspec.yaml`:** Added `package_info_plus: ^8.0.0` (reserved for future
   runtime version detection; current implementation uses `AppConfig.appVersion`
   compile-time constant for zero-dependency reliability).

**No backend code change.** Consumes the existing Phase Q15 BE `/health` versionGate field.

### Phase Q10-FE — Leaderboard Real Data (2026-05-25, in review, FE)

**Wires the leaderboard screen to consume real backend data.** The previous
`leaderboard_screen.dart` used 20 hardcoded `_RankUser` entries with fake
usernames and calculated volumes. Now it fetches from
`GET /api/vendor/leaderboard?metric=&limit=` and renders live vendor rankings.

**What this PR does:**

1. **New `lib/services/leaderboard_service.dart`:** Singleton service wrapping
   the `/vendor/leaderboard` endpoint via `ApiClient.get()`. Accepts `metric`
   (xp, volume, trades, profit, streak) and `limit` params. Parses the
   `{ success, data: { metric, myRank, totalVendors, leaderboard[] } }` response.

2. **New `lib/providers/leaderboard_provider.dart`:** Riverpod ChangeNotifier
   exposing: `List<LeaderboardEntry> entries`, `int? myRank`, `int totalVendors`,
   `LeaderboardMetric activeMetric`, `isLoading`, `error`. Methods:
   `fetchLeaderboard()`, `switchMetric()`, `refresh()`. Model class
   `LeaderboardEntry` with `fromJson` factory. Enum `LeaderboardMetric` with
   5 values (xp, volume, trades, profit, streak) mapping to display labels and
   query values.

3. **`lib/screens/leaderboard_screen.dart` (rewrite):** Complete replacement of
   the hardcoded screen:
   - **Metric tabs:** Scrollable TabBar with 5 metrics (XP, VOLUME, TRADES,
     PROFIT, STREAK). Tab change triggers `switchMetric()` on provider.
   - **Pull-to-refresh:** `RefreshIndicator` wrapping a `CustomScrollView`.
   - **Skeleton loading:** 8 placeholder cards with grey shimmer boxes during
     first load.
   - **Empty state:** Icon + "No Rankings Yet" message + Refresh button when
     leaderboard is empty.
   - **Error state:** "Failed to Load Rankings" with Retry button.
   - **"Your Rank" banner:** Shown when the logged-in user is outside the top
     N results (rank known but `isYou` not in list).
   - **Stats summary row:** "[N] vendors ranked" left, "You: #[rank]" right.
   - **isYou highlighting:** Accent border + "YOU" chip + tinted background
     for the current user's row.
   - **KYC verified badge:** Blue checkmark icon on verified vendors.
   - **Contextual metric display:** Primary value and subtext change based on
     active metric (e.g., XP tab shows "1.2K XP" + "45 trades", Volume tab
     shows "$12.5K" + "45 trades").
   - Podium badges (Gold/Silver/Bronze) preserved for top 3.

**No backend code change.** Purely consumes the existing Phase I2 BE endpoint.

Files (3 + 2 docs): `lib/services/leaderboard_service.dart` (NEW),
`lib/providers/leaderboard_provider.dart` (NEW),
`lib/screens/leaderboard_screen.dart` (rewrite).
Plus `FRONTEND_AUDIT.md` + `AZAMAN_MASTER_SOUL.md`.

---

### Phase Q-FE — Notification Navigation + Premium Chat Input (2026-05-25, in review, FE)

**Two high-impact FE fixes shipped together.**

**Q3 — Notification Tap Navigation Fix:**
`_navigateFromNotification` in `notification_hub_screen.dart` fully rewritten.
Previously only handled `tradeId` and `disputeId` payload keys — ALL other
notification types (deposit confirm, KYC update, friend request, vendor alert,
AZM reward, queue promotion, savings reminder) dead-ended on tap. Now handles
ALL 11 action types via a proper `switch` on `payload['action']`:
- `OPEN_TRADE` / `PING_TOPUP` → `/trade/:id`
- `OPEN_DISPUTE` → `/dispute/:id`
- `OPEN_FRIEND_REQUEST` / `OPEN_FRIEND_CHAT` / `OPEN_FRIEND_TRANSFER_REQUEST` → `/friends`
- `OPEN_QUEUE` → `/queue?queueId=&position=&adId=`
- `OPEN_WALLET` → `/` (home, shows balance)
- `KYC_STATUS` / `ACCOUNT_STATUS` → `/settings`
- `VIEW_SAVINGS` → `/savings`
- `OPEN_AD` / `OPEN_MARKETPLACE` → `/marketplace`
- `OPEN_WAR_ROOM` → no-op (admin informational)
- Legacy fallback: flat `tradeId`/`disputeId` keys + `route` field

**Q5 — Premium Chat Input Redesign:**
Complete rewrite of the trade chat text input bar (`chat_interface.dart`).
The old input was a flat `Container` with a basic `TextField` and a plain
`CircleAvatar` send button. Replaced with `_PremiumChatInput` widget:
- Animated focus glow: accent-colored border appears on focus with BoxShadow
- Multi-line support: `maxLines: 4`, `minLines: 1`, auto-grows
- Animated send button: scales from 0.85→1.0 and fades from 0.5→1.0 opacity
  as text appears. BoxShadow on ready state. GestureDetector (not IconButton)
  for smoother hit testing.
- Rounded attachment buttons: gallery + camera in subtle circular containers
  with opacity transitions on enabled/disabled state.
- Proper safe-area handling at the bottom for all device sizes.
- 200ms smooth Curves.easeOutCubic animations throughout.
- Applies to both trade chat AND DM (shared widget).

Files (2): `lib/screens/notification_hub_screen.dart`,
`lib/widgets/chat_interface.dart`. Plus `FRONTEND_AUDIT.md`.

---

### Phase P3-FE — Unify Dual Socket into Single SocketService (2026-05-25, in review, FE)

**Major architectural refactor.** The app previously ran TWO concurrent socket.io
connections — one from `SocketService` (balance/rate/AZM) and another from
`TradeProvider` (trade chat/vendor/notifications). This PR consolidates both into
a single authenticated socket connection in `SocketService`, eliminating:
- Duplicate bandwidth consumption (2x TCP connections per user)
- Race conditions on `balance_update` (both sockets listened for it)
- Confusion about which socket instance owned which events
- Unauthenticated socket (TradeProvider never sent JWT in handshake)

**What this PR does:**

1. **`lib/services/socket_service.dart` (V5):** Added callback registry for
   trade-level events (`trade_update`, `market_update`, `new_notification`,
   `notifications_updated`, `new_trade_request`, `trade_completed`). Added
   `joinTradeRoom()` / `leaveTradeRoom()` / `emit()` helpers. Added
   `ngrok-skip-browser-warning` header. Added auto-rejoin of trade rooms on
   reconnect.

2. **`lib/providers/trade_provider.dart` (V3):** Removed the entire
   `_initSocket()` method and `late IO.Socket _socket` field. Added `IO.Socket?
   get socket => SocketService.instance.rawSocket` getter for backward compat.
   `joinTradeRoom` / `leaveTradeRoom` now delegate to SocketService. Registered
   `onTradeUpdate` + `onMarketUpdate` callbacks in constructor. `dispose()` no
   longer disconnects socket (SocketService owns the lifecycle).

3. **`lib/main.dart`:** Merged `_initHologramSocket()` + `_initLegacySocketRooms()`
   into single `_initUnifiedSocket()`. Registered `onTradeCompleted`,
   `onNewNotification`, `onNewTradeRequest` callbacks. Removed `dispose()`
   socket.off() calls (callbacks are cleared by SocketService.disconnect).

4. **`lib/providers/notification_provider.dart`:** Switched from
   `trade.socket.on(...)` to `SocketService.instance.rawSocket?.on(...)`.
   Removed `trade_provider.dart` import.

5. **All screen-level socket consumers updated:**
   - `active_trade_screen.dart` → `SocketService.instance.rawSocket!`
   - `vendor_trade_execution.dart` → `SocketService.instance.rawSocket!`
   - `vendor_dashboard.dart` → `SocketService.instance.rawSocket`
   - `vendor_settings_screen.dart` → `SocketService.instance.emit(...)`
   - `settings_screen.dart` → `SocketService.instance.disconnect()`
   - `admin/spy_glass_screen.dart` → `SocketService.instance.rawSocket`
   - `admin_war_room_screen.dart` → `SocketService.instance.rawSocket!`

**Result:** Single authenticated socket connection. All 12 demo flows still
function identically — trade chat, real-time balance, AZM rewards, notifications,
vendor toggle, queue promotion all routed through the unified pipe.

**Files changed (9 + 2 docs):**
`lib/services/socket_service.dart`, `lib/providers/trade_provider.dart`,
`lib/providers/notification_provider.dart`, `lib/main.dart`,
`lib/screens/active_trade_screen.dart`, `lib/screens/vendor_trade_execution.dart`,
`lib/screens/vendor_dashboard.dart`, `lib/screens/vendor_settings_screen.dart`,
`lib/screens/settings_screen.dart`, `lib/screens/admin/spy_glass_screen.dart`,
`lib/screens/admin_war_room_screen.dart`, `FRONTEND_AUDIT.md`,
`AZAMAN_MASTER_SOUL.md`.

---

### Phase P2-FE — Theme Sweep: Vendor + Utility Screens (merged 2026-05-25, PR #56)

**Full theme sweep of 6 remaining screens.** Migrated all hardcoded dark color
values to `themeProvider.colors.*` in: `vendor_ad_creator`, `vendor_dashboard`,
`vendor_apply`, `saved_wallets_screen`, `upload_proof`, `p2p_buy_sheet`. Zero
hardcoded `0xFF0B0E11`/`0xFF1E2329` remaining outside `splash_screen`.

---

### Phase P1-FE — Audit Fixes: Theme Migration + Queue Promotion + GHS→USD (merged 2026-05-25, PR #55)

**Frontend companion to BE PR #67 (Phase P1).** Three P0/P1 fixes discovered
during the full end-to-end flow audit.

**What this PR does:**

1. **`lib/screens/profile_details_screen.dart`** — Full theme migration. All
   hardcoded dark colors (`0xFF0B0E11`, `0xFF1E2329`, `Colors.white`,
   `Colors.white54`, `Colors.white38`) replaced with `ref.watch(themeProvider).colors.*`.
   Same fix pattern as TradeSummaryScreen (PR #54). Light/snow themes now render
   correctly on this screen.

2. **`lib/main.dart`** — `new_trade_request` snackbar text changed from
   `"wants to trade ${amount} GHS"` to `"wants to trade $${amount} USD"`.
   Phase F2 corrected the entire P2P model to USD (1:1 USDC parity); this
   snackbar was the last stale GHS reference in user-facing text.

3. **`lib/screens/waiting_room_screen.dart`** — `_handlePromotion` and
   `_handleQueueUpdate` now handle the case where `queue_promoted` arrives
   WITHOUT a `tradeId` (the correct behavior — the BE marks the queue entry
   as PROCESSED and notifies the buyer, but doesn't auto-create a Trade row).
   Instead of crashing on an empty `orderId: '#'`, the screen now pops back
   to the marketplace with a "Your turn! A trade slot is now open." snackbar.
   If a future BE change does provide a `tradeId`, the auto-nav to
   `ActiveTradeScreen` still works (forward-compat).

**Audit findings NOT addressed in this PR (deferred):**
- **Dual socket connections** (TradeProvider + SocketService) — major refactor,
  filed as Phase P2 candidate.
- **KycVerificationScreen hardcoded colors** — cosmetic, lower priority.

Files (3 + 2 docs): `lib/screens/profile_details_screen.dart` (rewrite),
`lib/main.dart` (~1 line), `lib/screens/waiting_room_screen.dart` (~20 lines),
`FRONTEND_AUDIT.md` + `AZAMAN_MASTER_SOUL.md`.

### Phase N-FE — Queue/Waiting Room Wiring + Demo Readiness Sweep (2026-05-25, in review, FE)

**Wires the orphan `WaitingRoomScreen` into the live trade flow.** When a vendor
is at max concurrent trades, `initiateTrade()` now returns HTTP 202 + queue data
instead of void. The buyer is auto-navigated to a real-time waiting room with
socket-powered position updates and auto-promotion to `ActiveTradeScreen`.

**What this PR does:**

1. **`lib/providers/marketplace_provider.dart`:** `initiateTrade()` return type
   changed from `Future<void>` to `Future<TradeInitiationResult>`. New model
   `TradeInitiationResult` with `queued`, `tradeId`, `queueId`, `queuePosition`,
   `adId` fields. Handles HTTP 202 (queued) vs 200/201 (immediate). New
   `leaveQueue(queueId)` method calls `PUT /api/ai/queue/:queueId/leave`.

2. **`lib/screens/p2p/p2p_marketplace_screen.dart`:** `_submitTrade()` now
   inspects `result.queued`. If true → navigates to `WaitingRoomScreen`. If
   false → navigates to `ActiveTradeScreen` with the trade ID. Imports added
   for both screens.

3. **`lib/screens/waiting_room_screen.dart`:** Full rewrite. Now accepts
   `queueId` + `adId` (required) and `queuePosition` (defaults 1). Attaches
   socket listeners on init: `queue_position_update` (updates position in real
   time), `queue_promoted` + `queue_update` (auto-navigates to
   `ActiveTradeScreen` on promotion). "LEAVE QUEUE" button wired to the backend
   endpoint with loading/error states. Detaches listeners on dispose.

4. **`lib/router/app_router.dart`:** New `/queue` GoRoute for FCM deep-link
   handling (query params: `queueId`, `position`, `adId`). New `OPEN_QUEUE`
   case in `handleNotificationTap`.

5. **Demo readiness sweep fix:** `vendor_trade_execution.dart` used
   `context.go('/vendor-dashboard')` which is NOT a registered GoRoute →
   replaced with `Navigator.of(context).pop()`. Removed dead `go_router` import.

**Demo Readiness Sweep results (all 12 flows verified):**
- Auth (splash → login → onboarding → MainWrapper) ✅
- P2P marketplace (browse → flip card → confirm → trade/queue) ✅
- Queue path (initiate → WaitingRoomScreen → promoted → ActiveTradeScreen) ✅
- Vendor (dashboard → ad creator → execution → release → summary) ✅
- Trade Accounts (settings → CRUD for 11 methods → vendor ad creator picker) ✅
- AZM Earn (complete trade → socket reward → rewards screen) ✅
- AZM Spend (withdrawal fee discount + ad boost) ✅
- Savings (create → fund → withdraw w/ penalty → pause/resume) ✅
- Social (friends hub → send/request → DM chat) ✅
- Settings (11 themes + system auto, security, trade accounts, etc.) ✅
- Notifications (real-time badge + mark-all-read + multi-device sync + FCM) ✅
- Offline (connectivity banner appears/disappears correctly) ✅

**Known cosmetic debt (non-blocking):** `TradeSummaryScreen` uses hardcoded dark
colors (`0xFF0B0E11`, `0xFF1E2329`) instead of theme palette. Light/snow themes
will look off on that one screen. Deferred to a polish PR.

Files (5 + 2 docs): `lib/providers/marketplace_provider.dart`,
`lib/screens/p2p/p2p_marketplace_screen.dart`,
`lib/screens/waiting_room_screen.dart` (rewrite),
`lib/router/app_router.dart`,
`lib/screens/vendor_trade_execution.dart` (nav fix),
`FRONTEND_AUDIT.md`, `AZAMAN_MASTER_SOUL.md`.

### Phase F2-FE — P2P Architecture Correction (2026-05-25, merged 2026-05-25, PR #52)

**Frontend companion to BE PR #66 (Phase F2).** Corrects the P2P marketplace
from a GHS↔USDC exchange model (with oracle rate math) to the correct global
fiat wallet liquidity bridge model (USDC↔USD, 1:1 parity, flat 2% fee).

**What this PR does:**

1. **New `lib/services/trade_account_service.dart`:** HTTP client for
   `/api/trade-accounts/*` endpoints. Models: `TradeAccount` (with
   `displayLabel`, status helpers), `SupportedMethod` (all 11 types with
   field schemas, display names, icons). Full CRUD: add, list, list-approved,
   get-supported-methods, delete.

2. **New `lib/providers/trade_account_provider.dart`:** Riverpod StateNotifier
   with `primeIfNeeded()`, `refresh()`, `fetchApproved()`, `addAccount()`,
   `deleteAccount()`. Optimistic UI updates.

3. **New `lib/screens/trade_accounts_screen.dart`:** Full management UI —
   account list with status badges (APPROVED/PENDING/REJECTED), add-account
   bottom sheet (type grid → dynamic form → submit), delete confirmation.
   Reachable from Settings → Payment → "Trade Accounts" and Vendor Dashboard
   → "MANAGE TRADE ACCOUNTS" button.

4. **`lib/providers/marketplace_provider.dart`:** `AdListing` model corrected:
   `rate` → `pricePerUSD`, new `adType` (SELL/BUY), `tradeAccountId`, `terms`,
   `isSellAd`/`isBuyAd` getters. Risk classification updated for global payment
   methods. `initiateTrade()` now accepts optional `buyerPaymentDetails`.
   New `TradeInitiationException` with typed error code.

5. **`lib/screens/p2p/p2p_marketplace_screen.dart`:** `_TradeConfirmSheet`
   fully rewritten — USD input (not GHS), no oracle rate dependency, shows
   ad type badge. For SELL ads, dynamically renders buyer payment detail fields
   (per the ad's method type) and validates before submission.

6. **`lib/screens/vendor_ad_creator.dart`:** Replaced old fiat wallet account
   multi-select with single-select TradeAccount picker (only APPROVED shown).
   Removed "Pricing Strategy (Oracle Linked)" section, replaced with flat 2%
   fee explanation. Sends `tradeAccountId` in ad creation payload.

7. **GHS → USD corrections across 6 screens:**
   - `trades_tab_screen.dart` — trade card amounts
   - `trade_summary_screen.dart` — success header
   - `active_trade_screen.dart` — share text + amount display
   - `vendor_trade_execution.dart` — row labels + default currency
   - `vendor_ad_card.dart` — rate row shows ad type + method (not GHS rate)
   - `ad_detail_flip_card.dart` — detail rows show $ limits, ad type

8. **Navigation wiring:**
   - `settings_screen.dart` — new "Trade Accounts" tile in Payment section
   - `vendor_dashboard.dart` — new "MANAGE TRADE ACCOUNTS" button

9. **`lib/models/ad.dart`:** Added `adType`, `tradeAccountId`, `terms`,
   `isSellAd`/`isBuyAd` getters.

**No backend code change.** Purely consumes the Phase F2 BE endpoints (PR #66).

Files (15 + 2 docs): `lib/services/trade_account_service.dart` (NEW),
`lib/providers/trade_account_provider.dart` (NEW),
`lib/screens/trade_accounts_screen.dart` (NEW),
`lib/providers/marketplace_provider.dart`,
`lib/models/ad.dart`,
`lib/screens/p2p/p2p_marketplace_screen.dart`,
`lib/screens/vendor_ad_creator.dart`,
`lib/screens/vendor_dashboard.dart`,
`lib/screens/settings_screen.dart`,
`lib/screens/trades_tab_screen.dart`,
`lib/screens/trade_summary_screen.dart`,
`lib/screens/active_trade_screen.dart`,
`lib/screens/vendor_trade_execution.dart`,
`lib/widgets/vendor_ad_card.dart`,
`lib/widgets/ad_detail_flip_card.dart`.
Plus `FRONTEND_AUDIT.md` + `AZAMAN_MASTER_SOUL.md`.

---

### Phase E2-FE — AZM Spend UI (2026-05-25, in review, FE)

**Frontend companion to BE PR #63 (Phase E2).** Adds the AZM spend UI:
fee-discount selector on the withdrawal screen, ad-boost purchase sheet on
the vendor dashboard, and real-time `azm_spend` socket listener.

**What this PR does:**

1. **New `lib/services/azm_spend_service.dart`:** HTTP client for `/api/azm/spend/*`
   endpoints (options, fee-discount, ad-boost, history). Models: `FeeDiscountTier`,
   `AdBoostOption`, `AzmSpendOptions`, `FeeDiscountResult`, `AdBoostResult`,
   `AzmSpendEntry`.

2. **New `lib/providers/azm_spend_provider.dart`:** Riverpod StateNotifier with
   spend options state, `applyFeeDiscount()`, `boostAd()`, and real-time spend
   injection via socket. Supports: `primeIfNeeded()`, `refresh()`, `onRealtimeSpend()`.

3. **`lib/screens/withdrawal_screen.dart`:** New "USE AZM TO REDUCE FEE" selector
   section below the exit-fee preview (MoMo mode only). Shows tier chips (25% Off /
   50% Off / Free) with AZM cost and affordability state. Selecting a tier updates
   the fee preview in real-time (strikethrough original + green discounted amount).
   On submission, the selected tier's AZM is debited via `POST /azm/spend/fee-discount`
   before the withdrawal fires — if the debit fails, the withdrawal proceeds at
   standard fee with a warning snackbar.

4. **`lib/screens/vendor_dashboard.dart`:** New "BOOST AD" button on every active
   ad card. Tapping opens `_AdBoostSheet` — a bottom sheet showing three boost
   durations (24h / 3 days / 7 days) with AZM costs, affordability badges, and a
   "CONFIRM BOOST" CTA. On success, the ad list refreshes to show a green "BOOSTED"
   badge with countdown. Already-boosted ads show an "EXTEND" button to stack
   additional time.

5. **`lib/services/socket_service.dart`:** New `azm_spend` event listener in both
   WidgetRef and plain-Ref variants. Updates `balanceDataProvider.azmBalance` on
   spend events and fires `_onAzmSpend` callback for provider notification.
   New `onAzmSpend()` registration method on `SocketService`.

**No backend code change.** Purely consumes the Phase E2 BE endpoints (PR #63).

Files (5 + 2 docs): `lib/services/azm_spend_service.dart` (NEW),
`lib/providers/azm_spend_provider.dart` (NEW),
`lib/screens/withdrawal_screen.dart`, `lib/screens/vendor_dashboard.dart`,
`lib/services/socket_service.dart`.
Plus `FRONTEND_AUDIT.md` + `AZAMAN_MASTER_SOUL.md`.

---

### Phase E1-FE — AZM Earn UI (2026-05-25, in review, FE)

**Frontend companion to BE PR #62 (Phase E1).** Adds the AZM rewards screen,
real-time socket listener, and navigation from the hologram card.

**What this PR does:**

1. **New `lib/services/azm_reward_service.dart`:** HTTP client for `/api/azm/*`
   endpoints (history, summary, rates). Models: `AzmRewardEntry`, `AzmSummary`,
   `AzmRates`, `AzmSourceStats`.

2. **New `lib/providers/azm_reward_provider.dart`:** Riverpod StateNotifier with
   paginated history, summary, rates, real-time reward injection via socket.
   Supports: `primeIfNeeded()`, `refresh()`, `loadMore()`, `onRealtimeReward()`.

3. **New `lib/screens/azm_rewards_screen.dart`:** Full-page AZM rewards view:
   - Summary card (current balance, total earned, transaction count)
   - Collapsible "How to Earn AZM" guide (live rates from backend)
   - Infinite-scroll history list grouped by date with source icons
   - Pull-to-refresh + skeleton loading states

4. **`lib/services/socket_service.dart`:** New `azm_reward` event listener
   updates `balanceDataProvider.azmBalance` in real-time + fires callback for
   provider notification. Both WidgetRef and plain Ref variants wired.

5. **`lib/widgets/hologram_balance_card.dart`:** AZM chip is now tappable —
   navigates to AzmRewardsScreen. Shows AZM value without `$` prefix (it's
   loyalty points, not USD). Added chevron indicator on tappable chip.

**No backend code change.** Purely consumes the Phase E1 BE endpoints.

Files (5 + 2 docs): `lib/services/azm_reward_service.dart` (NEW),
`lib/providers/azm_reward_provider.dart` (NEW),
`lib/screens/azm_rewards_screen.dart` (NEW),
`lib/services/socket_service.dart`, `lib/widgets/hologram_balance_card.dart`.
Plus `FRONTEND_AUDIT.md` + `AZAMAN_MASTER_SOUL.md`.

---

### Phase D-3 — AZM architecture correction (2026-05-25, docs only, FE)

**CRITICAL ARCHITECTURE CORRECTION.** Phase D-2 (BE PR #59) incorrectly
deleted the `azmBalance` column. FE PR #48 (which would have removed all
FE references) was never merged — the FE code is already correct.

**Action:** Close/abandon FE PR #48. Do NOT merge it. The existing FE code
that reads `azmBalance` from the backend API is correct and must stay.

**BE companion:** Phase D-3 (BE) restores the column. Once merged, the
FE's existing `toDouble(json['azmBalance'])` parsing works as-is.

**AZM design (corrected):** AZM = independent loyalty-point ledger, NOT a
derived UI label. Earn: trade completions, referrals, login streaks,
achievements. Spend: fee discounts, premium ad-tier unlocks, boosted visibility.

---

### Phase H4 — Connectivity banner (2026-05-25, in review)

Branch: `phase-h4-connectivity-banner`. Frontend-only PR. Closes the
audit's H / H2 deferred line: *"`connectivity_plus` banner — needs
adding the package + native config."* Phase H shipped the haptic
vocabulary + page transitions + skeleton loaders; H2/H3 wired
slide-to-confirm + biometric. H4 is the missing piece — the app now
*knows* when it's offline and surfaces it premium-style instead of
spinning forever on a dead network.

**What ships:**

1. **`pubspec.yaml`** — adds `connectivity_plus: ^6.1.0`. No native
   config required (the iOS `Info.plist` and Android manifest already
   declare the network entitlement for the existing http +
   socket_io_client traffic).

2. **`lib/services/connectivity_service.dart`** (NEW, ~70 LOC).
   Wraps `Connectivity().onConnectivityChanged` into a Riverpod
   `StreamProvider<bool>` that emits `true` when any interface is up
   (wifi / mobile / ethernet / vpn / bluetooth / other) and `false`
   when fully offline. Initial state seeded by `checkConnectivity()`
   so the banner doesn't flash at cold-launch. Fail-open on probe
   error so a transient connectivity_plus glitch doesn't strand the
   user behind a permanent banner. Companion `isOnlineProvider`
   exposes a synchronous bool for retry-button gating in callsites.

3. **`lib/widgets/azaman_connectivity_banner.dart`** (NEW, ~150 LOC).
   Slide-down strip that overlays every screen via a `Stack`, so
   screens never reflow when connectivity flips (no jolt every time
   you walk through a tunnel). Shows a danger-coloured *"You are
   offline — Showing your last loaded data. Some actions are paused."*
   card on disconnect. On reconnect, briefly flashes a success-green
   *"Reconnected"* tick for ~1.4s, then slides back up. Tied into
   `AzamanHaptics.warn()` on disconnect and `AzamanHaptics.confirm()`
   on reconnect — same vocabulary the rest of the app speaks since
   Phase H. First emission seeds `_lastKnownOnline` without firing a
   banner, so the banner doesn't ping the user with "Reconnected" the
   moment the app launches in a perfectly normal online state.

4. **`lib/main.dart`** — wires the banner into
   `MaterialApp.router(builder:)` so it overlays every routed screen
   with one mount. Zero per-screen migration. The Phase H
   `AnnotatedRegion<SystemUiOverlayStyle>` wrapper stays outside so
   the banner sits inside the themed status-bar overlay correctly.

**What this catches.** Radio-state changes — phone disconnects from
wifi, drops onto mobile data, enters airplane mode, leaves a tunnel,
etc. The banner reacts within the OS-reported event (~immediate on
iOS, ~1-2s on Android).

**What this does NOT catch (deliberate scope).** *"Wifi connected but
the upstream router has no internet"* (captive portals, home wifi
without WAN, corporate wifi behind a login page). Catching that
requires probing a known endpoint on every state change, which is
its own concern (battery, cost, retry-storm risk if the probe target
is down). If we ever add it, the right place is a follow-up
`internet_probe` service that combines this radio-state stream with
periodic HEAD-pings to `${AppConfig.apiUrl}/health`. Out of scope
here — filed as Phase H5 if it becomes painful in practice.

**Re-test sweep folded in.** Walked the existing socket reconnect
path (Phase G `home_summary_provider.refresh()` + Phase J
`balance_update` handler in `trade_provider`/`socket_service`) — the
banner is presentational only; no socket / API code paths change.
Verified the Phase H `AzamanHaptics.warn()` two-beat heavy haptic on
disconnect is distinct from the `confirm()` medium tap on reconnect
by reading both signatures inline. Verified the Phase B2-FE
`notifications_updated` socket handler is in a separate code path
and unaffected.

**Files (5):**
- `pubspec.yaml` — `connectivity_plus: ^6.1.0`.
- `lib/services/connectivity_service.dart` — NEW.
- `lib/widgets/azaman_connectivity_banner.dart` — NEW.
- `lib/main.dart` — `MaterialApp.router.builder` wraps in banner (~+8 lines).
- `FRONTEND_AUDIT.md` + `AZAMAN_MASTER_SOUL.md` — this entry.

### Phase B2-FE — Multi-device notification sync (FE PR #45, merged 2026-05-25)

Branch: `phase-b2-fe-multi-device-sync`. Frontend-only PR. Closes the
FE half of Phase B2 (BE PR #50, merged 2026-05-25). Two complementary
shippings: a socket handler so the badge stays in sync across multiple
open sessions of the same user, and a "mark all read" affordance the
audit's §5 flagged as missing.

**The gap this PR closes.** BE PR #50 made `markAsRead` and
`markAllAsRead` emit a `notifications_updated` socket event to the
user's room after the DB write. Without a matching FE listener, that
event went into the void: marking a notification read on phone left
the web badge stuck, marking all-read on web left the phone badge
stuck. The "Mark all read" affordance itself didn't exist on the FE
either — `notification_hub_screen` only let users tap items
individually, and on a 50-item backlog that's tedious.

**What ships:**

1. **`lib/providers/notification_provider.dart`** — `_initSocketListener`
   adds a second handler alongside the existing `new_notification` one.
   The new `notifications_updated` handler dispatches on `type`:
   - `MARKED_READ` with `notificationId` → `_applyMarkAsReadLocal(id)`.
   - `MARKED_ALL_READ` with `affected` count → `_applyMarkAllAsReadLocal()`.

   Both helpers are idempotent so the device that initiated the change
   sees its own server-emitted echo as a no-op.

2. **New `markAllAsRead()` method.** Same optimistic-then-server
   pattern as the existing single-item `markAsRead`. Updates local
   state immediately, then PATCH `/notifications/read-all`, then
   returns the affected row count from the server response (or `null`
   on failure so the caller can show a retry banner). The BE then
   echoes `notifications_updated MARKED_ALL_READ` over socket — every
   other open session clears its badge in one round-trip.

3. **Internal helpers `_applyMarkAsReadLocal(id)` and
   `_applyMarkAllAsReadLocal()`.** Pulled out of the previously-inline
   `markAsRead` body so the user-initiated path and the socket-echo
   path share state-mutation logic. Each is idempotent; calling on an
   already-read row is a no-op.

4. **`lib/screens/notification_hub_screen.dart`** — new "Mark all
   read" `AppBar` action that's only rendered when
   `ref.watch(unreadCountProvider) > 0`. Tap fires
   `AzamanHaptics.confirm()` → optimistic mark-all → API call →
   `AzamanHaptics.commit()` on success or a danger snackbar on
   failure. Disabled state during the in-flight call shows a small
   inline progress spinner. Empty-state and populated lists both wrap
   in `RefreshIndicator` (was missing before, so users had no recovery
   path after a transient fetch failure).

5. **Haptic vocabulary applied everywhere.** Tab switches fire
   `AzamanHaptics.toggle()`, notification taps fire
   `AzamanHaptics.nav()`, the mark-all CTA fires `confirm()` then
   `commit()` — same vocabulary the rest of the app speaks since
   Phase H.

**Re-test sweep (per the team rule of always verifying earlier
phases still hold).** Walked through:
- The existing `new_notification` socket listener (Phase 0/F era) →
  unchanged behaviour, still adds new rows to the head of the list
  with `addNotification` dedup-by-id.
- The Phase J `balance_update` socket envelope → unchanged behaviour;
  this PR only touches the notification path.
- The Phase M GoRoute deep-link from a tapped notification (`/trade/:id`,
  `/dispute/:id`) → unchanged; the tap handler in
  `_navigateFromNotification` is intact.
- The Phase G home-screen `unreadCountProvider` consumption (Today
  widget badge) → still reactive; the new socket-echo path correctly
  invalidates the badge on every other device.

No regression risk: the new socket event is purely additive to the BE
side, and the FE listener guards every path with try/catch +
idempotent state mutations.

**FE coordination.** None required. Same backwards-compat posture as
the BE half — older app builds in the wild that don't listen for
`notifications_updated` keep using pull-to-refresh, which still works.

**Files (4):**
- `lib/providers/notification_provider.dart` — socket handler + `markAllAsRead` + helpers (~+90 lines).
- `lib/screens/notification_hub_screen.dart` — `AppBar` action + RefreshIndicator + haptics (~+70 lines, refactor).
- `FRONTEND_AUDIT.md` + `AZAMAN_MASTER_SOUL.md` — this entry.

### Phase M — Wiring + orphan sweep (FE PR #44, merged 2026-05-25)

Branch: `phase-m-orphan-sweep`. Frontend-only PR. Closes the audit's
§13 orphan inventory by deleting 11 confirmed-dead files, wiring 5
orphan screens that had product value, and expanding the GoRouter so
FCM notifications can deep-link to surfaces that previously required
manual navigation through the app.

**Scope philosophy.** The audit asked for "every imperative
`Navigator.push` promoted to a `GoRoute`." Phase M takes a more
surgical interpretation: GoRoute promotion is for **deep linking**,
not all navigation. Sibling-to-sibling navigation inside a feature
(settings → child picker, marketplace → ad detail) stays imperative
because there is no FCM payload that can target an intermediate
screen. Only screens that an FCM `actionPayload`, an external URL,
or a settings deep-link would target need a named route.

**What ships:**

1. **GoRouter expansion (`lib/router/app_router.dart`).** From 4 routes
   to 13. Every deep-linkable surface now has a name:

   | Path | Name | Wired to |
   |---|---|---|
   | `/` | `home` | `SplashScreen` (existing) |
   | `/notifications` | `notifications` | `NotificationHubScreen` (existing) |
   | `/trade/:tradeId` | `trade` | `ActiveTradeScreen` (existing) |
   | `/dispute/:disputeId` | `dispute` | inline `_DisputeScreen` (existing) |
   | `/settings` | `settings` | `SettingsScreen` (NEW) |
   | `/profile/edit` | `profile-edit` | `ProfileDetailsScreen` (NEW, was orphan) |
   | `/account/activity` | `account-activity` | `AccountActivityScreen` (NEW) |
   | `/account/delete` | `account-delete` | `AccountDeactivationScreen` (NEW, was orphan) |
   | `/friends` | `friends` | `FriendsHubScreen` (NEW) |
   | `/messages` | `messages` | `MessagesHubScreen` (NEW, was orphan) |
   | `/referral` | `referral` | `ReferralScreen` (NEW, was orphan) |
   | `/leaderboard` | `leaderboard` | `LeaderboardScreen` (NEW, was orphan) |
   | `/marketplace` | `marketplace` | `P2PMarketplaceScreen` (NEW) |
   | `/savings` | `savings` | `SavingsScreen` (NEW) |

2. **`handleNotificationTap` action vocabulary expanded.** Was
   `OPEN_TRADE` + `OPEN_DISPUTE` only; now also handles `PING_TOPUP`
   (→ `/trade/:id`), `OPEN_FRIEND_REQUEST` / `OPEN_FRIEND_CHAT`
   (→ `/friends`), `VIEW_SAVINGS` (→ `/savings`), `OPEN_AD`
   (→ `/marketplace`). Mirrors the `actionPayload.action` strings the
   BE emits in `notificationService.sendNotification` callsites.
   Unknown actions silently no-op so older clients don't crash on a
   future BE-only rollout.

3. **Orphan screens wired into Settings.** New "Account" section at
   the top of `settings_screen.dart` exposes three previously-
   unreachable screens:
   - **Edit Profile** → `ProfileDetailsScreen` (was orphan).
   - **Refer & Earn** → `ReferralScreen` (was orphan).
   - **Delete Account** → `AccountDeactivationScreen` (was orphan, kept
     at the bottom of the "Other" section next to Sign Out, with
     danger-coloured copy + icon to discourage accidental taps).

4. **11 confirmed-dead orphan files deleted.** Each was confirmed by
   `grep -rln` to have zero inbound imports across the whole `lib/`
   tree:

   | Deleted | Reason |
   |---|---|
   | `account_deactivation.dart` | Duplicate of `account_deactivation_screen.dart` (the wired one) |
   | `admin_spy_screen.dart` | Duplicate of `admin/spy_glass_screen.dart` |
   | `admin_war_room.dart` | Duplicate of `admin_war_room_screen.dart` (the wired one) |
   | `admin_war_room_alerts.dart` | Orphan, no consumers |
   | `chat_screen.dart` | Replaced by `chat/` folder structure |
   | `notification_screen.dart` | Duplicate of `notification_hub_screen.dart` |
   | `signup_screen.dart` (root) | Duplicate of `auth/signup_screen.dart` |
   | `trade_appeal_sheet.dart` | Orphan, no consumers |
   | `user_dashboard.dart` | Dev sandbox file (defines `RealAd` + unused `UserDashboard`); Phase J's edits to it were discarded with the file |
   | `wallet_screen.dart` | Replaced by `HologramBalanceCard` widget |
   | `fiat_wallet_screen.dart` | Orphan, no consumers |

**Out of scope, deferred:**
- **Promoting all 67 `Navigator.push` callsites to GoRoutes.** The
  ones that benefit from deep linking are now in the router. Sibling
  navigation inside a feature is fine staying imperative — promoting
  it would be churn without value.
- **Wiring `LeaderboardScreen` into a UI surface in `vendor_dashboard.dart`.**
  Vendor dashboard has no leaderboard area today; adding one is non-trivial
  UI work outside Phase M's "wire orphans" scope. The `/leaderboard` route
  exists for FCM deep-links + external URLs.
- **Wiring `MessagesHubScreen` into the bottom nav.** The current Chat
  tab routes to `FriendsHubScreen` (which has a chat list inside).
  Adding `MessagesHubScreen` as a 6th tab would conflict; folding it
  into the existing 5-tab structure is a UX redesign outside this PR.
  The `/messages` route exists for FCM deep-links.
- **Removing the AppBar chat icon** (audit §6 P1). Visual change with
  ambiguous tradeoffs — the duplicate-but-faster-access argument cuts
  both ways. Defer to a focused UX PR.

**~280 LOC** across 4 changed files + 11 deletions.

### Phase J — Schema cleanup: drop dead V1 fields (FE PR #43, merged 2026-05-25)

Branch: `phase-j-schema-cleanup`. Frontend-only PR (paired with the
backend `phase-j-schema-cleanup` PR that drops the columns themselves).
Closes the loop on Phase B's audit findings C and D — `User.ghsBalance`
and `User.lockedBalance` were write-dead V1 columns; the FE was reading
both from every JSON envelope and rendering a "$0 in escrow" UI label
that has been zero forever.

**What ships (FE):**

1. **`lib/models/user_model.dart`** — drops both `lockedBalance` and
   `ghsBalance` from the `User` class (constructor, `fromJson`,
   `copyWith`). Comment block above `azmBalance` documents the Phase J
   removal.
2. **`lib/providers/auth_provider.dart`** — `updateBalance` no longer
   accepts `lockedBalance`; callers should pass `escrowLockedBalance`
   (the V2 field).
3. **`lib/providers/hologram_provider.dart`** — `BalanceData` drops
   both fields; `totalLocked` now correctly sums only V2 buckets
   (`escrowLockedBalance + disputeEscrowBalance`). The orphan
   `ghsBalanceProvider` is removed; consumers should use
   `hologramBalanceProvider` (computes `availableBalance × oracleRate`).
4. **`lib/providers/trade_provider.dart`** — socket `balance_update`
   handler no longer reads `lockedBalance`; reads
   `vendorUnallocatedBalance`, `escrowLockedBalance`,
   `disputeEscrowBalance` instead so the V2 ledger split is fully wired.
5. **`lib/services/socket_service.dart`** — both `balance_update`
   handlers (Ref + plain-Ref variants) drop the dead JSON keys.
6. **`lib/screens/auth/login_screen.dart` + `signup_screen.dart`** —
   stop reading `lockedBalance` when constructing the post-login
   `User` object.
7. **`lib/screens/vendor_dashboard.dart`** — `_lockedBalance` field
   renamed to `_escrowLockedBalance` and rebound to the V2 column
   from the `/auth/me/:id` response and the socket envelope. **The
   "LOCKED (IN ESCROW)" UI label now shows real numbers for the first
   time** — it has been bound to the write-dead `lockedBalance` since
   the V2 split, so it has reported $0.00 for every vendor regardless
   of active trade volume.
8. **`lib/screens/vendor_deposit_screen.dart`** — same swap. The
   "X USDT locked in escrow" hint now appears when a vendor has
   active trades.

**Backwards compatibility.** Older app builds in the wild that still
read the dropped JSON keys will get `undefined` and parse defensively
to `0.0` — same value the keys held when they were present, so no
functional regression. The vendor escrow display is the only behaviour
change, and it's a pure improvement (false-zero → true value).

**Out of scope, deferred to Phase J2 (BE):** Float → Decimal column
type rewrite + `CHECK (col >= 0)` constraints on every money column.

Branch: `phase-m-orphan-sweep`. Frontend-only PR. Closes the audit's
§13 orphan inventory by deleting 11 confirmed-dead files, wiring 5
orphan screens that had product value, and expanding the GoRouter so
FCM notifications can deep-link to surfaces that previously required
manual navigation through the app.

**Scope philosophy.** The audit asked for "every imperative
`Navigator.push` promoted to a `GoRoute`." Phase M takes a more
surgical interpretation: GoRoute promotion is for **deep linking**,
not all navigation. Sibling-to-sibling navigation inside a feature
(settings → child picker, marketplace → ad detail) stays imperative
because there is no FCM payload that can target an intermediate
screen. Only screens that an FCM `actionPayload`, an external URL,
or a settings deep-link would target need a named route.

**What ships:**

1. **GoRouter expansion (`lib/router/app_router.dart`).** From 4 routes
   to 13. Every deep-linkable surface now has a name:

   | Path | Name | Wired to |
   |---|---|---|
   | `/` | `home` | `SplashScreen` (existing) |
   | `/notifications` | `notifications` | `NotificationHubScreen` (existing) |
   | `/trade/:tradeId` | `trade` | `ActiveTradeScreen` (existing) |
   | `/dispute/:disputeId` | `dispute` | inline `_DisputeScreen` (existing) |
   | `/settings` | `settings` | `SettingsScreen` (NEW) |
   | `/profile/edit` | `profile-edit` | `ProfileDetailsScreen` (NEW, was orphan) |
   | `/account/activity` | `account-activity` | `AccountActivityScreen` (NEW) |
   | `/account/delete` | `account-delete` | `AccountDeactivationScreen` (NEW, was orphan) |
   | `/friends` | `friends` | `FriendsHubScreen` (NEW) |
   | `/messages` | `messages` | `MessagesHubScreen` (NEW, was orphan) |
   | `/referral` | `referral` | `ReferralScreen` (NEW, was orphan) |
   | `/leaderboard` | `leaderboard` | `LeaderboardScreen` (NEW, was orphan) |
   | `/marketplace` | `marketplace` | `P2PMarketplaceScreen` (NEW) |
   | `/savings` | `savings` | `SavingsScreen` (NEW) |

2. **`handleNotificationTap` action vocabulary expanded.** Was
   `OPEN_TRADE` + `OPEN_DISPUTE` only; now also handles `PING_TOPUP`
   (→ `/trade/:id`), `OPEN_FRIEND_REQUEST` / `OPEN_FRIEND_CHAT`
   (→ `/friends`), `VIEW_SAVINGS` (→ `/savings`), `OPEN_AD`
   (→ `/marketplace`). Mirrors the `actionPayload.action` strings the
   BE emits in `notificationService.sendNotification` callsites.
   Unknown actions silently no-op so older clients don't crash on a
   future BE-only rollout.

3. **Orphan screens wired into Settings.** New "Account" section at
   the top of `settings_screen.dart` exposes three previously-
   unreachable screens:
   - **Edit Profile** → `ProfileDetailsScreen` (was orphan).
   - **Refer & Earn** → `ReferralScreen` (was orphan).
   - **Delete Account** → `AccountDeactivationScreen` (was orphan, kept
     at the bottom of the "Other" section next to Sign Out, with
     danger-coloured copy + icon to discourage accidental taps).

4. **11 confirmed-dead orphan files deleted.** Each was confirmed by
   `grep -rln` to have zero inbound imports across the whole `lib/`
   tree:

   | Deleted | Reason |
   |---|---|
   | `account_deactivation.dart` | Duplicate of `account_deactivation_screen.dart` (the wired one) |
   | `admin_spy_screen.dart` | Duplicate of `admin/spy_glass_screen.dart` |
   | `admin_war_room.dart` | Duplicate of `admin_war_room_screen.dart` (the wired one) |
   | `admin_war_room_alerts.dart` | Orphan, no consumers |
   | `chat_screen.dart` | Replaced by `chat/` folder structure |
   | `notification_screen.dart` | Duplicate of `notification_hub_screen.dart` |
   | `signup_screen.dart` (root) | Duplicate of `auth/signup_screen.dart` |
   | `trade_appeal_sheet.dart` | Orphan, no consumers |
   | `user_dashboard.dart` | Dev sandbox file (defines `RealAd` + unused `UserDashboard`) |
   | `wallet_screen.dart` | Replaced by `HologramBalanceCard` widget |
   | `fiat_wallet_screen.dart` | Orphan, no consumers |

**Out of scope, deferred:**
- **Promoting all 67 `Navigator.push` callsites to GoRoutes.** The
  ones that benefit from deep linking are now in the router. Sibling
  navigation inside a feature is fine staying imperative — promoting
  it would be churn without value.
- **Wiring `LeaderboardScreen` into a UI surface in `vendor_dashboard.dart`.**
  Vendor dashboard has no leaderboard area today; adding one is non-trivial
  UI work outside Phase M's "wire orphans" scope. The `/leaderboard` route
  exists for FCM deep-links + external URLs.
- **Wiring `MessagesHubScreen` into the bottom nav.** The current Chat
  tab routes to `FriendsHubScreen` (which has a chat list inside).
  Adding `MessagesHubScreen` as a 6th tab would conflict; folding it
  into the existing 5-tab structure is a UX redesign outside this PR.
  The `/messages` route exists for FCM deep-links.
- **Removing the AppBar chat icon** (audit §6 P1). Visual change with
  ambiguous tradeoffs — the duplicate-but-faster-access argument cuts
  both ways. Defer to a focused UX PR.

**~280 LOC** across 4 changed files + 11 deletions.

### Phase H3 — Biometric pre-gate + slide-to-confirm completion (2026-05-25, in review)

Branch: `phase-h3-biometric-confirm`. Frontend-only. Stacked on Phase H2 (now
merged on main via PR #41). Closes the "out of scope, deferred" line of the
Phase H2 changelog: the vendor's Release-crypto button on
`vendor_trade_execution.dart`, plus the biometric prompt before every existing
slide-to-confirm fires.

**Three things shipped:**

1. **The vendor's Release-crypto AlertDialog → slide-to-confirm bottom sheet.**
   The previous `_handleReleaseCrypto` showed an `AlertDialog` with a Cancel
   button and a "Confirm & Release" `ElevatedButton`. A reflex tap fires the
   release. Replaced with a richer `_ReleaseCryptoSheet` showing the typed
   crypto amount being released, the fiat amount the buyer paid, the payment
   method, and a final "do not release based on screenshots alone" warning.
   The confirm is a slide gesture (90% drag threshold), not a tap. The slide
   is biometric-gated when the user has enabled the lock in Security Settings.

2. **`AzamanBiometricGate` — opt-in biometric pre-gate.** `lib/utils/biometric_gate.dart`.
   Wraps any callback so it runs only after `BiometricService.authenticate()`
   succeeds, but only when the user has flipped the toggle in Settings — when
   the toggle is off the gate is a no-op. Wired into every existing
   `SlideToConfirm.onConfirmed`: vendor release, withdrawal (mobile-money +
   crypto), savings goal fund/withdraw, friends-transfer send/request, and
   the buyer's "I HAVE PAID" flow on `upload_proof.dart` (which was also
   upgraded from `ElevatedButton` to `SlideToConfirm` in this PR for
   consistency). Each callsite passes a tailored `reason:` string that lands
   in the system biometric prompt: "Authenticate to release crypto",
   "Authenticate to send mobile money", "Authenticate to fund Vacation",
   "Authenticate to send funds", "Authenticate to mark trade as paid".

3. **"Biometric Lock" toggle in `security_settings.dart`.** New card under
   Two-Factor and PIN. Toggle is itself biometric-gated in **both directions**
   — turning ON requires `authenticate()` to prove ownership, turning OFF
   also requires it. This is the security-critical detail: a thief with an
   already-unlocked phone shouldn't be able to disable the lock and drain
   funds. The card is disabled (Switch greyed, `onChanged: null`) on devices
   that have no biometrics enrolled.

**Review-pass fixes folded in same PR (post-first-push, three rounds of
semantic review):**

- `_processApiRelease` no longer calls `Navigator.pop(context)` three times.
  The pops were aimed at the old `AlertDialog`; with the dialog gone they
  ate `VendorTradeExecution` instead, collapsing the back-stack to
  `[TradeSummaryScreen]` on success and bouncing the vendor off the trade
  screen on transient backend errors. Now the success path goes straight to
  `pushReplacement(TradeSummaryScreen)` and the error paths just snackbar.
- `_ReleaseCryptoSheet` was reading `tradeData['amountFiat']` /
  `['amountCrypto']` which the backend's `new_trade_request` socket emit
  doesn't carry — vendors entering the screen via the dashboard's NEW-trade
  card saw `Releasing 0.00 USDT` on the highest-stakes confirm in the app.
  Fixed in two places: `vendor_dashboard.dart` now forwards the typed fields
  on both REST and socket paths, and `_fetchLiveTradeDetails` mutates
  `widget.tradeData` from the trade-details REST sync to backfill the
  socket-fed entry path.
- `BiometricService.authenticate()` was hard-coding `localizedReason` —
  every callsite was passing tailored copy that never reached `local_auth`.
  The signature is now `authenticate({String? reason})` and pipes through.
- `SlideToConfirm` previously committed to `_confirmed = true` the moment a
  swipe completed, with no way to re-arm the thumb after a callback that
  short-circuited or after a biometric-cancel. Three converging fixes:
  - New `enabled` prop rejects drags up front (mirrors `onPressed: null`
    semantics — used by `upload_proof` to refuse the slide before an image
    is selected).
  - `didUpdateWidget` re-arms on the `isLoading: true → false` and
    `enabled: false → true` edges so the natural async lifecycle of the
    parent's submit flag heals the slider.
  - Public `SlideToConfirmState` (was private) so every gated callsite can
    hold a `GlobalKey<SlideToConfirmState>` and explicitly reset on the
    gate's failure path. `AzamanBiometricGate.run/runSync` accept an
    `onCancelled` callback that fires `slideKey.currentState?.reset()`.
- The heavy `AzamanHaptics.commit()` haptic was firing the moment the slide
  completed, before the gate resolved. A cancelled biometric auth fired a
  phantom "transaction sent" buzz. Moved inside the gated action body so it
  only fires when the action actually runs.
- `BiometricService.isAvailable` was `canCheckBiometrics || isDeviceSupported()`
  which admits passcode-only devices — but the settings card title says
  "Biometric on financial actions". Tightened to `&&` so only devices with
  at least one biometric enrolled can toggle the feature on. Once enrolled,
  the auth prompt itself still allows passcode fallback (`biometricOnly:
  false`), so users who later remove all enrolled biometrics aren't locked
  out of every financial action.

**Files in this PR:**

- `lib/utils/biometric_gate.dart` — NEW. The opt-in pre-gate helper.
- `lib/services/biometric_service.dart` — `isAvailable` tightened,
  `authenticate({reason})` parameter added.
- `lib/widgets/slide_to_confirm.dart` — `enabled` prop, public
  `SlideToConfirmState`, `didUpdateWidget` re-arming, dimmed visual when
  disabled.
- `lib/screens/vendor_trade_execution.dart` — `AlertDialog` → bottom-sheet
  + `_ReleaseCryptoSheet` + `_SummaryRow`. `_processApiRelease` Navigator
  cleanup. `_fetchLiveTradeDetails` backfills typed amount fields onto
  `widget.tradeData`.
- `lib/screens/vendor_dashboard.dart` — REST and socket paths forward
  `amountFiat` / `amountCrypto` / `crypto` / `currency` / `paymentMethod`
  on the `tradeData` map.
- `lib/screens/upload_proof.dart` — `ElevatedButton` "I HAVE PAID" replaced
  with `SlideToConfirm` + biometric gate. `enabled: _imageFile != null
  && !_isUploading`.
- `lib/screens/withdrawal_screen.dart` — `SlideToConfirm.onConfirmed`
  wrapped in `AzamanBiometricGate.runSync`. `commit()` haptic moved inside
  gated action.
- `lib/widgets/savings_goal_sheet.dart` — same wrap pattern; same `commit()`
  fix.
- `lib/screens/friends/transfer_modal.dart` — same wrap pattern; gates both
  send and request flows.
- `lib/screens/security_settings.dart` — new "Biometric Lock" card.
  `_onToggleBiometric` gates both ON and OFF behind `authenticate()`.
  `_toggleRow.onChanged` widened to `ValueChanged<bool>?` so the Switch
  visually disables on devices without biometric support.

**Out of scope, deferred:**

- Slide-to-confirm on the in-chat transfer modal (`chat_transfer_modal`).
  Same biometric_gate hook applies; touched in a smaller follow-up.
- Wiring biometric pre-gate onto the dispute-open flow (low frequency,
  lower priority).
- Replacing the existing PIN auth path with the biometric gate. PIN is its
  own auth model and the user might want both.
- Any backend coordination for the eventually-want fields `crypto` /
  `currency` in the `getTradeDetails` REST response — today both default
  to `'USDT'` / `'GHS'` via the schema, so the frontend's fallback is
  correct, but a future multi-currency rollout will need both.

### Phase H2 — Slide-to-Confirm on Financial Actions (2026-05-24, in review)

Branch: `phase-h2-slide-to-confirm`. Wires the existing `SlideToConfirm`
widget into the highest-risk financial confirms. Stacked on Phase H.
Frontend-only.

The Phase H audit roadmap line scoped this for a follow-up: "Apply
`slide_to_confirm` + biometric to every financial confirm (withdraw,
send, complete trade, fund savings)". Phase H2 ships **2 of the 4**
in this PR; the remaining two (active-trade complete-trade button,
TransferModal — already wired prior, verified intact) ship as either
no-op or a separate H3.

**Wired in this PR:**

- `lib/screens/withdrawal_screen.dart` — replaces the legacy
  `ElevatedButton(child: 'CONFIRM MOBILE MONEY WITHDRAWAL' / 'CONFIRM WITHDRAWAL')`
  with `SlideToConfirm`. Disabled state preserved: when `canSubmit`
  is false (form incomplete) or `_isSubmitting` is true, we render a
  static disabled ElevatedButton that explains *what to fill in* or
  shows a spinner respectively. Once the form is valid, the swipe
  affordance appears. The swipe routes through the existing `_submit()`
  so all validation, balance double-checks, and network calls fire
  unchanged. `AzamanHaptics.commit()` fires at the moment value moves.
- `lib/widgets/savings_goal_sheet.dart` (`_AmountPromptSheet` inside) —
  replaces the legacy `ElevatedButton(onPressed: _submit)` for fund /
  withdraw amount confirmations with `SlideToConfirm`. The CTA color
  and label propagate from the parent sheet (Fund = success-green
  "Slide to fund", Withdraw = warning-yellow "Slide to withdraw"). Same
  `_submit()` routing — validation untouched.

**Already wired (verified intact):**

- `lib/screens/friends/transfer_modal.dart` — peer transfer between
  friends. Uses `SlideToConfirm` with `_executeTransfer` since prior
  Phase B work. No changes.

**Out of scope, deferred:**

- `active_trade_screen.dart` — the vendor "Release crypto / Complete
  trade" CTA. Larger surface (~1500 LOC screen with multi-state
  affordances and timer pill); needs its own focused PR to do justice.
- Biometric prompt before slide-to-confirm fires. `local_auth` is
  already in pubspec and `biometric_service.dart` exists. Phase H3
  scope.

**Files in this PR:**

- `lib/screens/withdrawal_screen.dart` — slide widget swap. ~+50 LOC.
- `lib/widgets/savings_goal_sheet.dart` — slide widget swap. ~+15 LOC.
- `FRONTEND_AUDIT.md` — this changelog.
- `AZAMAN_MASTER_SOUL.md` — Phase H2 entry.

### Phase H — Premium Polish Pass (2026-05-24, in review)

Branch: `phase-h-premium-polish`. Cross-cutting polish layer that adopts a
consistent visual + tactile language across every existing surface. Stacked
on Phase G. Frontend-only — no backend changes.

> **Review-pass fixes folded in (2026-05-24).** A manual code-review pass
> after Phase H's first push surfaced six real bugs in F+G+H code; rather
> than open three rebased fix-PRs, the patches were folded into this Phase
> H commit so the merged tip of the stack ships clean. Reviewers comparing
> Phase F or Phase G in isolation will see the original bugs; the merged
> end-state is the corrected code.
>
> | # | Phase | Severity | Bug | Fix |
> |---|-------|----------|-----|-----|
> | a | F | RUNTIME | `ThemeProvider` clobbered Flutter framework's `dispatcher.onPlatformBrightnessChanged` setter — broke `MediaQuery.platformBrightness` for every other observer. | Refactored to `WidgetsBindingObserver` + `didChangePlatformBrightness()`. Removed the dispatcher mutation. |
> | b | F | RUNTIME | SSO success snackbar fired BEFORE `Navigator.pushReplacement` in both login + signup → toast posted on a disposing ScaffoldMessenger, never seen by the user. | Flipped the order so the toast lands on the destination MainNavigationWrapper's messenger. |
> | c | G | RUNTIME | `home_summary_service` read trade JSON keys (`amountGhs`, `amountUsdc`) that don't exist on the backend's Prisma `Trade` model. The actual fields are `amountFiat` and `amountCrypto`. | Read the correct keys; Dart-side field names retained for API stability. |
> | d | G | RUNTIME | `_activeStatuses` listed `AWAITING_RELEASE` (not in the `TradeStatus` enum) and missed `PENDING` (the freshest status — fresh trades were invisible on home until they transitioned). | Replaced with `{PENDING, PENDING_PAYMENT, PAID, DISPUTED}` matching the schema enum. |
> | e | G | RUNTIME | `live_market_section.build()` mutated `rateHistoryProvider` mid-build via `Future.microtask`. Trips Riverpod debug asserts and produces a flicker frame on hot reload. | Moved the rate-history append into `HomeSummaryNotifier.refresh()` after `state = fresh`. `LiveMarketSection` is now `ConsumerWidget` again. `RateObservation` exposed (was `_RateObservation`). |
> | f | G | POLISH | `WithdrawalSummary.currency` read a JSON key the backend doesn't emit. | Replaced with `payoutMethod` + `network` (the actual columns on `Withdrawal`). |
>
> Smaller polish folded in same commit: dropped orphan `flutter/services.dart`
> imports in three files (every `HapticFeedback.*` is now `AzamanHaptics.*`),
> fixed the theme-picker's hairline-divider collapse on the System tile,
> updated the stale "4-tab layout" comment in `main.dart` to "5-tab".

The audit's §11 listed seven "premium fintech apps consistently do that
Azaman doesn't" items. Phase H ships five of them; the remaining two
(custom font + slide_to_confirm everywhere) are scoped to a follow-up
H2 PR because they require asset-pipeline work and screen-by-screen
adoption that doesn't fit this PR's footprint.

**1. Custom page transitions (global).**
New `lib/utils/azaman_page_transitions.dart` — `AzamanPageTransitionsBuilder`
that does an iOS-style slide+fade (240ms, easeOutCubic, 6% horizontal slide
in / 4% out, 8% dim on the page being covered). Wired into `ThemeData.pageTransitionsTheme`
in `theme_provider.dart` so every existing `Navigator.push(MaterialPageRoute(...))`
across the app picks it up automatically — zero per-screen migration.

**2. Status-bar + system-nav-bar style synced to the active theme.**
`AzamanApp` now wraps its `MaterialApp.router` in `AnnotatedRegion<SystemUiOverlayStyle>`
that flips status-bar icon brightness + system-nav-bar color whenever the
active palette is dark vs light. Closes the audit §11 bug — switching to
a light theme used to leave a white status bar with white icons (invisible).

**3. Haptic vocabulary.**
New `lib/utils/azaman_haptics.dart` — five named patterns:

   * `AzamanHaptics.nav()`     — light tap, every navigation push / row tile
   * `AzamanHaptics.toggle()`  — selection click, switches/picker pulls
   * `AzamanHaptics.confirm()` — medium impact, primary CTA / submit
   * `AzamanHaptics.commit()`  — heavy impact, final commit on financial action
   * `AzamanHaptics.warn()`    — heavy double-pulse, danger confirm

Replaces ad-hoc `HapticFeedback.lightImpact()` calls in `home_screen.dart`,
`theme_picker_screen.dart`, `settings_screen.dart`. Also gives us a single
hook for the future "respect Settings.haptics off" toggle (audit §12 P2).

**4. Skeleton loaders on the home cold-load path.**
`SkeletonBlock` already existed (orphan, used in zero screens — audit §9
P1 called this out specifically). Phase H wires it into:

   * `TodayWidget` — the 4-tile grid renders 4 skeleton blocks during the
     initial `homeSummaryProvider.refresh()` before any data is back.
   * `LiveMarketSection._GhsHeroCard` — skeletons the rate value AND the
     sparkline space until `/api/oracle/rates` returns. Once data is
     present, real values fade in via the existing `AnimatedSwitcher`.

Loading-then-refresh keeps the previous snapshot visible (no flicker)
because `HomeSummaryNotifier.refresh()` only flips the `loading` flag,
leaving the displayed counters stable. Skeletons only appear on a true
cold start.

**5. Bottom-sheet confirmation pattern.**
New `lib/widgets/azaman_confirm_sheet.dart` — `AzamanConfirmSheet.show(...)`
returns `bool?` matching the legacy `showDialog<bool>` contract, so
existing call sites swap one line. Settings sign-out is the first
adopter; Phase H2 will sweep the remaining `AlertDialog` confirms across
the app.

**6. PageTransitionsTheme covers all 6 platforms** (Android, iOS, Fuchsia,
Linux, macOS, Windows) — explicit per-platform entries so desktop
targets behave identically to mobile.

**Files in this PR:**

- `lib/utils/azaman_haptics.dart` — NEW. ~75 LOC.
- `lib/utils/azaman_page_transitions.dart` — NEW. ~80 LOC.
- `lib/widgets/azaman_confirm_sheet.dart` — NEW. ~190 LOC.
- `lib/providers/theme_provider.dart` — wires `pageTransitionsTheme`. ~+15 LOC.
- `lib/main.dart` — wraps `MaterialApp.router` in `AnnotatedRegion`. ~+25 LOC.
- `lib/widgets/today_widget.dart` — cold-load skeleton + Haptics adoption. ~+50 LOC.
- `lib/widgets/live_market_section.dart` — skeleton on rate + sparkline cold-load. ~+30 LOC.
- `lib/screens/home_screen.dart` — Haptics adoption (5 callsites). Trivial.
- `lib/screens/theme_picker_screen.dart` — Haptics adoption (2 callsites). Trivial.
- `lib/screens/settings_screen.dart` — Haptics adoption + bottom-sheet sign-out. ~+10 LOC delta.

**Out of scope, deferred to Phase H2:**

- `slide_to_confirm` + biometric on every financial action (withdraw, send,
  fund savings, complete trade). Existing `SlideToConfirm` widget is in
  `lib/widgets/slide_to_confirm.dart`; H2 wires it into the four screens.
- Custom font (Inter / Manrope / SF Pro) — needs `.ttf` binaries committed
  and `pubspec.yaml > fonts:` block. Separate small PR.
- `connectivity_plus` banner — needs adding the package + native config. Also
  separate.
- Skeleton loaders on the remaining list screens (friends, trades, marketplace,
  chat). High value but ~200 LOC each — Phase H2 can split per-screen.
- The audit's "prefer bottom sheets over AlertDialog" sweep across all the
  other confirm dialogs scattered through the app — H2 sweep with grep.

### Phase G — Home Overhaul (2026-05-24, in review)

Branch: `phase-g-home-overhaul`. Closes the second-most visible "static
brochure" surface in the app (the home screen) and replaces it with a
dynamic morning-coffee dashboard. Frontend-only — no backend code changes.

**1. settings_screen→home_screen continuity:** the Phase F section header
typography and row-tile aesthetic now extends to home, so the app reads
as one coherent surface from top to bottom.

**2. New `TodayWidget` (replaces hardcoded Platform News).**
2x2 grid of stat tiles, each tappable:

- *Active Trades* → `TradesTabScreen`
- *Pending Withdrawals* → in-place bottom sheet listing the recent pending
  rows (no dedicated history screen exists yet; sheet is enough surface
  until Phase M wires `withdrawal_screen.dart`).
- *Friend Requests* → `FriendsHubScreen`
- *Unread Notifications* → `/notifications` GoRoute (so FCM deep-links
  hit the same destination).

Counters animate via `AnimatedSwitcher` so a refresh feels alive. Per-section
fetch failures degrade to `—` rather than blocking the whole render.

**3. New `LiveMarketSection` (replaces hardcoded Core Assets).**
Was: AZM/USDT/GHS rows pegged at $1.00 forever (the user's audit §7 P0).
Now:

- A USD->GHS hero card with the live oracle rate from `GET /api/oracle/rates`,
  source attribution ("KOTANI PAY · updated 4m ago"), and a 24-sample
  in-memory sparkline rendered via `fl_chart`. The sparkline only paints
  once we have ≥2 distinct observations — backend has no historical-rate
  endpoint yet, so this is a rolling client-side window. Drop-in upgrade
  to `/api/oracle/history` once that ships.
- Three stable-peg rows (USDC / USDT / AZM) at $1.00 with badge labels.
  We don't fake price movement — the hologram model is 1:1 USDC for
  everything that isn't local fiat.

**4. New aggregator `lib/services/home_summary_service.dart`.**
Five concurrent fetches via `Future.wait`:

- `GET /api/oracle/rates`
- `GET /api/trades/history` filtered to active statuses
  (PENDING_PAYMENT, PAID, AWAITING_RELEASE, DISPUTED)
- `GET /api/wallet/history` filtered to PENDING
- `GET /api/friends/requests?page=1&limit=20`
- `GET /api/notifications/unread-count`

Each request is wrapped so a single failure doesn't torch the whole snapshot.
Per-section error messages bubble up as `*Error` fields on the `HomeSummary`
value object.

**5. New Riverpod surface `homeSummaryProvider`** (`StateNotifierProvider<HomeSummaryNotifier, HomeSummary>`).
First-mount auto-prime so the home renders real data without the user
having to swipe down. Refresh keeps the previous snapshot visible while
loading (only the `loading` flag flips), so the UI doesn't blink.

**6. Pull-to-refresh now actually refreshes.** Was: `await Future.delayed(const Duration(seconds: 1))` — literally a sleep. Now:

- `homeSummaryProvider.refresh()` re-fetches all five sections in parallel.
- `authProvider.fetchUserDetails()` re-hydrates the canonical /auth/me/:id
  response (best-effort, fired without await).
- The hologram balance auto-updates via the existing socket.io
  `balance_update` event channel — no extra fetch needed there.

**7. Animated balance counter.** Was already in place inside
`HologramBalanceCard` via `TweenAnimationBuilder` + `AnimatedSwitcher` —
verified untouched. The audit's call for `animated_flip_counter` is
already satisfied by the custom implementation; saved a dependency.

**8. Platform News removed.** Was hardcoded mock data ("Azaman v4.0 — Hologram Balance is Live", "Just now", etc.) with no backend endpoint and stale dates on every cold start. The audit's roadmap §G says "remove until ready" — done. Re-add when a real `/api/news` endpoint ships.

**Files in this PR:**

- `lib/services/home_summary_service.dart` — NEW. ~370 LOC.
  `HomeSummary` value object + `HomeSummaryService.fetch()` aggregator.
- `lib/providers/home_summary_provider.dart` — NEW. ~55 LOC.
  `HomeSummaryNotifier` state notifier with `primeIfNeeded()` + `refresh()`.
- `lib/widgets/today_widget.dart` — NEW. ~325 LOC.
  4-tile dashboard grid + pending-withdrawals bottom sheet.
- `lib/widgets/live_market_section.dart` — NEW. ~395 LOC.
  USD->GHS hero with sparkline + stable-peg rows + in-memory rate history.
- `lib/screens/home_screen.dart` — REWRITE. ~225 LOC.
  ConsumerWidget → ConsumerStatefulWidget for `initState` priming.
  Removed hardcoded Core Assets and Platform News blocks.
  Real `_onRefresh` that fans out summary + balance refetch.

**Out of scope, deferred:**

- A real `/api/news` endpoint (Phase L+ when backend has news to ship).
- A historical-rate endpoint (Phase L+, blocking richer sparkline backfill).
- Migrating `WithdrawalScreen` into a proper `WithdrawalHistoryScreen`
  child page rather than a bottom sheet (Phase M, orphan-sweep).
- Dedicated DM unread-count tile (folded into "Unread" alongside notifications
  for now; Phase M can split when the messages hub is wired).

### Phase F — Settings Overhaul (2026-05-24, in review)

Branch: `phase-f-settings-overhaul`. Closes the **original user-stated UI
pain point**: "Just look at the actual settings page. The themes are listed
there and it's not proper." Phase 0 patched the grid layout (3-col swatch
stripe). Phase F is the structural fix.

**1. settings_screen rewrite — Apple/Binance row layout.**
Six sections (Appearance / Notifications / Preferences / Security & Privacy
/ Payment / Other), each rendered as a rounded `_Card` of `_NavRow` /
`_ToggleRow` tiles separated by indent-aligned `_Divider`s. Replaces the
old vertical mish-mash where toggles, dropdowns, and an inline 11-tile
theme grid all coexisted in one ListView. Currency / Language dropdowns
are now iOS-style bottom-sheet pickers — the previous `DropdownButton`
inside a row was a layout fight on small phones.

**2. ThemePickerScreen (new child screen).**
Pulled the picker out of the main settings list. Full-page screen with:

- A *live home preview* card at the top — a miniature hologram balance
  card + quick-actions row painted in the *currently selected* theme, so
  taps in the grid below repaint it before the user navigates back.
- A dedicated "Auto" row at the top for the new system-follow option,
  with a two-tone swatch (light + dark accents) so users see at a glance
  what it'll do.
- The 11 explicit themes in the same Phase 0 swatch-stripe / icon / name
  tile aesthetic, 3-col grid, aspect 0.95.

**3. AzamanTheme.system (12th option).**
Added at the **end** of the enum so existing `SharedPreferences` indices
for already-installed users do not shift. ThemeProvider subscribes to
`onPlatformBrightnessChanged` and resolves `.system` to dark/light at
read-time. Static `getColors(.system)` resolves via
`WidgetsBinding.instance.platformDispatcher.platformBrightness` so callers
without a provider instance still get a sensible answer. Switching to
.system, then flipping the OS dark/light toggle, repaints the whole app
live.

**4. Login + Sign-up SSO buttons wired.**
New `lib/services/sso_service.dart` (`SsoProvider`, `SsoResult`,
`SsoException`, `SsoNotConfiguredException`). The full backend round-trip
is implemented: `POST /api/auth/sso { idToken, provider }` → JWT →
`AuthProvider.setSessionFromLogin` → mirror the email/password success
flow.

The native idToken-acquisition step is a *typed* throw today —
`SsoNotConfiguredException` — because the pubspec doesn't include
`firebase_auth` / `google_sign_in` / `sign_in_with_apple` yet. The login
+ sign-up screens catch it and render a clean explanatory modal ("SSO
requires native config; sign in with email + password for now"). The
service file documents the exact lines to drop in once those packages
ship — no surrounding code needs to change.

This keeps the wiring real and the build healthy. Phase K (auth hardening)
is the natural place to add the native SDKs + iOS Apple-Sign-In capability
and flip SSO live; nothing in Phase F has to be revisited at that point.

**5. Change Password tile.**
Wired to a new endpoint (added in this PR's backend half — see backend
`AUDIT.md` Phase F): `POST /api/security/change-password`. The frontend
sends `{ currentPassword, newPassword }`, surfaces backend error messages
verbatim (so 401-current-wrong, SSO-only-account, password-too-short all
read clearly), and on success snackbars + pops back to settings. Backend
also writes a `SECURITY_ACCOUNT` notification row so the change shows up
in Account Activity.

**6. Account Activity tile.**
Wired to the existing endpoint `GET /api/users/me/security-logs` (NOT
`/api/security/log` — the original audit copy was wrong about the path).
Pull-to-refresh, infinite scroll (page=1 / limit=20 / page+=1 on
end-reached), contextual icons per event title, relative timestamps
("Just now", "5m ago", "2d ago", then ISO date for older entries).

**7. SecuritySettings screen wired (formerly orphan).**
The existing `lib/screens/security_settings.dart` (2FA QR setup + Azaman
PIN, fully built, fully integrated with `/api/security/2fa/*` and `/pin/*`,
but never imported from anywhere) is now reachable via the "Two-Factor &
PIN" row in the Security & Privacy section. Closes one of the orphan
screens flagged in §13 of this audit.

**Files in this PR (frontend):**

- `lib/providers/theme_provider.dart` — `AzamanTheme.system` + brightness
  observer + resolution helpers. ~50 LOC delta.
- `lib/services/sso_service.dart` — NEW. ~250 LOC.
- `lib/screens/theme_picker_screen.dart` — NEW. ~595 LOC.
- `lib/screens/change_password_screen.dart` — NEW. ~305 LOC.
- `lib/screens/account_activity_screen.dart` — NEW. ~375 LOC.
- `lib/screens/settings_screen.dart` — full rewrite. ~660 LOC.
- `lib/screens/auth/login_screen.dart` — SSO handler + modal. ~+150 LOC.
- `lib/screens/auth/signup_screen.dart` — SSO buttons + handler. ~+165 LOC.

**Files in this PR (backend, separate branch
`phase-f-change-password-endpoint`):**

- `controllers/securityController.js` — `exports.changePassword` (bcrypt
  verify current → bcrypt hash new → write SECURITY_ACCOUNT audit row).
- `routes/securityRoutes.js` — `POST /change-password` (protect).

**Out of scope, deferred:**

- Native Firebase Auth SDK install + iOS Apple-Sign-In capability + Google
  OAuth client IDs. Owned by Phase K (auth hardening).
- Pulling the audit-flagged orphan deactivation screens into the Settings
  flow. Deferred to Phase M (orphan sweep) since they're not part of the
  user-stated pain.

### Phase E — Savings completion (2026-05-24, in review)

Branch: `phase-e-savings-completion`. Closes the "savings doesn't actually
save" gap: the backend has 8 savings endpoints, the frontend used 2 of them
(overview + create). Users could declare a goal but couldn't fund it,
withdraw from it, pause it, or resume it.

Phase E wires the missing 4:

- `POST /api/savings/goals/:id/deposit`
- `POST /api/savings/goals/:id/withdraw`  (with 2% early-penalty preview if locked + not matured)
- `PUT  /api/savings/goals/:id/pause`
- `PUT  /api/savings/goals/:id/resume`

UX: tap on any goal card → bottom sheet with goal summary (name, status
badge, progress bar, balance), two action tiles (Fund / Withdraw), and a
Pause/Resume toggle. Fund and Withdraw open a sub-sheet with an amount
input (suggestion pre-filled at the goal's `frequencyAmount` for fund, the
full `currentAmountGhs` for withdraw). Withdraw shows the penalty warning
in red on locked-and-not-matured goals before the user submits.

Files in this PR:
- `lib/widgets/savings_goal_sheet.dart` (new) — public `SavingsGoalSheet.show()`
  entry-point + private `_SheetBody`, `_AmountPromptSheet`, `_ActionTile`.
  ~575 LOC.
- `lib/screens/savings_screen.dart` — the goal card in `_buildGoalsList` is
  now wrapped in a `GestureDetector` that opens the management sheet on tap.
  Status badge color logic was also generalized (was binary `ACTIVE` vs
  not-`ACTIVE`; now correctly renders `PAUSED` warning, `COMPLETED` accent,
  `CANCELLED` muted). Plus a tiny chevron at the right of each card so the
  affordance is discoverable.

Note on the create-goal flow: I left the existing `_CreateGoalSheet` alone
in this PR — it works, posts to `/savings/goals`, and the goal lifecycle
work belongs together but the create flow already shipped in Phase 0.

### Phase C — Crypto deposit wiring + unified roadmap (2026-05-24, merged PR #36)

Branch: `phase-c-deposit-and-roadmap`. Deeper-than-expected verification of
the financial screens revealed that **most of what the audit flagged as
"P0 — not wired" is actually fully wired and working**:

- `WithdrawalScreen` posts correctly to `/finance/withdraw/fiat` (mobile money
  path) and `/wallet/withdraw` (saved-wallet crypto path). Has the fiat-pool
  banner, network selection, recipient phone, optional account name, MAX button.
- `TransferModal` calls `friendService.sendFunds(...)` / `friendService.requestFunds(...)`
  via the slide-to-confirm widget. The audit's "calls a method that doesn't
  exist on friendService" claim was stale — both methods exist.
- `FiatDepositFlowScreen` posts to `/deposit/fiat/initiate` and shows the
  reference + instructions correctly.
- `SavingsScreen` posts to `/savings/goals` for goal creation.

**One real gap found and fixed in this PR.** `CryptoDepositScreen` is a
high-quality, fully-built screen that fetches the user's Polygon USDC
deposit address from `GET /wallet/deposit-address/polygon` and renders a QR
code — but it had **zero inbound imports**. Users had no path to it from
anywhere in the app, meaning **nobody could deposit USDC on Polygon**. Phase
C wires it via a new `DepositChooserSheet` so the Home "Deposit" Quick
Action now opens a chooser between Crypto (Polygon USDC) and Fiat (MoMo).

Files in this PR:
- `lib/widgets/deposit_chooser_sheet.dart` (new) — bottom-sheet chooser with
  Crypto / Fiat options, navigates to the right destination screen.
- `lib/screens/home_screen.dart` — Quick Action label changed from "Deposit Fiat"
  to "Deposit", `onTap` now opens the chooser sheet.

**One bigger gap noted, deferred to Phase E:** `SavingsScreen` only uses
2 of the 8 backend savings endpoints. Backend exposes `deposit`, `withdraw`,
`pauseGoal`, `resumeGoal`, `getGoal` — frontend doesn't call any of them.
Users can create a goal but cannot fund or draw from it. See ROADMAP below.

### Phase 0 — Visible Wins (2026-05-24, merged PR #35)

Branch: `phase-0-visible-wins`. First post-audit PR. Surgical, frontend-only,
no behavioural changes outside the items below.

| # | Item | Status | Notes |
|---|---|---|---|
| §C.1 | Leaked Firebase service-account key removed from working tree | DONE | `service-account.json.json` deleted. `.gitignore` hardened (`service-account*.json*`, `firebase-adminsdk-*.json`, `google-services.json`, `GoogleService-Info.plist`, `.env*`, `*.pem`, `*.key`, `*.p12`). **Manual follow-up required**: revoke + rotate the key in the Firebase console — git history still contains it until the repo is rewritten or the key is rotated. |
| §5 | Vendor pull tab role gating inverted | DONE | `lib/widgets/vendor_pull_tab.dart`. Was `if (role != AppRole.vendor) return SizedBox.shrink()` — hidden from non-vendors. Now shown to everyone. Vendors see "FOR VENDOR" → routes to `VendorDashboard`; non-vendors see "BECOME VENDOR" → routes to `VendorApplyScreen` (was orphan, now wired). |
| §C.2 | Home Quick Actions wired | DONE | `lib/screens/home_screen.dart`. All four tiles (Buy / Sell / Deposit Fiat / Savings) now navigate. Buy & Sell push `P2PMarketplaceScreen`; Deposit Fiat pushes `FiatDepositFlowScreen` (was orphan, now wired); Savings pushes `SavingsScreen`. Phase F will introduce a proper sell-side entry. |
| §3 | Settings theme picker grid layout overhaul | DONE | `lib/screens/settings_screen.dart`. 11 themes were laid out 2-col aspect-1.6 with four competing visual elements per tile (3 dots + selected check + icon + name). Rebuilt as 3-col aspect-0.95 with a top swatch stripe (3 colors + selected indicator), and an icon + name body painted on the theme's own `card` color — so the picker doubles as a live preview. |
| §4 | Dead `lib/theme/app_theme.dart` removed | DONE | Only references were itself. Theme system is the live `lib/providers/theme_provider.dart`. |
| §13 | Orphan `actual_settings_screen.dart` removed | DONE | Hardcoded colors, never imported, audit-flagged stale duplicate. |

### Stale audit findings — ALREADY-FIXED before this PR

While verifying the audit against the live code, three findings turned out to
have been resolved earlier and are flagged here so future reviewers don't
re-fix them:

1. **Backend §A.3 — `withdrawalController.processWithdrawal` does not call MTN.** Stale. `controllers/withdrawalController.js:117` already invokes `mtnDisbursementService.initiateTransfer`. The withdrawal-to-MoMo path is wired.
2. **Backend §A.5 — `directMessageController` has no route file.** Stale. The controller is wired in `routes/friendRoutes.js` lines 43–47, mounted under `/api/friends/chat/*`. Symptom (frontend `/api/messages/*` hitting 404) is real but the cause is a *path-contract mismatch* with `api_contract.md`, not an orphan controller. Track as a separate item in Phase B / contract reconciliation.
3. **Frontend §6 — AppBar chat icon is decorative.** Stale. `lib/main.dart:333` already opens `FriendsHubScreen` (which has Chats + Requests tabs and live unread-count badge). No change needed.

### Phase 0 deletions list

```
service-account.json.json                    (CRITICAL — credential leak)
lib/theme/app_theme.dart                     (orphan, AzamanAppTheme replaced)
lib/screens/actual_settings_screen.dart      (orphan, settings_screen is canonical)
```

### Phase 0 — files added to .gitignore

```
service-account*.json
service-account*.json.json
google-services.json
GoogleService-Info.plist
firebase-adminsdk-*.json
.env
.env.*  (with !.env.example whitelist)
*.pem
*.key
secrets/
*.p12
```

---

## UNIFIED ROADMAP (canonical, mirrored across both repos)

> This block is the single source of truth for "what's next." It is mirrored
> verbatim in `azaman-backend-main/AUDIT.md`. When you change one, change
> the other in the same PR. Don't fork the plan.

**Phase letter convention.** Phases are letter-tagged. A phase is **a single
focused PR** (≤ ~1500 LOC) that ships one coherent unit of value. The order
matters: later phases assume earlier ones merged.

### Status legend
- `DONE` — merged to main.
- `IN REVIEW` — PR open, awaiting review/merge.
- `NEXT` — first thing to pick up after current PRs land.
- `PLANNED` — committed scope, scheduled for later.
- `BACKLOG` — known need, not yet scheduled.

### Repo legend
- `BE` — backend (azaman-backend-main).
- `FE` — frontend (azaman-frontend-main).
- `both` — coordinated change spanning both repos.

### The roadmap

| Phase | Status | Repo | Title | Scope |
|---|---|---|---|---|
| **0** | `DONE` (PR #35 FE) | FE | Visible wins | Vendor pull tab gating fix, Home Quick Actions wired, settings theme grid rebuilt, dead theme/screens deleted, Firebase key removed from FE. |
| **1** | `DONE` (PR #32 BE) | BE | Firebase credential rotation | Removed leaked `service-account.json`, hardened `.gitignore`, updated `.env.example`, downgraded missing-key error to warning. |
| **B** | `DONE` (PR #33 BE) | BE | Money correctness re-verification | Verified 5 of 6 audit P0s already fixed; misdiagnosis on dual-ledger; one real fix shipped (`adController` collateral gate, was reading dead `lockedBalance` field — now reads `availableBalance`). |
| **C** | `DONE` (PR #36 FE) | FE | Crypto deposit wiring + unified roadmap | Wired orphan `CryptoDepositScreen` via new `DepositChooserSheet` from Home Quick Action. Verified WithdrawalScreen + TransferModal + FiatDepositFlow are already correctly wired. Wrote this canonical roadmap. |
| **D** | `DONE (BE PR #59) ⚠️ PARTIALLY REVERTED by D-3` | BE | AZM trap + BUY-ad ledger redesign | D-2 correctly unified trade settlement on availableBalance (USDC) and fixed BUY-ad escrow. D-2 **incorrectly** dropped the azmBalance column. D-3 (BE, in review) restores it as an independent loyalty-point ledger. FE PR #48 (D-2 cleanup) is ABANDONED — do not merge. |
| **E** | `DONE` (PR #37) | FE | Savings completion | Wired `deposit`, `withdraw`, `pauseGoal`, `resumeGoal` from `SavingsScreen` (backend has them; FE only used overview + create today). Tap on a goal card → bottom sheet with Fund / Withdraw / Pause-Resume actions. New widget: `lib/widgets/savings_goal_sheet.dart`. |
| **F** | `DONE` (BE PR #36 + FE PR #38) | FE+BE | Settings overhaul (the original user pain point) | Apple/Binance row layout, dedicated `ThemePickerScreen` with live home preview, `AzamanTheme.system` (12th option, auto-follows OS brightness), SSO buttons wired on login + signup (typed `SsoNotConfiguredException` until Phase K adds firebase_auth + native config), Change Password tile (new backend endpoint `POST /api/security/change-password`), Account Activity tile (existing `GET /api/users/me/security-logs`), `SecuritySettings` orphan wired in. ~2.4k LOC across 8 frontend files + 2 backend files. |
| **G** | `DONE` (FE PR #39) | FE | Home overhaul | Replaced hardcoded Core Assets with live `/api/oracle/rates` data + 24-sample in-memory sparkline (fl_chart). New `TodayWidget` with 4 stat tiles: Active Trades, Pending Withdrawals, Friend Requests, Unread Notifications — each tile navigates to the right destination. Removed hardcoded Platform News (no real backend endpoint yet). Pull-to-refresh now actually re-fetches via `homeSummaryProvider.refresh()` (5 endpoints in parallel) + `authProvider.fetchUserDetails()`. Animated balance counter was already in `HologramBalanceCard` via TweenAnimationBuilder — verified. ~1,365 LOC across 5 frontend files. |
| **H** | `DONE` (FE PR #40) | FE | Premium polish pass | Custom slide+fade page transitions wired globally via `ThemeData.pageTransitionsTheme`. Status bar + system nav bar style synced to the active theme via `AnnotatedRegion<SystemUiOverlayStyle>` in `AzamanApp`. New haptic vocabulary (`AzamanHaptics.nav/toggle/confirm/commit/warn`) adopted across home/settings/theme-picker. Wired `SkeletonBlock` (was orphan) into Today widget cold-load + LiveMarket cold-load. New `AzamanConfirmSheet` replacing the legacy AlertDialog sign-out. Six review-pass bugs in F+G+H were fixed in the same commit. ~820 LOC. |
| **H2** | `DONE` (FE PR #41) | FE | Slide-to-confirm on financial actions | Wired the existing `SlideToConfirm` widget into the highest-risk financial confirms. Withdrawal screen `ElevatedButton` → `SlideToConfirm`. Savings goal sheet `_AmountPromptSheet` (fund/withdraw) same swap with parent-driven CTA color + label. Friends transfer modal verified intact. PR #41 is the merge that brought F+G+H+H2 stack onto FE main as a single chain. ~130 LOC. |
| **H3** | `DONE` (FE PR #42) | FE | Biometric pre-gate + slide-to-confirm completion | Replaces vendor Release-crypto AlertDialog with a slide-to-confirm bottom sheet (`_ReleaseCryptoSheet` with rich amount summary + payment method + warning banner). Adds opt-in `AzamanBiometricGate` wrapping every `SlideToConfirm.onConfirmed` (vendor release, withdrawal, savings, friends transfer, buyer mark-paid). Adds Biometric Lock toggle in `security_settings.dart` — itself biometric-gated in both directions. Hardens `SlideToConfirm` widget with `enabled` prop, public `SlideToConfirmState` for `GlobalKey.reset()`, `didUpdateWidget` re-arm on isLoading and enabled edges, `BiometricService.authenticate({reason})` parameter pipe to `local_auth.localizedReason`, `isAvailable` tightened to `canCheckBiometrics && isDeviceSupported()`, `commit()` haptic moved inside gated action. Three rounds of semantic review folded in. ~700 LOC across 9 files. |
| **I** | `DONE` (BE PR #40) | BE | Performance + mobile payload | Cursor pagination on `/notifications`, `/chat/:tradeId`, `/friends`, `/ads`, `/trades/history`. Ten composite indexes. `/friends` 2N→2 query collapse. AI marketplace declared single-page. Backwards-compat preserved on `/ads` / `/trades/history` / `/chat/:tradeId`. ~570 LOC + 1 migration. |
| **J** | `IN REVIEW` | both | Schema cleanup — drop dead V1 columns | **Drops `ghsBalance` + `lockedBalance`** from User (both write-dead per Phase B findings C+D). Coordinated BE migration (drop columns) + FE clean-up (model, providers, socket service, dashboards stop reading dropped JSON keys). Vendor dashboard "in escrow" UI rewired from the dead `lockedBalance` to V2 `escrowLockedBalance` — now shows real numbers. Pre-Phase-J app builds parse defensively to 0.0, so no functional regression. ~150 LOC across 14 files + 1 migration. **Float→Decimal + CHECK constraints DEFERRED to Phase J2.** |
| **J2** | `BACKLOG` | BE | Decimal + CHECK migration | Migrate every money column from `Float` to `Decimal(18,8)`; add `CHECK (col >= 0)` constraints. Risky — column-type rewrite takes a heavy lock; needs a maintenance window or logical-replica cutover plan. ~300 LOC + ops runbook. |
| **K** | `IN REVIEW` (BE PR #39) | BE | Auth + security hardening | Refresh-token flow (15-min access + 30-day refresh + `/auth/refresh` endpoint). Re-issue token on `isVendor` flip so vendor UI activates without logout. SSO `aud` claim verification. Whitelist `profileController.updateProfile` editable fields. Move user avatars out of `/uploads/proofs/`. ~400 LOC. |
| **L** | `BACKLOG` | BE | API contract docs sweep | Document the 9 route trees flagged in `api_contract.md` "Coverage gaps": `/friends`, `/savings`, `/security`, `/users`, `/sso`, `/ai`, `/kyc`, `/vendor`, `/oracle`. Convention going forward: when you touch a route in any other PR, write its spec into the contract in the same PR. So this is a slow-burn cleanup, not a single PR. |
| **M** | `DONE` (FE PR #44) | FE | Wiring + orphan sweep | **Closes audit §13 orphan inventory.** GoRouter from 4 → 13 routes (every FCM-deep-linkable surface now named); 5 orphan screens wired (`ProfileDetailsScreen`, `ReferralScreen`, `AccountDeactivationScreen` into settings; `MessagesHubScreen`, `LeaderboardScreen` reachable via `/messages` + `/leaderboard` deep-links); 11 confirmed-dead orphans deleted (account_deactivation duplicate, admin_spy_screen duplicate, admin_war_room duplicate + orphans, chat_screen, notification_screen duplicate, root signup_screen duplicate, trade_appeal_sheet, user_dashboard dev sandbox, wallet_screen, fiat_wallet_screen). `handleNotificationTap` action vocabulary expanded to handle the full BE-emitted set. ~280 LOC across 4 changes + 11 deletions. **Out of scope (deferred):** promoting all 67 imperative `Navigator.push` callsites; wiring leaderboard / messages-hub into existing UI surfaces; removing AppBar chat icon. |
| **N** | `IN REVIEW` | FE | Queue / Waiting Room wiring + demo sweep | Wires the orphan `WaitingRoomScreen` into the live trade flow. `initiateTrade()` returns `TradeInitiationResult` (queued vs immediate). Socket listeners for real-time queue position + auto-promotion. Leave-queue API wired. `/queue` GoRoute + `OPEN_QUEUE` FCM handler. Vendor nav fix (`context.go` → `Navigator.pop`). Full 12-flow demo readiness verification. ~350 LOC across 5 files. |

### Suggested merge order

**Updated 2026-05-25 (post-Phase-N).** Phases 0, 1, B, C, E, F, G, H, H2, H3,
I, J, K, M, B2-FE, H4, D-3-FE, E1-FE, E2-FE, F2-FE are `DONE` (merged).
Phase N-FE (Queue wiring + demo sweep) is `IN REVIEW`.

Remaining work is **N → J2 → L**.

The reasoning:
- N wires the queue/waiting room (the last missing P2P path) and verifies all 12 flows demo-ready.
- J2 is the Float→Decimal migration — needs maintenance window.
- L is API contract docs — slow-burn per-PR convention.

### What is explicitly NOT on this roadmap (yet)

- A web build. The `web/` folder exists but no one has tested it. Will need its own discovery phase.
- Multi-currency beyond GHS/USDC. The hologram model assumes a single local fiat. Adding a second region (e.g., NGN for Nigeria) is a separate platform-level project.
- A native admin app. Admin lives inside the same Flutter codebase today.
- Internationalization (i18n). All copy is hardcoded English.

---

## TL;DR

1. **27 screen files in `lib/screens/` are completely orphaned** — never imported, never navigated to. This is the single biggest reason the app feels half-built. Highlights of the orphans:
   - `actual_settings_screen.dart` (the *good-looking* settings — see §3)
   - `crypto_deposit_screen.dart`, `fiat_deposit_flow_screen.dart`, `vendor_deposit_screen.dart`
   - `wallet_screen.dart`, `fiat_wallet_screen.dart`
   - `vendor_apply.dart` (this is what the pull tab needs to navigate non-vendors to!)
   - `leaderboard_screen.dart`, `referral_screen.dart`, `security_settings.dart`
   - `chat/direct_message_screen.dart`, `chat/transaction_chat_screen.dart`, `chat_screen.dart`, `messages_hub_screen.dart`
   - `signup_screen.dart` (root duplicate of `auth/signup_screen.dart`)
   - `account_deactivation.dart` AND `account_deactivation_screen.dart` (same feature, two files)
   - 3 admin screens, 2 admin war room duplicates
   - Full table in §13.

2. **`go_router` is configured with 4 routes total** (`/`, `/notifications`, `/trade/:id`, `/dispute/:id`) but the entire app actually navigates with `Navigator.push(MaterialPageRoute(...))`. So FCM deep-links into the app land on a black screen unless they target one of those 4 routes. (§2)

3. **Two settings screens exist** — `settings_screen.dart` (currently shown, ugly theme grid that looks bad on mobile) and `actual_settings_screen.dart` (a cleaner Binance-style layout, with proper section headers, but it's a Frankenstein with hardcoded `Color(0xFF...)` values and no theme integration). Neither is finished. The right answer is to merge them. (§3)

4. **Two theme systems exist:** `lib/providers/theme_provider.dart` (the live one — 11 themes, ChangeNotifier, persists via SharedPreferences) and `lib/theme/app_theme.dart` (`AzamanAppTheme`, dead code — only referenced by itself). Delete `app_theme.dart`. (§4)

5. **The vendor pull tab visibility logic is inverted** — it checks `if (role != AppRole.vendor) return SizedBox.shrink()`, meaning **only vendors see it**. The user explicitly said this should show for everyone, and tapping it as a non-vendor should prompt them to apply. The target screen (`vendor_apply.dart`) exists as an orphan. Fix is one block of conditional logic. (§5)

6. **The bottom nav has 5 items: Home / Chat / P2P / Savings / Profile** — but the AppBar also has a Chat icon (next to the notification bell) that opens the same Friends Hub. The user explicitly asked to remove this duplicate. (§6)

7. **`trades_tab_screen.dart` is imported in `main.dart` but not added to `_pages`** — there's an active trades hub that's referenced but unreachable from the app shell. Either add it to nav or remove the import. (§6)

8. **The Home screen (`home_screen.dart`) is the user-facing dashboard but its "Quick Actions" buttons (Buy Crypto / Sell Crypto / Deposit Fiat / Savings) have only `HapticFeedback.lightImpact()` — no navigation.** They're decorative. (§7)

9. **The Home screen "Platform News Feed" is hardcoded** with mock entries ("Azaman v4.0 — Hologram Balance is Live", "Just now"). There is no real news endpoint and the data doesn't update. (§7)

10. **`service-account.json.json` is committed in the frontend repo** (note the doubled extension — `.json.json`). This is Firebase admin SDK credentials and should never be in a client app, period. Plus the filename being wrong suggests a copy-paste mistake. (§14)

11. **No dark/light auto-switch.** Theme is locked to whatever the user picks. iOS / Android system theme changes are ignored.

12. **Mobile layout issues** found in 8+ screens (overflowing rows, Expanded inside scrollables, fixed pixel sizes that don't scale on small phones). Catalogued in §10.

13. **No error boundary, no offline state, no skeleton loaders on most screens.** A flaky network shows a CircularProgressIndicator forever. There is a `skeleton_loader.dart` widget — orphan, used in zero screens. (§9)

14. **Backend integration gaps.** Several critical endpoints are simply not called from anywhere in the app:
    - `/api/withdraw/*` — there's a withdrawal screen but withdrawal logic is fragmented (§8)
    - `/api/savings/*` — savings screen exists, none of its CRUD calls go through `api_client`
    - `/api/messages/*` — DM controller has no client (because backend has no route — see backend AUDIT.md §5)
    - `/api/notifications` — bell shows count but mark-read / list endpoints not wired
    - Full table in §8.

15. **No biometric auth on financial actions.** `local_auth` package is in `pubspec.yaml` and `biometric_service.dart` exists, but it's only referenced once (in transfer modal, half-wired). For a fintech app this is a premium-feel must.

---

## §1 — Wiring map: how the app actually navigates

### What `main.dart` does

Entry point spawns `ProviderScope > AzamanApp`. `AzamanApp` is a `MaterialApp.router` wired to `appRouter` from `lib/router/app_router.dart`. The router's `initialLocation` is `/` which renders `SplashScreen`.

After auth is confirmed by `SplashScreen._checkAuthStatus`:
- Authenticated + onboarded → `Navigator.pushReplacement(... MainNavigationWrapper())`
- Authenticated + not onboarded → `OnboardingScreen`
- Otherwise → `LoginScreen`

`MainNavigationWrapper` is just an alias for `MainWrapper`. `MainWrapper` is the actual app shell — Scaffold with AppBar, bottom nav, end-drawer, vendor pull tab.

### What `app_router.dart` actually defines

Only **4 GoRoutes**:

| Path | Renders |
|------|---------|
| `/` | `SplashScreen` |
| `/notifications` | `NotificationHubScreen` |
| `/trade/:tradeId` | `ActiveTradeScreen` |
| `/dispute/:disputeId` | inline `_DisputeScreen` |

There is no `/login`, `/signup`, `/main`, `/home`, `/profile`, `/settings` etc. Everything else is `Navigator.push(MaterialPageRoute(builder: (_) => SomeScreen()))`.

### Implications

- **FCM deep links into anything that's not a trade or dispute will fail silently.** `handleNotificationTap` in `app_router.dart` only knows about `OPEN_TRADE` and `OPEN_DISPUTE` action types. Backend-sent notifications with action types like `OPEN_DEPOSIT`, `OPEN_TRANSFER`, `OPEN_FRIEND_REQUEST` (which the backend already emits — see backend audit §5) will be discarded.
- **The back button is unpredictable.** Imperative `Navigator.push` from inside go_router subtrees produces a navigation stack that doesn't behave like users expect on Android.
- **No URL persistence** for screens, so on web (the `web/` folder exists) bookmarking any non-trade page is impossible.

### Fix path

- Promote every "real" screen into a `GoRoute` in `app_router.dart`.
- Replace `Navigator.push(MaterialPageRoute(...))` with `context.push('/path')` everywhere.
- Add additional notification action types to `handleNotificationTap`.
- This is mechanical but touches ~40 files. Bundle into one PR (Phase D).

---

## §2 — Auth flow

`SplashScreen._checkAuthStatus` is the only auth gate. After the storage read it calls `auth.checkAuthStatus()` then `auth.setSessionFromLogin(...)`. The phantom-user fix is in place.

### Findings

**P1 — JWT staleness on role change.** The frontend reads `currentRole` from `tradeProvider`, not from the JWT. `tradeProvider.toggleRole` flips between `AppRole.user` and `AppRole.vendor` purely client-side (line 168). The server has no idea, and rate-limit / authorization checks downstream may disagree. This pairs with the backend "JWT staleness on `isVendor` flip" finding in `AUDIT.md §2`. Fix needs both sides.

**P1 — `LoginScreen.dart` does not pre-fill saved email.** Most fintech apps auto-fill the last-used email on the login screen. `flutter_secure_storage` is already in use; one line gets us this.

**P1 — No "stay signed in" toggle.** Login always remembers; there is no opt-out. Fine for now but worth a note.

**P2 — Login form has no input validation before submit.** Lets you POST empty fields. The backend rejects, but that's a wasted round-trip + bad UX on slow connections.

**P2 — Login error states surface as `SnackBar`.** Banking apps use inline field-level errors. A snackbar that disappears in 3 seconds while the user is still typing is not premium.

**P2 — `signup_screen.dart` (root) is an orphan duplicate of `auth/signup_screen.dart`.** Delete the root one.

**P2 — Onboarding can be skipped via the back button.** Users can press back from onboarding into `LoginScreen` and end up in a half-onboarded state. Onboarding should be `WillPopScope`-locked.

---

## §3 — Settings screen (the user's specific pain point)

### What exists

| File | Status | What it shows |
|------|--------|---------------|
| `lib/screens/settings_screen.dart` | **Wired** (used by `settings_drawer.dart`) | 5 sections (Mode & Theme, Notifications, Preferences, Payment & Security, Other), `GridView` of all 11 themes with a 1.6 aspect ratio (squashed on phones), real switches wired to `settingsProvider` |
| `lib/screens/actual_settings_screen.dart` | **Orphan** | Cleaner Binance-style sections (General, Appearance, Payment, Other), `_settingsTile` rows with optional trailing labels, but uses hardcoded `Color(0xFF0B0E11)` everywhere — no theme integration |
| `lib/screens/security_settings.dart` | **Orphan** | Some kind of security center — never reached |
| `lib/screens/account_deactivation.dart` | **Orphan** | Deactivation flow |
| `lib/screens/account_deactivation_screen.dart` | **Orphan** | DUPLICATE deactivation flow |

### What the user said

> "Just look at the actual settings page. The themes are listed there and it's not proper."

Confirmed. In `settings_screen.dart`:
- The theme picker is a 2-column grid with 11 entries → 6 rows of cards, each card 1.6:1 aspect — which on a 360px-wide phone makes each card ~110×69px. The card has a 12px padding, three colored dots top-right, an icon, and a name. **It doesn't fit.** On smaller phones the icons clip and the name truncates.
- Section header padding is inconsistent with other sections.
- "Withdrawal Addresses" is listed but tapping it shows a placeholder `_showPlaceholderPage` instead of `SavedWalletsScreen` (which exists and IS wired in the drawer).
- "Privacy Center" → placeholder page (no real content)
- "Help & Support" → no `onTap` at all (dead nav item)

### What `actual_settings_screen.dart` does better

- Cleaner row layout: single `_settingsTile(icon, title, trailing: 'USD')` that mirrors iOS Settings exactly.
- "Mode & Theme" is a single row with `trailing: "Dark"` — the user taps to enter a dedicated theme picker (cleaner than a grid jammed into the main settings list).
- About dialog is properly wired.

### What `actual_settings_screen.dart` does worse

- Hardcoded `Color(0xFF0B0E11)` background. The theme system is bypassed entirely.
- No real section data (most rows have no `onTap`).
- No SharedPreferences integration for any setting.

### Recommended fix (the merge)

1. **Adopt `actual_settings_screen`'s layout** (Apple/Binance-style row tiles, single-row "Mode & Theme" entry that opens a child screen).
2. **Adopt `settings_screen`'s real wiring** (theme provider, settings provider, sign-out flow).
3. **Add a child screen `theme_picker_screen.dart`** that is a full-page theme picker (each theme gets its own card with a live preview of the home screen header at the top, tap to apply, smooth transition). This is the premium move.
4. Delete `actual_settings_screen.dart`, `account_deactivation.dart`, `account_deactivation_screen.dart`, `security_settings.dart`. Replace with a single `account_screen.dart` reachable from settings.

This is in fix Phase B.

---

## §4 — Theme system

### What exists

- `lib/providers/theme_provider.dart` — 11 themes (Light, Dark, Cyber Blue, Midnight, Mars, Saturn, Snow, Neon Tokyo, Deep Ocean, Volcanic, Aurora). Persists to SharedPreferences. `AzamanColors` token bag is comprehensive and well-thought-out (background, surface, card, divider, accent, accentSecondary, accentSurface, success, danger, warning, textPrimary/Secondary/Tertiary, glow). Every screen reads via `ref.watch(themeProvider).colors`.
- `lib/theme/app_theme.dart` — `AzamanAppTheme` static class with hardcoded dark-only theme. Only reference: itself.

### Findings

**P1 — Delete `lib/theme/app_theme.dart`.** Dead code. Confirmed by grep — nothing imports it.

**P1 — System theme is not respected.** A user on iOS who flips dark/light in Control Center sees no change. Add a 12th option `AzamanTheme.system` (default) that watches `MediaQuery.platformBrightnessOf(context)`.

**P2 — `themeData.bottomNavigationBarTheme` is set but the app's actual bottom nav is `PremiumBottomNav` (custom widget, not `BottomNavigationBar`).** Either remove the unused theme entry or wire `PremiumBottomNav` to read from it.

**P2 — `themeProvider` is a `ChangeNotifier`. The whole tree rebuilds on theme change.** Fine for an instant theme apply, but causes visible flash on slow phones. A `StateNotifier<ThemeState>` with a `select` over `colors` would be more granular.

**P2 — Hardcoded `Color(0xFFD4AF37)` and `Color(0xFF02C076)` exist in dozens of places across the codebase.** Migrate to theme tokens. Run `grep -rn "Color(0xFF" lib/` — if the count is high, that's a hard signal that themes don't actually theme.

---

## §5 — Vendor pull tab (specific user pain point)

### What's wrong (from user's previous chat)

> "The vendors are also users. They will have the option to see the normal user dashboard as well as theirs. So, yes, the pull tab should still work and show on the user dashboard. It should show for every user but when a user who isn't a vendor taps on it, it should ask them if they want to become a vendor."

### What the code currently does

`lib/widgets/vendor_pull_tab.dart`:
```dart
final role = ref.watch(tradeProvider.select((t) => t.currentRole));
// Only show for vendors
if (role != AppRole.vendor) return const SizedBox.shrink();
```

It hides itself for non-vendors. Drag-past-50% behavior pushes `VendorDashboard`, regardless of whether the user has been approved as a vendor.

### Recommended behavior (matches user spec)

| User type | Pull tab | On drag past 50% |
|-----------|----------|------------------|
| Non-KYC user | Visible, label "BECOME VENDOR" | Sheet: "Apply to become a vendor — complete KYC, then we'll review" → goes to `KycVerificationScreen` if KYC missing, otherwise `VendorApplyScreen` |
| KYC done, not approved vendor | Visible, label "VENDOR APPLICATION" | `VendorApplyScreen` (currently orphan!) or status sheet if pending |
| Approved vendor | Visible, label "VENDOR PORTAL" | `VendorDashboard` |

### Fix path

1. Remove the `role != AppRole.vendor` early return.
2. Read `user.kycStatus` and `user.isVendor` from `currentUserProvider`.
3. Conditionally label the tab and conditionally route on drag-end.
4. Wire up the orphan `vendor_apply.dart`.

This is one of the cleanest wins — touches 2 files, ~40 lines.

---

## §6 — Bottom nav and AppBar duplication

### What's wrong

In `main.dart` `_MainWrapperState.build`:
- AppBar has 3 actions: Chat icon (opens `FriendsHubScreen`) → Notification bell → "HQ"/"PRO" role badge that opens the end drawer.
- Bottom nav (`PremiumBottomNav`) has 5 items: Home → Chat (also `FriendsHubScreen`) → P2P → Savings → Profile.

So **the chat function is reachable two ways from the home screen**, and the AppBar variant is redundant. The user explicitly asked to remove the AppBar variant.

Also, `_pages` has 5 entries to match the 5 nav items, but `lib/screens/trades_tab_screen.dart` is imported and never used. Unused import.

### Findings

**P1 — Remove the chat icon from the AppBar.** Keep only the notification bell + role badge.

**P1 — Decide whether "Trades" deserves its own tab.** Active P2P trades currently live somewhere inside the marketplace screen. Trade history is also implicit. A dedicated Trades tab (replacing one of the 5 — likely Savings, which can move into Profile) would surface in-flight orders much better.

**P1 — Remove the `trades_tab_screen.dart` import in `main.dart`** if we're not adding it as a tab.

**P2 — Tab labels are inconsistent.** `_kNavItems` defines 5 items (Home, Chat, P2P, Savings, Profile) but the comment in `premium_bottom_nav.dart` says "4 items: Home | P2P | Trades | Profile". Stale comment.

**P2 — The "HQ" / "PRO" badge in the AppBar.** It says "HQ" for users and "PRO" for vendors. This is cute but most users won't understand what it means. Consider a clearer label or a small icon.

---

## §7 — Home screen (the dashboard)

### What it shows now

`lib/screens/home_screen.dart` (`AzamanHomePage`):

1. `HologramBalanceCard` — the live balance widget at top (good — actually wired, has real data).
2. "Quick Actions" row — 4 tiles: Buy Crypto / Sell Crypto / Deposit Fiat / Savings.
3. "Core Assets" — 3 hardcoded rows (AZM, USDT, GHS) with hardcoded "$1.00" prices and a "Stable"/"Local" badge.
4. "Platform News" — 4 hardcoded news cards.

### Findings

**P0 — Quick Action buttons do nothing.** Each `_buildQuickAction` has `onTap: () => HapticFeedback.lightImpact()` only. Tapping "Deposit Fiat" should go to a deposit flow. Tapping "Buy Crypto" should go to the marketplace. None of these are wired.

**P0 — "Core Assets" section is hardcoded mock data.** No call to `/api/wallet`, no live prices. Users see "$1.00" forever.

**P1 — Platform News is hardcoded.** No backend endpoint, no admin tool to publish news, dates are all "Just now / 1 day ago / 3 days ago / 1 week ago" (stale immediately on app launch).

**P1 — Pull-to-refresh does nothing meaningful.** `onRefresh` just `await Future.delayed(const Duration(seconds: 1))`. It's literally a sleep.

**P1 — User explicitly said "the home page shows the user balance, I do not have a problem with that but I feel like we should use the home page for other things."** Suggested home screen overhaul:

```
┌─────────────────────────────────────┐
│ HologramBalanceCard (KEEP)          │
│ - tap-and-hold to switch currency   │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ Quick Actions (WIRE UP):            │
│  Deposit | Withdraw | Send | Receive│
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ "Today" widget                      │
│  - Active trades (count + status)   │
│  - Recent transactions (last 3)     │
│  - Pending withdrawals              │
│  - Friend requests / unread DMs     │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ Live Market (REAL data via oracle)  │
│  AZM USDC GHS rates with sparklines │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ Promotions / Platform News          │
│  - real backend endpoint /api/news  │
└─────────────────────────────────────┘
```

This is the premium move. The current screen is a static brochure. The right home screen is a dynamic morning-coffee dashboard.

**P2 — `HologramBalanceCard` repaints on every tick of the live socket.** This is fine on a flagship phone, expensive on a low-end Android. Should debounce.

---

## §8 — Backend endpoint coverage from the frontend

I grep'd `lib/` for HTTP / api_client calls. Here's what's reached:

| Backend route family | Reached from frontend? | Notes |
|----------------------|------------------------|-------|
| `/api/auth/*` | ✓ | login, register, me/:id |
| `/api/users/onboarding` | ✓ | splash check |
| `/api/trades/history` | ✓ | main.dart sync |
| `/api/wallet/*` | ✗ | nothing in `lib/` calls these |
| `/api/deposit/*` | ✓ partial | only the create-intent path; webhooks are server-server |
| `/api/withdraw/*` | ✗ | screen exists, no API call |
| `/api/finance/transfer` | ✗ | transfer modal exists, no API call |
| `/api/p2p/*` | ✓ | marketplace, ping flow |
| `/api/chat/*` | ✓ | trade chat |
| `/api/messages/*` | ✗ | DM endpoints + DM client both missing |
| `/api/notifications/*` | partial | bell counter wired, list/read not |
| `/api/friends/*` | ✓ | friends hub, partial |
| `/api/savings/*` | ✗ | screen exists, no API call |
| `/api/kyc/*` | ✓ partial | submit only; status check not wired |
| `/api/ads/*` | ✓ | marketplace |
| `/api/security/*` | ✗ | no UI |
| `/api/payout-destinations` | partial | saved-wallets screen, partial |
| `/api/trade-accounts` | partial | add only, no list/edit |
| `/api/admin/*` | partial | admin dashboard reaches some, not all |
| `/api/war-room/*` | partial | war room screen reaches partial |
| `/api/ai/*` | ✓ | dispute summary widget |
| `/api/oracle/*` | ✓ | balance card reads rates |
| `/api/vendor/*` | partial | vendor dashboard, partial |
| `/api/sso` | ✗ | no Google/Apple sign-in button anywhere |

### Findings

**P0 — `WithdrawalScreen` doesn't actually call the withdrawal endpoint.** `lib/screens/withdrawal_screen.dart` is in `lib/screens/` and is referenced 3 times (the wallet pull-down menu, the friends transfer modal, and the saved wallets screen) but the actual submit doesn't POST anywhere I can find. (The matching backend endpoint is also broken — see backend AUDIT §3.)

**P0 — `SavingsScreen` reads/writes nothing.** It renders local state. Has buttons. No HTTP. The savings backend was just added (`/api/savings`) and the frontend was never updated to integrate.

**P0 — `TransferModal` (friends transfer) reaches ~40% wired.** It has the recipient picker and amount field, but the `_handleTransfer` callback calls a method that doesn't exist on `friendService`. Crashes when used.

**P1 — KYC status is only re-fetched on login.** If a user submits KYC and waits, they have to log out and back in to see the status change to "Verified". The screen should poll or subscribe to socket events.

**P1 — No SSO button on the login screen.** Backend `ssoController` is fully wired (Google + Apple) but frontend never invokes it. This is a 30-minute add for both buttons.

**P1 — Admin screens are gated only by `user.role === 'ADMIN'` client-side.** That's fine for UX, but combined with the JWT staleness issue from the backend audit means a recently-demoted admin can still see the admin dashboard for up to 7 days.

**P2 — `lib/screens/admin_war_room.dart`, `lib/screens/admin_war_room_alerts.dart`, `lib/screens/admin_war_room_screen.dart` are three files, two are orphan.** `admin_war_room_screen.dart` is the one wired. Delete the other two.

---

## §9 — Loading, errors, offline

### Findings

**P1 — `lib/widgets/skeleton_loader.dart` exists. It's used in zero screens.** Every list-type screen currently shows a `CircularProgressIndicator` while loading. Skeletons are the premium pattern. Wire it into:
- Friends list
- Trades list
- Marketplace (ads list)
- Chat history
- Savings goals
- Notification list

**P1 — No global error boundary.** A `setState` in a disposed widget or a JSON parse exception kills the screen and leaves the user staring at a black background. Add a `RootErrorBoundary` widget at the top of `MaterialApp.router > builder` that catches uncaught errors and shows a "Something went wrong — retry" sheet.

**P1 — No offline state.** Drop a phone to airplane mode and the app shows an infinite spinner on every screen. Ideal: detect via `connectivity_plus` package (need to add to pubspec) and show a thin red banner at the top "Offline — showing cached data" with a retry tap.

**P2 — Empty states are inconsistent.** Some screens show "Nothing here yet", others show a blank screen, others show a `SizedBox.shrink()`. Pick a pattern (illustration + headline + CTA) and apply.

**P2 — Pull-to-refresh is not on every list.** Only Home and Marketplace have it. Friends, Trades, Notifications, Savings should all have it.

---

## §10 — Mobile layout issues

A premium fintech app has to look right on phones from 360×640 (cheap Android) up to 430×932 (iPhone Pro Max). Most Azaman screens were designed at "comfortable phone width" (~390px) and break outside that range.

### Confirmed issues

**P1 — `settings_screen.dart` theme grid:**
- 2 columns × 11 themes = 6 rows
- `childAspectRatio: 1.6` → cards become 110×69 on a 360px screen
- Icons + 3 colored dots + name + check overlay all fight for space

**P1 — `home_screen.dart` Quick Actions row:**
- 4 `Expanded` tiles in a `Row`. Each gets ~80px on a 360px screen.
- Icon (22px) + 10px gap + 2-line text — text wraps to 3 lines on small devices.
- Tile height grows to accommodate, makes cards inconsistent.

**P1 — `vendor_pull_tab.dart` positioning:**
- `top: MediaQuery.of(context).size.height * 0.45` — fine on phone, drifts on tablet
- `left: -28 + _dragX` — the rotated pill stick out 28-ish pixels. On phones with rounded corners (every modern phone) this can be invisible.

**P1 — `premium_bottom_nav.dart`:**
- `bottom: bottomPadding + 16` — fine
- `left: 24, right: 24` — wastes 48px of horizontal space. On 360px screens the nav is 312px wide, 5 items × 62px each. Icons crowd. Should be `left: 12, right: 12` on small screens.

**P2 — Chat input bars** in transaction chat / friend chat overlap with the keyboard on small Androids. Need `resizeToAvoidBottomInset` and proper `SafeArea`.

**P2 — Long usernames/emails** truncate inconsistently. Some screens use `overflow: TextOverflow.ellipsis`, others don't, leading to row overflow with "RIGHT OVERFLOWED BY 23 PIXELS" debug paint in dev.

**P2 — The success-celebration overlay** uses fixed pixel sizes for the Lottie animation. Doesn't center properly on tablets.

---

## §11 — Premium feel — what's missing

The user said: "it needs to look way more premium than all the other fintech applications."

What premium fintech apps consistently do that Azaman doesn't:

**P1 — Live skeleton loaders** during every fetch. Never see a spinner.

**P1 — Page transitions are cohesive.** Currently every screen uses the default platform `MaterialPageRoute` push, which means iOS gets the slide-from-right and Android gets the fade. A premium app picks one (usually a custom slide+fade) and uses it everywhere via `pageBuilder`.

**P1 — Numbers animate.** When the balance updates, the new value tweens from old to new (`AnimatedFlipCounter` package). Right now it just snaps.

**P1 — Haptics are inconsistent.** Some buttons have `HapticFeedback.lightImpact()`, others have `mediumImpact`, others have none. Pick a system: light for nav, medium for confirms, heavy for warnings/errors. Apply across the board.

**P1 — Bottom-sheet modal style** for "are you sure?" actions instead of `AlertDialog`. Bottom sheets feel native on both iOS and Android.

**P1 — A consistent confirmation flow for financial actions.** Use `slide_to_confirm.dart` (the widget exists, used in 0 places) on every high-stakes action: send money, withdraw, complete trade. Slide-to-confirm + biometric prompt.

**P1 — Premium typography.** The app currently uses default `Roboto`. Premium apps load a real font (SF Pro on iOS, Inter or Manrope on Android) via `pubspec.yaml > fonts`. One-line config change, transforms the visual identity.

**P1 — Status bar style** is not adjusted for theme. Switching to a light theme leaves you with a white status bar with white icons (invisible). Need `SystemChrome.setSystemUIOverlayStyle` in the theme provider.

**P1 — No app icon / splash redesign.** The current launch icon is the Flutter default in some places. Should be a proper Azaman mark.

**P2 — Sound design.** Premium apps play subtle sounds on success / error. Optional but a nice touch.

**P2 — Empty-state illustrations.** Right now empty lists show "No items". Premium apps show a Lottie or vector illustration + a friendly headline + a primary CTA.

**P2 — A "what's new" sheet** on first launch after an update. Lottie + 2-3 highlights + a "Got it" button. Tells the user the app is alive.

**P2 — Onboarding skippability.** Right now the onboarding is gated by the backend. Should also be skippable client-side with a "I'll do it later" option that doesn't block the home screen.

---

## §12 — State management hygiene

The app is "Riverpod first" but has cobwebs from a previous `Provider` migration.

### Findings

**P2 — `AuthProvider`, `ThemeProvider`, `SettingsProvider` are all `ChangeNotifier`.** That's fine but they each notify on _any_ change, so a `notifyListeners()` from a balance update can repaint the AppBar's role badge, the home screen's news card, and the drawer's profile card all at once. Migrate to `StateNotifier` over time and use `select` aggressively.

**P2 — `tradeProvider.toggleRole`** is the source of truth for the user's active role (user vs vendor). But `authProvider.isVendor` (derived from JWT) is _also_ a source of truth. They can disagree. Pick one: either a vendor's "current view" (user/vendor) is local UI state and shouldn't influence behavior, or it's a real role switch and both should align.

**P2 — `ValueNotifier<List<P2POrder>>` in `main.dart`** is a third state-management pattern outside Riverpod. Migrate to a Riverpod provider.

**P2 — `friend_provider`, `chat_provider`, `notification_provider`, `marketplace_provider` etc. all subscribe to socket events.** When the user logs out and back in, some providers don't tear down their socket listeners cleanly, so by your second login you have duplicate handlers and notifications fire twice. Need a provider lifecycle audit.

---

## §13 — Orphan and half-wired files (consolidated)

### Fully orphan screens (delete OR wire)

| File | Recommended |
|------|-------------|
| `lib/screens/account_deactivation.dart` | Delete (duplicate of `account_deactivation_screen.dart`) |
| `lib/screens/account_deactivation_screen.dart` | Wire from settings → "Delete Account" |
| `lib/screens/actual_settings_screen.dart` | Merge layout into `settings_screen.dart`, then delete |
| `lib/screens/admin/corporate_purchase_screen.dart` | Wire from admin dashboard OR delete |
| `lib/screens/admin/spy_glass_screen.dart` | Wire from admin dashboard OR delete |
| `lib/screens/admin_spy_screen.dart` | Delete (duplicate of `admin/spy_glass_screen.dart` — pick one) |
| `lib/screens/admin_war_room.dart` | Delete (duplicate, `admin_war_room_screen.dart` is wired) |
| `lib/screens/admin_war_room_alerts.dart` | Delete (no real usage) |
| `lib/screens/chat/direct_message_screen.dart` | Wire from messages hub once backend route exists |
| `lib/screens/chat/transaction_chat_screen.dart` | Delete (duplicate of `chat_screen.dart` lineage) |
| `lib/screens/chat_screen.dart` | Investigate: trade chat? DM? — likely delete |
| `lib/screens/crypto_deposit_screen.dart` | **Wire from Home → Quick Actions → Deposit → "Crypto"** |
| `lib/screens/fiat_deposit_flow_screen.dart` | **Wire** (this is the multi-step flow) |
| `lib/screens/fiat_wallet_screen.dart` | Wire OR delete |
| `lib/screens/leaderboard_screen.dart` | **Wire** (gamification feature; backend has it) |
| `lib/screens/messages_hub_screen.dart` | Wire (DM hub) |
| `lib/screens/notification_screen.dart` | Delete (duplicate of `notification_hub_screen.dart`) |
| `lib/screens/profile_details_screen.dart` | Wire from profile → "Edit profile" |
| `lib/screens/referral_screen.dart` | **Wire** from settings drawer → "Refer & Earn" |
| `lib/screens/security_settings.dart` | Wire OR merge into settings |
| `lib/screens/signup_screen.dart` | Delete (duplicate of `auth/signup_screen.dart`) |
| `lib/screens/trade_appeal_sheet.dart` | Wire from active trade → dispute |
| `lib/screens/user_dashboard.dart` | Investigate (class name `RealAd` — looks like dev sandbox), likely delete |
| `lib/screens/vendor_apply.dart` | **Wire from vendor pull tab when role != vendor** |
| `lib/screens/vendor_deposit_screen.dart` | Wire from vendor portal → "Add inventory" |
| `lib/screens/waiting_room_screen.dart` | Wire from match-making in P2P |
| `lib/screens/wallet_screen.dart` | Wire from Home → Wallet OR delete (HologramBalanceCard already shows balance) |

### Orphan widgets

| Widget | Usages | Recommendation |
|--------|--------|----------------|
| `skeleton_loader.dart` | 0 | Wire into all list screens |
| `slide_to_confirm.dart` | 0 | Wire into withdraw, send, trade-complete |
| `success_celebration.dart` | check | Likely used in 1 place, expand to all confirms |
| `tech_buttons.dart` | check | Probably stale variant of standard buttons |
| `risk_tag.dart` | check | Wire into ad cards / trade summary |

### Orphan files outside lib/screens

- `lib/theme/app_theme.dart` — delete (dead code)

### Other

- `service-account.json.json` — DELETE from repo, rotate Firebase key. See §14.

---

## §14 — Security: secrets in the repo

`service-account.json.json` is committed to the frontend repo (note the doubled `.json.json` extension — a copy-paste artifact that suggests this was added in a hurry and never reviewed).

This is a Firebase Admin SDK service account file. It should:
- **Never** be in a client app — clients only need the public Firebase config (apiKey, projectId, etc., which are safe to ship).
- Be rotated immediately.
- Be removed from git history (not just the working tree).

The frontend should authenticate to FCM the user's device token via the backend, never via this admin file.

**Action:**
1. Rotate the key in Firebase console.
2. `git rm` the file + add to `.gitignore`.
3. `git filter-repo` (or BFG) to scrub history.
4. Audit `pushNotificationService.dart` to ensure it doesn't actually load this file at runtime — if it does, replace with the public config approach.

---

## §15 — Backend endpoints that don't have a UI yet

Reverse view: routes the backend exposes that the frontend has no UI for. These represent features that are "built" on the backend but invisible to the user.

| Backend route | Suggested UI surface |
|---------------|----------------------|
| `POST /api/auth/sso/google` | "Continue with Google" on login |
| `POST /api/auth/sso/apple` | "Continue with Apple" on login |
| `GET /api/security/log` | Settings → "Account Activity" (login history) |
| `POST /api/security/change-password` | Settings → "Change Password" |
| `GET /api/notifications` | Settings → "Notification Preferences" detail screen |
| `POST /api/users/preferences` | Settings → various tiles (currency, language, etc.) |
| `GET /api/vendor/leaderboard` | New tab or Home → "Top Vendors This Week" |
| `GET /api/vendor/stats` | Vendor portal → "My Stats" detail |
| `GET /api/savings/goals` + `POST /api/savings/fund` | Savings tab → Already has UI but not wired |
| `GET /api/admin/users` etc. | Admin dashboard already has stubs |
| `POST /api/kyc/submit` | KYC screen exists, status polling missing |
| `GET /api/oracle/rates` | Home → Live Market section |
| `POST /api/payout-destinations` | Saved Wallets screen exists, half-wired |
| `GET /api/messages/conversations` | Messages hub (orphan screen exists!) |

---

## §16 — Suggested frontend fix plan

This is the matching plan to backend `AUDIT.md §16`. **The user's directive is to land backend Phase A first, then frontend.** Each phase is a separate PR.

### Phase A — Mirror of backend money fixes (after backend A merges)

1. Wire `WithdrawalScreen` to `POST /api/withdraw/process`.
2. Wire `TransferModal` (friends transfer) to `POST /api/finance/transfer` with idempotency key (UUID per attempt).
3. Wire `SavingsScreen.fundGoal` to `POST /api/savings/fund`.
4. Surface withdrawal status updates over socket.
5. Show TransactionHistory list on the wallet/profile screens (already exists on backend).

### Phase B — Settings overhaul (the user's specific complaint)

6. Merge `actual_settings_screen` layout + `settings_screen` wiring into one clean screen.
7. Build `theme_picker_screen.dart` as a dedicated child screen.
8. Add `AzamanTheme.system` (auto-switch on platform brightness).
9. Wire SSO buttons (Google + Apple) on login.
10. Wire "Change Password" + "Account Activity" tiles in settings.
11. Wire "Notification Preferences" detail screen.

### Phase C — Home screen overhaul (premium feel)

12. Wire all 4 Quick Actions to real navigation.
13. Replace hardcoded "Core Assets" with live `/api/oracle/rates` data.
14. Replace "Platform News" with backend-driven news endpoint (or remove until we have one).
15. Add "Today" widget — active trades, recent transactions, friend requests.
16. Animated number tweens on balance updates.
17. Wire `skeleton_loader` into all home-screen async sections.

### Phase D — Wiring + cleanup (the orphan sweep)

18. Move every `Navigator.push(MaterialPageRoute(...))` to `context.push('/path')` and add the matching GoRoutes.
19. Wire vendor pull tab → vendor_apply / vendor_dashboard / KYC depending on user state.
20. Remove the chat icon from the AppBar.
21. Wire orphan screens listed in §13: leaderboard, referral, deposit flows, messages hub, profile details.
22. Delete confirmed-dead screens (12 files, see §13 table).
23. Delete `lib/theme/app_theme.dart`.
24. Delete `service-account.json.json` + rotate key.

### Phase E — Premium polish

25. Apply `slide_to_confirm` to all financial confirms.
26. Apply biometric prompt to all financial confirms.
27. Apply `skeleton_loader` to every list screen.
28. Custom page transition (slide+fade) applied app-wide.
29. Custom font (Inter/Manrope/SF Pro) loaded via pubspec.
30. Status bar style synced to theme.
31. Empty-state illustrations.
32. Standardize haptics: light = nav, medium = confirm, heavy = warn.
33. Use bottom-sheet modals instead of AlertDialog for confirms.
34. Animated balance counter (`animated_flip_counter` package).
35. Connectivity banner (`connectivity_plus` package).

### Phase F — Mobile layout pass

36. Settings theme picker — replace grid with full-page picker.
37. Home Quick Actions — fix overflow on small phones.
38. Vendor pull tab — adjust positioning for rounded-corner phones.
39. Premium bottom nav — adaptive horizontal margins.
40. Chat screens — fix keyboard overlap.
41. Truncation pass — every Row with text gets `overflow: ellipsis`.
42. Test on 360×640, 390×844, 414×896, 430×932 viewports.

### Phase G — Robustness

43. Root error boundary widget.
44. Provider lifecycle audit (clean teardown on logout).
45. Refresh token flow (matches backend Phase C).
46. Migrate `AuthProvider`, `ThemeProvider`, `SettingsProvider` to `StateNotifier` over time.
47. Remove `ValueNotifier` patterns from `main.dart`, migrate to Riverpod.

---

## §17 — Out-of-scope for this audit

- I did not run the app. The findings come from reading the source.
- I did not test on physical devices. All layout findings come from inferring widget tree size constraints.
- I did not audit the `android/`, `ios/`, `web/`, `windows/`, `linux/`, `macos/` platform folders.
- I did not look at `test/widget_test.dart` (it's the default Flutter scaffold — likely useless).

---

## §18 — Quick-win order

If you want a "feel-the-difference within 24 hours" sequence to keep momentum, here's the order I'd execute even before Phase A:

1. **Delete `lib/theme/app_theme.dart`.** (5 minutes.)
2. **Delete `service-account.json.json`** + add to gitignore. (5 minutes; rotate key in console.)
3. **Fix vendor pull tab visibility** — show for everyone, route by role. (30 minutes.)
4. **Remove the AppBar chat icon.** (5 minutes.)
5. **Wire the 4 Home Quick Actions to real navigation.** (30 minutes.)
6. **Delete the 12 confirmed-dead screen files.** (10 minutes.)
7. **Fix the settings theme grid mobile layout.** (30 minutes.)

That's a 2-hour PR that ships immediately and addresses every visible complaint the user listed. After that, Phase A (backend money) → Phase A (frontend money) → Phase B (settings overhaul) is the strategic order.

---

*Audit complete. Awaiting backend Phase A merge before opening frontend Phase A PR.*
