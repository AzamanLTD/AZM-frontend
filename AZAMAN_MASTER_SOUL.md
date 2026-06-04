AZAMAN V2: THE MASTER SOUL
Identity: Enterprise Neo-Bank & P2P Crypto Exchange Hybrid.
Scale Target: Millions of Users.
This document is the immutable source of truth for the Azaman V2 architecture. It supersedes any legacy code, previous implementations, or generic AI assumptions.

CHANGELOG (most recent first)
- 2026-05-27 — Phase H12: shared idempotency-key util + savings deposit retry safety (FE PR, in review)
  - **CRITICAL — savings deposit retry double-debit.** The BE `savingsController.deposit` previously had no idempotency key, so two concurrent calls (network retry, FE double-tap on the deposit button) both passed the balance check and both ran the full debit + goal credit + ledger insert. The H12 BE half added `clientRequestId` support; this FE PR feeds it.
  - **`lib/utils/idempotency_key.dart`** — new shared util that generates RFC 4122 v4-style UUIDs using `Random.secure()`. Extracted from the inline helper in `friend_service.dart` so other money-moving endpoints (savings, future flows) can share one generator. Avoids pulling the `uuid` package for one helper.
  - **`savings_goal_sheet._deposit`** now sends `clientRequestId: IdempotencyKey.generate()` on every deposit POST. Network retries on transient errors are now safe — duplicate requests hit the BE's `@unique` txHash constraint and roll back inside the transaction.
  - **`FriendService.sendFunds` / `requestFunds`** refactored to use the shared `IdempotencyKey.generate()` instead of the private `_generateRequestId` from H6. Behaviour unchanged; one canonical generator now.
  - Files (3 NEW + 2 modified + 2 docs): `lib/utils/idempotency_key.dart` (NEW), `lib/services/friend_service.dart`, `lib/widgets/savings_goal_sheet.dart`. Plus `AZAMAN_MASTER_SOUL.md` + `FRONTEND_AUDIT.md`.
- 2026-05-27 — Phase H10: vendor ad creator + fiat deposit screen polish (FE PR, in review)
  - **CRITICAL — vendor ad creator: time-format wire bug.** `_publishAd` was sending `_activeHoursStart.format(context)` for the active-hours payload — which returns a localized string like `"8:00 AM"` on a 12-hour locale device or `"08:00"` on a 24-hour one. The BE expects `HH:mm` 24-hour. On 12-hour locales, ads were either rejected by the BE or stored with garbage active hours that never matched the trade-time-window check. Fixed by adding a `_formatTimeWire(TimeOfDay)` helper that always emits zero-padded 24-hour `HH:mm`.
  - **Vendor ad creator: dead "+ Deposit" button.** `_showDepositModal` showed a snackbar reading `"Deposit flow opening..."` and did nothing else. Now actually pushes `DepositScreen` (the unified deposit hub with crypto + mobile money tabs). After pop, `_fetchVendorData` re-runs so the collateral check uses the latest available balance.
  - **Vendor ad creator: active-hours validation.** Step-1 → Step-2 transition now validates that start ≠ end (a zero-length active window would produce an ad that never matches a buyer). Combined with the existing balance / limit checks, the user can't ship an unusable ad.
  - **Vendor ad creator: step-2 → publish boundary check.** Final step's "Publish" button now blocks the user with a precise error if no `_selectedTradeAccount` is set, BEFORE the publish round-trip. Previously the user could tap publish, submit, and watch it fail with a generic error.
  - **Fiat deposit screen: instructions-list overwrite.** The `data['instructions']` list iterator was assigning every entry to the same `'Note'` key — only the LAST instruction was rendered. Now each instruction gets its own `Note 1`, `Note 2`, … key (or just `Note` when there's exactly one).
  - **Fiat deposit screen: dispose() leak.** No `dispose()` method meant the amount `TextEditingController` leaked one instance per navigation. Added `dispose()`.
  - Files (2 + 2 docs): `lib/screens/vendor_ad_creator.dart`, `lib/screens/fiat_deposit_screen.dart`. Plus `AZAMAN_MASTER_SOUL.md` + `FRONTEND_AUDIT.md`.
- 2026-05-27 — Phase H7: Active trade timer + transfer idempotency + pull-tab leak (FE PR, in review)
  - **CRITICAL — active trade screen: extension double-counted.** `_requestTimeExtension` was bumping `_secondsRemaining += addedMinutes * 60` locally AND the BE ack `time_extended` socket event was bumping it again on arrival. Pressing the +15 chip actually gave +30 to whoever clicked. The optimistic local bump is now removed — the FE waits for the server's `time_extended` event which carries the canonical `newExpiresAt`. Single source of truth.
  - **CRITICAL — active trade screen: extensions wiped within 1 second.** `_recomputeRemaining` was computing `_secondsRemaining = 15min - (now - createdAt)` on every Timer.periodic tick. The screen ignored `Trade.expiresAt` entirely, so any extension (correctly persisted on the BE) was overwritten by the FE's local recomputation within 1 second. Fixed by anchoring to `_tradeExpiresAt` (sourced from `Trade.expiresAt`, falling back to `createdAt + selectedTimeframe` for older BE deploys). Extensions now land instantly and persist across reopen.
  - **Active trade screen: message duplication on mid-conversation reload.** `_onNewMessage` deduped by message id, but `_syncTradeState`'s history loader didn't include the id field on loaded entries. A realtime push that landed during the sync round-trip would slip past the dedup check and render twice. Fixed by including `id` and `createdAt` on the loaded history entries.
  - **CRITICAL — friend transfer: missing idempotency key.** `FriendService.sendFunds` and `requestFunds` weren't sending `clientRequestId`, even though the BE explicitly supports it for retry safety. Without the key, any retry on a transient network error WAS a fresh debit. Now generates a v4-style UUID per call (using `Random.secure()` to avoid pulling in the `uuid` package for one helper) and ships it in the body. The BE derives `TransactionHistory.txHash` from the key, so duplicate requests hit the `@unique` constraint and are rejected before any second balance mutation can commit.
  - **Friend transfer: in-flight guard added** to `_executeTransfer`. The slide-to-confirm widget already has internal `_confirmed` to prevent re-fire, but defense-in-depth on the highest-stakes financial commit is cheap. If a future surface drives this method without the slider, it still won't double-debit.
  - **Vendor pull-tab: listener leak fixed.** `_onDragEnd` was calling `_snapController.addListener(...)` every time the user dragged the tab — listeners accumulated without ever being removed. After N drags, the (N+1)th drag fired N setState() calls per animation tick (quadratic rebuild storm + memory leak). Listener is now installed ONCE in `initState` and reads `_snapAnimation.value` directly (the field is reassigned per drag-end, but the controller is the same — driving the listener via `.value` Just Works).
  - Files (4): `lib/screens/active_trade_screen.dart`, `lib/services/friend_service.dart`, `lib/screens/friends/transfer_modal.dart`, `lib/widgets/vendor_pull_tab.dart`. Plus `AZAMAN_MASTER_SOUL.md` + `FRONTEND_AUDIT.md`.
- 2026-05-27 — Phase H6: Withdrawal + P2P + drawer bug-hunt sweep (FE PR, in review)
  - **CRITICAL — withdrawal screen double AZM debit fixed.** `_submitMobileMoney` was calling `azmSpendProvider.applyFeeDiscount(tierId)` on the FE AND sending `feeDiscountTierId` in the request body. The BE `fiatWithdrawal` controller forwards that body field to `azmSpendService.applyFeeDiscount`, so AZM was being debited TWICE per withdrawal — once from the FE pre-call, then again inside the BE controller. The fix: forward the tier id only and let the BE be the single source of truth. The BE was always running the AZM debit inside the same logical flow as the withdrawal anyway, so a withdrawal failure couldn't strand a user without their AZM. Local AZM mirror is now refreshed via `azmSpendProvider.refresh()` after a successful withdrawal, replacing the previous optimistic local update.
  - **Withdrawal screen — wrong balance cap on crypto path fixed.** `_submitCryptoWallet` was capping the balance check at `_azmBalance` for non-vendor users, reflecting the obsolete Phase D-2 state where AZM was the withdrawal currency. Phase D-3 reverted that and AZM is strictly a loyalty-point ledger now. The BE `walletController.requestWithdrawal` debits `availableBalance` (USDC) for ALL roles. The FE check now mirrors that — every user, vendor or not, withdraws USDC from `availableBalance`.
  - **Withdrawal screen — stale balance label fixed.** Header was showing "USDT" for vendor crypto withdrawals and "AZM" for non-vendor crypto withdrawals. Both are wrong — withdrawals are USDC end-to-end. Now shows "USDC" regardless of mode and role.
  - **Withdrawal screen — error surface for AZM_SPEND_FAILED.** When the BE `code: AZM_SPEND_FAILED` is returned (insufficient AZM, invalid tier), the snackbar now reads "AZM discount failed: {message}" so the user knows their USDC is untouched and only the discount half failed.
  - **Withdrawal screen — dead state cleanup.** Retired the `_isApplyingDiscount` flag (set/cleared but never read) and the local `_azmBalance` mirror (now read live from `azmSpendProvider.options.currentBalance` — single source of truth, kept fresh by the spend service after every debit).
  - **P2P marketplace — flip-card success navigation fixed.** `_initiateTradeFromFlip` only handled the queued branch (snackbar). When the vendor was available and the trade went straight through, the user got NO success feedback and was stranded back on the marketplace with no way to reach the trade chat. Now mirrors the legacy `_TradeConfirmSheet` handler — queued → push `WaitingRoomScreen`, immediate → push `ActiveTradeScreen` with the proper `tradeId` and amount.
  - **Settings drawer — Recommended section filled out.** Section had only Security Center + Referral Rewards. Added AZM Rewards (`AzmRewardsScreen`) and Theme (`ThemePickerScreen`) tiles — both standalone screens with proper AppBars + back arrows so the user can return without getting stranded. The drawer "RECOMMENDED" header now leads to four real destinations.
  - Files (3): `lib/screens/withdrawal_screen.dart`, `lib/screens/p2p/p2p_marketplace_screen.dart`, `lib/widgets/settings_drawer.dart`. Plus `AZAMAN_MASTER_SOUL.md` + `FRONTEND_AUDIT.md`.
- 2026-05-27 — Phase UI-7-B: FriendsHub list — trust signals + nested-shape bugfix (FE PR, in review)
  - **Trust line on every friends list row.** `_buildFriendTile` in `friends_hub_screen.dart` now renders a slender second line under the username: `⭐ {rating} · {N} completed`. Verified vendors get the theme-accent ✓ inline next to the name. Brand-new accounts with no signal yet (no rating + zero completed) suppress the trust line entirely so they don't carry a misleading "0 completed" stamp. Same metric definition the chat AppBar surfaces (Phase UI-6 / UI-7 backend) — the two now agree row-for-row.
  - **Nested-shape bugfix.** While wiring trust signals, found that `_buildFriendTile` was reading the BE response with the WRONG shape: `friend['username']` and `friend['lastMessage']` as flat top-level keys. The actual response shape from `controllers/friendController.getFriends` is `{ friendshipId, friend: {username, ...}, latestMessage: {content, createdAt}, unreadCount, friendSince }` — nested. The previous tile was therefore silently rendering "Unknown" for every username and "" for every last-message preview, falling back to the "Start chatting..." placeholder. Now reads the nested objects correctly with the legacy flat keys retained as defensive fallback. (User-visible: chats list will start showing real names + previews on next refresh.)
  - **`_handleFriendMessage` socket handler** now writes the new message into the nested `latestMessage` shape so the tile renders consistently whether the row arrived from REST `getFriends` or the live socket update. Legacy flat fields are still mirrored alongside for any older code path that still reads them.
  - **`fetchFriends` sort** rewired to read from `latestMessage.createdAt` first, then fall back to the legacy flat key. Defensive against an older BE response missing the nested field.
  - Files (3 + 2 docs): `lib/screens/friends/friends_hub_screen.dart`, `lib/providers/friend_provider.dart`. BE: `controllers/friendController.js`. Plus `AZAMAN_MASTER_SOUL.md` + `FRONTEND_AUDIT.md`.
- 2026-05-27 — Phase UI-7: Trust breakdown drilldown — tap-popup + vault identity refresh (FE PR, in review)
  - **Tappable trust line in the chat AppBar.** The persistent `⭐ {rating} · {N} Completed Transactions` subtitle from Phase UI-6 is now wrapped in a `GestureDetector` (HitTestBehavior.opaque so the tap doesn't bubble up to the parent vault-screen route). Tapping opens a bottom sheet with the per-category breakdown: P2P Trades / Peer Transfers / Tickets Closed, plus the rating + review count + Verified Vendor caption.
  - **New reusable widget `lib/widgets/trust_breakdown_sheet.dart`** with public `showTrustBreakdownSheet(...)` entry point. Pure presentational — accepts `TrustBreakdown`, rating, review counts, and `isVerifiedVendor` booleans, renders a clean modal sheet. Reused by both the chat AppBar (driven by `chatTrustMetricsProvider`) and the Chat Profile vault identity tier card (driven by the already-loaded `chatProfileProvider` payload — instant, no extra round-trip).
  - **Vault identity tier refreshed.** The `_StatPill` row on `chat_profile_screen.dart` previously showed "Mutual trades / Their trades / Completion%". The middle pill ("Their trades") only reflected `User.tradesCompleted` (P2P only) and was misleading next to the chat AppBar that surfaces the global count. Replaced with: **Completed** (global, tappable, accent-highlighted) → **Rating** (5-star scale, matches header) → **Mutual** (relationship-specific). The two surfaces now agree.
  - **`_StatPill` upgraded** with optional `onTap` + `highlight` props. Highlight tints the pill with the theme accent and adds a chevron, signalling "this drills down" without a separate CTA. Non-tappable pills render exactly as before — fully backwards-compatible.
  - **Verified Vendor badge in the title row** now prefers the theme-accent `Icons.verified_rounded` for `isVerifiedVendor` users, falls back to the green KYC tick for normal `VERIFIED` users. Both states have a Tooltip so screen readers and long-press users get the label.
  - **`ChatProfileFriend` + `ChatTrustMetrics` extended** with `TrustBreakdown` (`tradesCompleted` / `completedTransfers` / `closedTickets`). Defensive — falls back to `TrustBreakdown.empty` when an older BE deploy is in front of a new FE build, so the breakdown sheet still renders (with sensible zeros) instead of crashing.
  - **No regressions.** UI-6 code paths still work: an FE without UI-7 reads the same `completedTransactions` number it always read; a BE without UI-7 still serves the rolled-up number to current FEs.
  - Files (3 NEW + 3 modified + 2 docs): `lib/widgets/trust_breakdown_sheet.dart` (NEW), `lib/services/chat_profile_service.dart`, `lib/screens/friends/friend_chat_screen.dart`, `lib/screens/chat_profile_screen.dart`. BE: `controllers/chatProfileController.js`. Plus `AZAMAN_MASTER_SOUL.md` + `FRONTEND_AUDIT.md`.
- 2026-05-27 — Phase UI-6: Social Trust Metrics in chat header (FE PR, in review)
  - **Persistent trust line in chat AppBar.** `friend_chat_screen.dart` AppBar title was previously `username` plus a transient `typing...` subtitle that only appeared while the friend was typing. Replaced with a stacked block: username + verified-vendor checkmark on the top row, and a PERSISTENT trust line beneath: `⭐ {rating} · {N} Completed Transactions`. The typing indicator now FADES IN as a transient overlay via `AnimatedSwitcher` and the trust line fades back the moment typing stops — no row-height bounce, no lost reputation context. The verified ✓ trailing icon (using `Icons.verified_rounded` in the theme accent colour) renders only when the BE flags `isVerifiedVendor: true` (i.e. `role === 'VENDOR' && kycStatus === 'VERIFIED'`).
  - **The metric is GLOBAL, not just P2P.** Per the brief: trust applies to BOTH regular users and vendors because every successful transaction has two committed parties. `completedTransactions` is the sum of three signals: `User.tradesCompleted` (P2P escrow trades) + count of `PeerTransfer` rows with `status='COMPLETED'` for that user + count of `Ticket` rows with `status='CLOSED'` where the user was creator or counterparty. Each count is computed in parallel server-side with a graceful `.catch(() => 0)` so a single index outage never blocks the AppBar from rendering.
  - **Rating is null-safe.** Derived as `(positiveReviews / (positiveReviews + negativeReviews)) * 5`, returned as a Number with one decimal. When the friend has zero reviews, BE returns `rating: null` and the FE suppresses the star icon entirely so brand-new accounts don't show a misleading 0.0-star rating.
  - **New BE endpoint `GET /api/friends/:friendshipId/trust-metrics`** in `controllers/chatProfileController.js` `getTrustMetrics`. Lightweight subset of `getProfile` — skips mutual-trade aggregation and nickname JSON pluck because the chat AppBar opens far more frequently than the vault. Two parallel COUNTs + one User row, participant-gated via the existing `_verifyParticipant` helper. Mounted in `routes/friendRoutes.js`.
  - **`getProfile` also enriched.** Same trust signals (`completedTransactions`, `rating`, `isVerifiedVendor`) are now surfaced on the friend object returned to the Chat Profile vault screen so the identity-tier card can show them too in a future polish pass.
  - **New FE Riverpod family `chatTrustMetricsProvider(friendshipId)`** in `lib/providers/chat_trust_metrics_provider.dart` — `StateNotifierProvider.family` with `primeIfNeeded()` (idempotent first-fetch) and `refresh()` (force re-fetch). The chat screen primes it post-frame on mount.
  - **Real-time bumps without polling.** `friend_chat_screen.dart` now listens to two new socket triggers that bump the count: a `TRANSFER_COMPLETED` direct-message event refreshes immediately (peer-transfer fulfillment), and any `ticket_status_changed` event for this friendship triggers a refresh (covers CLOSED, CANCELLED, REOPENED — closing one count flow always converges to the right total). No tracker maintained client-side; one cheap refresh per state-changing event is correct by construction.
  - **`ChatTrustMetrics` model + `getTrustMetrics()`** added to `lib/services/chat_profile_service.dart`. Defensive int/double parsing — coerces strings, ints, or null gracefully so a stale older BE deploy never crashes a newer FE build.
  - Files (3 NEW + 3 modified + 2 docs): `lib/providers/chat_trust_metrics_provider.dart` (NEW), `lib/services/chat_profile_service.dart`, `lib/screens/friends/friend_chat_screen.dart`. BE: `controllers/chatProfileController.js`, `routes/friendRoutes.js`. Plus `AZAMAN_MASTER_SOUL.md` + `FRONTEND_AUDIT.md`.
- 2026-05-26 — Phase UI-POLISH: voice notes + vault polish (FE PR, in review)
  - **In-bubble inline audio playback.** `chat_media_bubble.dart` `_AudioBubble` rewritten from a stateless launcher into a stateful inline player using `audioplayers: ^6.1.0`. Tap the play circle to play/pause; the waveform bars colour-fill in proportion to playback position; the duration label flips between elapsed and total time during playback. Tap or drag horizontally on the waveform to seek. Globally only one audio bubble plays at a time — `_AudioBubblePlayerRegistry` singleton pauses every other registered player when a new one starts (WhatsApp / iMessage parity). Falls back to `_openInSystemViewer` if the codec isn't supported by audioplayers.
  - **Hold-to-record voice notes.** New `lib/widgets/audio_recorder_button.dart` is the canonical mic widget used by both `friend_chat_screen.dart` and `ticket_workspace_screen.dart`. Long-press starts recording (haptic + recording strip with pulsing red dot + elapsed time + slide-to-cancel hint); slide left past 80px turns the indicator red and arms cancel; release commits via `onRecorded(file, duration, peaks)`. Uses `record: ^6.2.0` (already in pubspec) configured for AAC LC at 96kbps / 44.1kHz. Sub-700ms recordings are discarded as accidental taps. Mic permission is requested via `record.hasPermission()` with a graceful snackbar fallback. `onAmplitudeChanged` stream samples down to 50 buckets max so the JSON payload matches the Phase UI-3 BE waveformPeaks contract.
  - **Input-bar swap (mic vs send).** Both `friend_chat_screen.dart` `_buildInputBar()` and `ticket_workspace_screen.dart` `_InputBar` now show the mic when the text field is empty and swap to the send arrow as soon as the user types. New `_isUploadingAudio` state on each screen locks the mic while a voice-note upload is in flight so a fast second hold can't kick off a parallel upload.
  - **AUDIO + IMAGE + VIDEO + DOCUMENT + LINK rendering wired into friend chat.** `friend_chat_screen.dart` message dispatcher now routes any of those five types through `ChatMediaBubble`, so a voice note (or any other media) sent from one device renders correctly on the other side without a code change.
  - **`FriendService.sendMessage` extended** with optional Phase UI-3 media kwargs (`messageType`, `mediaUrl`, `mediaType`, `mediaMimeType`, `mediaSize`, `mediaDuration`, `mediaWaveformPeaks`, `linkPreview`, `metadata`). The BE half (`directMessageController.sendMessage`) already accepted these in Phase UI-3; the FE service signature was the missing link for FE-originated media sends.
  - **Tickets vault tab counter badge.** `chat_profile_screen.dart` Tickets and Receipts tab labels now render with a count chip when count > 0 (capped at "99+") so users can see at a glance how much history exists in each. Implemented via a new `_CountedTab` widget that reads `ticketDashboardProvider` for tickets and the local profile state for receipts.
  - **Receipts cursor pagination.** `chat_profile_provider.dart` extended with `receiptsHasMore`, `receiptsNextCursor`, `receiptsLoadingMore`, plus a new `loadMoreReceipts()` method. The receipts tab now renders a "Load more" outlined button as the last list item when more pages exist; tapping it appends the next 50. The BE already served `nextCursor` + `hasMore` from Phase UI-5; the FE was capping at the first 50 until now.
  - **`pubspec.yaml`:** added `audioplayers: ^6.1.0`. The `record` package is unchanged; we use it for capture only.
  - Files (3 NEW + 6 modified + 1 pubspec + 2 docs): `lib/widgets/audio_recorder_button.dart` (NEW), `lib/widgets/chat_media_bubble.dart`, `lib/screens/friends/friend_chat_screen.dart`, `lib/screens/tickets/ticket_workspace_screen.dart`, `lib/screens/chat_profile_screen.dart`, `lib/providers/chat_profile_provider.dart`, `lib/services/friend_service.dart`, `pubspec.yaml`. Plus `AZAMAN_MASTER_SOUL.md` + `FRONTEND_AUDIT.md`.
- 2026-05-26 — Phase UI-5: Chat Profile + Transaction Vault (BE + FE, in review)
  - **BE half:** No new schema migration — `Friendship.localNicknames` JSONB shipped with Phase UI-4. New `controllers/chatProfileController.js` with five participant-gated endpoints (GET profile, PATCH nickname, GET media, GET docs-links, GET receipts). `services/receiptService.js` extended with `generateTransferReceipt(transfer, observer)` for immutable peer-transfer PDF receipts. New `GET /api/receipts/transfer/:id` route. Receipts are defined as immutable records of direct P2P off-ticket money transfers (the "send money with reason" PeerTransfer flow) — first-class artifacts with reference IDs and downloadable PDFs that cleanly differentiate casual balance transfers from structured ticket deals or formal P2P trades.
  - **FE half:** New `lib/services/chat_profile_service.dart` (typed REST client + models for profile, vault items, receipts), `lib/providers/chat_profile_provider.dart` (Riverpod family with parallel `primeAll()` + per-tab refresh + optimistic-with-rollback nickname updates), `lib/screens/chat_profile_screen.dart` (full screen with identity tier card + tabbed vault). Identity tier shows avatar, username (or local nickname when set, with @username subtitle), "Friends since" date, KYC verified badge, and three stat pills (mutual trades, their trades, completion %). Inline edit pencil opens a nickname dialog with save/clear/cancel. Vault tabs: **Media** (3-column grid mixing DirectMessage + TicketMessage, with TICKET ribbon overlay on ticket-source items), **Docs & Links** (list with mime-aware icons + OG link cards), **Tickets** (reuses Phase UI-4 `ticketDashboardProvider`, all three statuses sorted by lastActivityAt), **Receipts** (PeerTransfer rows with direction arrows, status chips, and PDF download buttons that fetch from the new `/api/receipts/transfer/:id` endpoint and open via `open_filex`).
  - **`friend_chat_screen.dart` rewired:** the AppBar title (avatar + name) is now a tappable region that pushes `ChatProfileScreen`. The existing AppBar Ticket button (Phase UI-4) is unchanged.
  - **No regressions.** All UI-1 through UI-4 surfaces continue to work. The profile screen is reachable only by avatar tap; older builds that don't know about it never see it.
  - Files (BE 3 + 2 routes + FE 3 NEW + 1 modified + 2 docs): `controllers/chatProfileController.js` (NEW), `controllers/receiptController.js`, `services/receiptService.js`, `routes/friendRoutes.js`, `routes/receiptRoutes.js`, `lib/services/chat_profile_service.dart` (NEW), `lib/providers/chat_profile_provider.dart` (NEW), `lib/screens/chat_profile_screen.dart` (NEW), `lib/screens/friends/friend_chat_screen.dart`. Plus `AZAMAN_MASTER_SOUL.md` + `FRONTEND_AUDIT.md`.
- 2026-05-26 — Phase UI-4: Tickets Engine (BE + FE, in review)
  - **BE half (PR pair):** Schema migration `20260526_phase_ui4_tickets_engine` adds `TicketType` (BUY | SELL | ESCROW | SERVICE_SWAP) and `TicketStatus` (OPEN | CLOSED | CANCELLED) enums; new `Ticket` and `TicketMessage` tables. `Friendship.localNicknames` JSONB column shipped now (used by Phase UI-5 Chat Profile Detail screen). `TicketMessage` reuses every Phase UI-3 media column so `chat_media_bubble.dart` renders identically in tickets and direct chat. New `controllers/ticketController.js` exposes six endpoints (create / list / detail / send-message / status-change / presence-ping) under `/api/tickets`. New `services/ticketSocketService.js` handles `join_ticket`, `leave_ticket`, `ticket_typing` socket events. Server-emitted: `ticket_created`, `ticket_message`, `ticket_status_changed`, `ticket_presence_update`. Status changes inject a TICKET_LINK event card into the parent friendship chat. Tickets do NOT touch any wallet column or trigger AZM rewards — they are pure chat artifacts.
  - **FE half (PR pair):** New `lib/services/ticket_service.dart` (typed REST client + models), `lib/providers/ticket_provider.dart` (two Riverpod families: dashboard + workspace, with bridge methods for socket events). New screens under `lib/screens/tickets/`: `ticket_dashboard_screen.dart` (3-tab Open/Closed/Cancelled list with FAB + pull-to-refresh), `ticket_create_sheet.dart` (structured creation form with type ChoiceChips, decimal-safe amount, currency dropdown, 500-char memo), `ticket_workspace_screen.dart` (isolated chat surface, header card, presence banner, message list reusing `ChatMediaBubble` from UI-3, AppBar popup menu for close/cancel/reopen, lifecycle-aware presence pings).
  - **`friend_chat_screen.dart` rewired:** the legacy `Icons.swap_horiz_rounded` "Transfer" AppBar icon was REPLACED by a prominent `Icons.confirmation_number_rounded` Ticket button that opens the dashboard. New `_buildTicketLinkBubble()` renders TICKET_LINK event cards in the parent chat feed with a deep-link CTA. New socket listener for `ticket_presence_update` toggles a soft "<friendName> is currently viewing the ticket window." banner above the input bar. Send-money is still reachable via the existing in-chat `+` send-funds button — it's a sibling, not a replacement.
  - **Backwards compat.** Older clients fall through to the existing TEXT-bubble path for unknown TICKET_LINK messages and render the human-readable `content` line. No socket-level coordination required from older builds.
  - Files (BE 4 + 1 migration + FE 5 NEW + 1 modified + 2 docs): `prisma/schema.prisma`, `prisma/migrations/20260526_phase_ui4_tickets_engine/migration.sql` (NEW), `controllers/ticketController.js` (NEW), `routes/ticketRoutes.js` (NEW), `services/ticketSocketService.js` (NEW), `server.js`, `lib/services/ticket_service.dart` (NEW), `lib/providers/ticket_provider.dart` (NEW), `lib/screens/tickets/ticket_create_sheet.dart` (NEW), `lib/screens/tickets/ticket_dashboard_screen.dart` (NEW), `lib/screens/tickets/ticket_workspace_screen.dart` (NEW), `lib/screens/friends/friend_chat_screen.dart`. Plus `AZAMAN_MASTER_SOUL.md` + `FRONTEND_AUDIT.md`.
- 2026-05-26 — Phase UI-3: Chat Media Infrastructure (BE + FE, in review)
  - **BE half (PR pair):** Schema migration `20260526_phase_ui3_chat_media` extends `MessageType` with IMAGE/VIDEO/DOCUMENT/AUDIO/LINK and `DirectMessageType` with the same five plus TICKET_LINK (reserved for Phase UI-4). Adds seven media columns (`mediaUrl`, `mediaType`, `mediaMimeType`, `mediaSize`, `mediaDuration`, `mediaWaveformPeaks`, `linkPreview`) to both `Message` and `DirectMessage`. New `LinkPreviewCache` table for server-side Open Graph metadata cache (24h success TTL, 1h failure TTL).
  - **New service** `services/linkPreviewService.js`: server-side Open Graph fetcher. Caps HTML reads at 256KB, 6s network budget, normalises URLs (strips utm/gclid/fbclid tracking params), sha256 hash cache key. Five status outcomes: OK | FAILED | TIMEOUT | BLOCKED.
  - **Four typed authenticated upload endpoints** (replace the public legacy `/api/chat/upload-media`):
    - `POST /api/chat/upload/image` — 10MB, image/* mime types
    - `POST /api/chat/upload/audio` — 5MB, m4a/mp4/webm/ogg/aac/wav. Optional `duration` + `waveformPeaks` body fields stored verbatim.
    - `POST /api/chat/upload/video` — 50MB, video/* mime types. Optional `duration` field.
    - `POST /api/chat/upload/document` — 25MB, pdf/docx/xlsx/pptx/txt/csv.
    - `POST /api/chat/link-preview` — body `{ url }`, returns cached/fresh OG metadata.
  - **Storage convention** `uploads/chat/<userId>/<kind>/<filename>` so we can audit/garbage-collect per-account.
  - **Legacy `/api/chat/upload-media` retained** (image-only, 8MB, public) to avoid breaking older builds in the wild. New clients target the typed routes.
  - **`directMessageController.sendMessage` extended** to accept all seven media fields. Validation: media-typed messages require `mediaUrl`; ticket-link messages require `metadata.ticketId`. For LINK type, opportunistically fetches OG metadata server-side if the client didn't supply it. FCM push body adapts per media type (📷 Photo, 🎙️ Voice message, etc.).
  - **FE half (PR pair):** New `lib/services/chat_media_service.dart` wraps the four uploads + link preview endpoints with typed `ChatMediaUploadResult` envelopes. `multipart()` calls go through `apiClient` so JWT is attached automatically. New `lib/widgets/chat_media_bubble.dart` is the canonical renderer for all five media kinds — drops into any chat surface (direct, trade, ticket workspace, vault grids). `ChatMediaPayload.fromMessageJson` is the wire-format adapter. New `file_picker: ^8.1.4` dep for document selection.
  - **Audio recorder UI deferred to a polish PR.** The `record: ^6.2.0` package is already in pubspec; the upload pipeline accepts pre-computed waveform peaks so the recorder can drop in without backend changes.
  - **No regression risk for existing chat.** All seven new columns are nullable; legacy TEXT messages render unchanged. The new bubble widget is opt-in per surface.
  - Files (BE 4 + 1 migration + FE 3 + 1 pubspec + 2 docs): `prisma/schema.prisma`, `prisma/migrations/20260526_phase_ui3_chat_media/migration.sql` (NEW), `services/linkPreviewService.js` (NEW), `controllers/directMessageController.js`, `server.js`, `lib/services/chat_media_service.dart` (NEW), `lib/widgets/chat_media_bubble.dart` (NEW), `pubspec.yaml`. Plus `AZAMAN_MASTER_SOUL.md` + `FRONTEND_AUDIT.md`.
- 2026-05-26 — Phase UI-2-FE: Drawer Payout/Deposit Realignment (FE PR, in review)
  - **Drawer "PAYMENT ADDRESSES" pair.** `settings_drawer.dart` "MERCHANT PROTOCOLS" section renamed and rebuilt: two slender tiles (Deposit Addresses → `DepositScreen`, Withdrawal Addresses → `SavedWalletsScreen`) in a single bordered container, separated by a hairline. Down-arrow / up-arrow icons signal funds-in vs funds-out at a glance. The duplicate "Withdrawal Addresses" entry that previously lived under the drawer's "RECOMMENDED" section is removed.
  - **`settings_screen.dart` Trade Accounts tile REMOVED.** Trade Accounts hold global fiat handles (Zelle, CashApp, Venmo, PayPal, Apple Pay, Google Pay, Wise, Revolut, Gift Cards, Western Union, Wire Transfer) that are EXCLUSIVELY used by vendors for P2P ad placements. Surfacing them under user Settings → Payment conflated payout destinations with vendor-side ad-receipt accounts. The vendor dashboard's "MANAGE TRADE ACCOUNTS" button is now the only entry point. Unused `trade_accounts_screen.dart` import dropped.
  - **`saved_wallets_screen.dart` filter hardened.** `_isValidPayoutWallet` now runs an explicit BLOCKLIST first that rejects all 11 global-fiat method types by name. The header doc-comment enumerates the forbidden types verbatim. On-screen helper text updated to direct vendors to the Vendor Dashboard's Trade Accounts area instead of a now-removed Settings link.
  - **No backend changes.** Pure FE nav restructure. The `/api/wallet/saved` and `/api/trade-accounts/*` endpoints are unchanged.
  - Files (3 + 2 docs): `lib/widgets/settings_drawer.dart`, `lib/screens/settings_screen.dart`, `lib/screens/saved_wallets_screen.dart`. Plus `AZAMAN_MASTER_SOUL.md` + `FRONTEND_AUDIT.md`.
- 2026-05-26 — Phase UI-1-FE: De-cluttering Sweep — remove redundant CTAs, slim drawer tiles (FE PR, in review)
  - **Header Chat Icon REMOVED.** The `Icons.chat_bubble_outline_rounded` IconButton in `lib/main.dart` (sat next to the notification bell) was a duplicate entry point for the Friends Hub — Chat is already permanently mounted on the bottom nav bar (`premium_bottom_nav.dart`). Two affordances for one destination produced visual bulk and split user attention. The friend-unread badge logic is also retired here (the bottom-nav Chat tab carries its own unread indicator).
  - **Vendor Pull Tab — first pop-up rewritten.** `vendor_pull_tab.dart` `_VendorRequirementSheet` had a green "Start Application" ElevatedButton that bypassed the deliberate 3-pull confirmation gate. Replaced with a clean text block prompting users to visit `https://azaman.me/vendors` for full details. The 3-pull gate (info → confirm prompt → registration) is now the ONLY in-app path to the application form. Future website logic will instruct visitors to pull this tab 3 consecutive times in-app to unlock the registration layer.
  - **Vendor Ad Cards — "Trade Now" button REMOVED.** `vendor_ad_card.dart` `_CtaRow` no longer renders a primary CTA button. The card-tap → vertical flip-open animation (`ad_detail_flip_card.dart`) is now the sole interaction gateway: tap the card → flips into trade form → submit on the back face. The standalone button was a redundant exit point that bulked out every card in a vertical-scrolling feed. Queue depth is communicated by an existing chip on the card body and tapping a queued ad still routes through the flip overlay.
  - **Settings Drawer — slender payment tiles.** The "MERCHANT PROTOCOLS" section in `settings_drawer.dart` previously rendered `_buildPortalTile`s — chunky 16-pad cards with 40×40 icon containers and verified_user trailing icons. They consumed disproportionate vertical space in a drawer already fighting for real estate. Replaced with a new `_buildSlenderTile` helper: 12-pad list-tile with a 32×32 icon plate, single-line title, single-line subtitle, and a hairline arrow. Same touch targets, half the visual weight.
  - **No backend changes.** Pure FE de-cluttering. Master framework for Tasks 2-5 (Drawer Realignment, Chat Media Infrastructure, Tickets Engine, Chat Profile + Vault) added below in §15.
  - Files (4 + 2 docs): `lib/main.dart`, `lib/widgets/vendor_pull_tab.dart`, `lib/widgets/vendor_ad_card.dart`, `lib/widgets/settings_drawer.dart`. Plus `AZAMAN_MASTER_SOUL.md` + `FRONTEND_AUDIT.md`.
- 2026-05-25 — Pre-Ship: QR Scanner + Cross-Device Settings Sync + Share Profile (FE PRs #76-79)
  - **Share Profile QR Screen (PR #77):** New screen shows user's Azaman username as a scannable QR code (`azaman://user/{username}` format). Copy username button, share invite link, info hint. Accessible from settings drawer QR icon (previously dead button).
  - **QR Scanner Screen (PR #78):** Camera-based QR scanner using `mobile_scanner: ^5.1.1`. Parses `azaman://user/{username}` deep links. On scan: searches user via `/friends/search`, shows confirmation bottom sheet with avatar + trade count, sends friend request. Self-scan detection, duplicate prevention, torch toggle, premium overlay with accent corner accents.
  - **Cross-Device Theme Sync (PR #76):** `ThemeProvider.setTheme()` now fire-and-forgets `PUT /users/preferences/theme`. New `loadFromBackend()` fetches from server on login. Splash screen triggers after auth. Non-fatal on failure.
  - **Cross-Device Settings Sync (PR #79):** SettingsProvider syncs notification toggles (push/trade/chat), currency, language to `PUT /users/preferences` on every change. Shortcuts sync to `PUT /users/preferences/shortcuts`. New `loadFromBackend()` restores all from server on login. Shortcuts now have `order` field for position persistence.
  - Files: `share_profile_screen.dart` (NEW), `qr_scanner_screen.dart` (NEW), `settings_provider.dart` (rewritten), `theme_provider.dart` (sync methods), `splash_screen.dart` (+settings sync), `settings_drawer.dart` (+QR nav), `pubspec.yaml` (+mobile_scanner).
- 2026-05-25 — Phase V-FE: War Room VENDORS Tab + Dispute Resolution Upgrade (FE PR #75)
  - **VENDORS Tab:** 4th tab in Admin War Room for reviewing pending vendor applications. Fetches from `GET /vendor/applications?status=PENDING`. Expandable cards with applicant details (identity, financials, docs). Document previews (ID front, selfie, address proof) with tap-to-zoom. Approve/Reject with confirmation dialogs.
  - **Structured Dispute Resolution (Q14):** Replaced basic force-release/cancel dialog with proper ruling form. 3 rulings: BUYER_WINS, VENDOR_WINS, SPLIT (configurable buyer %). Required reason field (min 10 chars). Calls `POST /api/admin/disputes/:tradeId/resolve`. God Mode quick buttons kept in chat intercept for urgent cases.
  - **Vendor Upload Integration (FE PR #74):** `_uploadDocuments()` helper uploads files via `apiClient.multipart()` to `POST /vendor/upload-docs` before JSON submission. URLs included in application payload.
  - Files: `admin_war_room_screen.dart` (major), `vendor_apply.dart` (upload integration).
- 2026-05-25 — Phase POLISH-FE: Inter Custom Font (in review, FE)
  - **App-wide typography upgrade to Inter via `google_fonts` package.** Replaces default system fonts (Roboto/San Francisco) with Inter — purpose-built UI typeface with excellent readability at small sizes, optimized x-height, and tabular numerals for financial data.
  - **`pubspec.yaml`:** Added `google_fonts: ^6.2.1`. Package handles font fetch/cache at runtime, bundles in release builds via asset manifest.
  - **`theme_provider.dart`:** Set `fontFamily: GoogleFonts.inter().fontFamily` in `getThemeData()`. Propagates to ALL Material text styles app-wide (AppBar, body, buttons, inputs, snackbars) without per-screen changes. All 12 theme variants inherit.
  - Files (2 + 2 docs): pubspec.yaml, lib/providers/theme_provider.dart.
- 2026-05-25 — Phase Q11-FE: Receipt Download Button (in review, FE)
  - **Download PDF receipts for completed trades and withdrawals.** "Download Receipt" button on `trade_summary_screen.dart` (after receipt card). "Recent Completed Withdrawals" section on `withdrawal_screen.dart` with per-row receipt download.
  - **New `receipt_service.dart`:** Static methods `downloadTradeReceipt(tradeId)` + `downloadWithdrawalReceipt(id)`. Downloads binary PDF via authenticated GET, saves to temp dir via `path_provider`, opens with system viewer via `open_filex`.
  - **`trade_summary_screen.dart` (modified):** OutlinedButton.icon "Download Receipt" with loading spinner, positioned between receipt card and review section.
  - **`withdrawal_screen.dart` (modified):** Expandable "Recent Completed Withdrawals" section at bottom. Tap loads `GET /wallet/history`, filters COMPLETED (max 5), each row has a "Receipt" download chip.
  - **`pubspec.yaml`:** Added `open_filex: ^4.5.0`.
  - Files (1 new + 3 modified + 2 docs).
- 2026-05-25 — Phase Q12-FE: Rate Alert UI (in review, FE)
  - **Rate alert system on home screen.** "Set Rate Alert" button below the GHS rate card opens a bottom sheet with target rate input, ABOVE/BELOW toggle, optional label, and "Create Alert" CTA. Active alerts show as colored chips below the button. Triggered alerts show with a "Triggered at X" badge.
  - **New `rate_alert_service.dart`:** Singleton wrapping POST/GET/DELETE `/api/oracle/alerts`. Models: `RateAlert`, `RateAlertListResponse`.
  - **New `rate_alert_provider.dart`:** Riverpod ChangeNotifier with fetchAlerts, createAlert, deleteAlert, refresh. Exposes activeAlerts, triggeredAlerts, currentRate.
  - **New `rate_alert_sheet.dart`:** DraggableScrollableSheet with create form + alert list + delete.
  - **`live_market_section.dart` (modified):** `_RateAlertRow` + `_AlertChip` widgets below the GHS hero card.
  - **`api_client.dart` (modified):** Added `delete()` HTTP method.
  - Files (3 new + 2 modified + 2 docs).
- 2026-05-25 — Phase Q16-FE: Vendor Analytics Screen (in review, FE)
  - **New vendor analytics dashboard reachable from vendor portal.** Period selector (7D/30D/90D), summary stat cards (trades, volume, revenue, avg time, dispute rate), volume-over-time line chart (fl_chart), payment method breakdown with volume bars + trade counts.
  - **New `vendor_analytics_service.dart`:** Singleton wrapping `GET /api/vendor/analytics?period=`. Models: `VendorAnalyticsSummary`, `VolumeDataPoint`, `MethodBreakdownEntry`, `VendorAnalyticsData`. All with `fromJson` factories.
  - **New `vendor_analytics_provider.dart`:** Riverpod `ChangeNotifier` with `AnalyticsPeriod` enum (7d/30d/90d), `fetchAnalytics()`, `switchPeriod()`, `refresh()`. Loading/error/data states. `autoDispose` so memory is freed when user leaves.
  - **New `vendor_analytics_screen.dart`:** Period tabs (animated container), 5 stat cards in 3+2 row layout, `LineChart` with curved line + filled area + touch tooltips, method breakdown list with `LinearProgressIndicator` bars, skeleton loading (shimmer boxes), error state with retry, pull-to-refresh.
  - **`vendor_dashboard.dart` (modified):** New analytics icon button (`Icons.analytics_outlined`) in AppBar row next to settings gear. Navigates to `VendorAnalyticsScreen`.
  - Files (3 new + 1 modified + 2 docs): vendor_analytics_service.dart (NEW), vendor_analytics_provider.dart (NEW), vendor_analytics_screen.dart (NEW), vendor_dashboard.dart (~5 lines).
- 2026-05-25 — Phase Q15-FE: Force Update Screen (in review, FE)
  - **App version gate blocks outdated builds at splash.** Calls `GET /health` (no auth), inspects `versionGate.minVersion`, compares with `AppConfig.appVersion` (semver split-compare). If client < min: shows blocking "Update Required" screen with backend message + store URL button via `url_launcher`. Fail-open: unreachable `/health` lets user proceed.
  - **New `version_gate_service.dart`:** Singleton, `check(clientVersion)` → `VersionGateResult`. Semver compare logic: split on ".", compare major/minor/patch numerically.
  - **New `force_update_screen.dart`:** Themed fullscreen (`PopScope canPop:false`), icon, message, min version label, "Update Now" ElevatedButton.
  - **`splash_screen.dart` (modified):** Version gate check before auth. If update required → `ForceUpdateScreen`, early return.
  - **`pubspec.yaml`:** Added `package_info_plus: ^8.0.0`.
  - Files (2 new + 2 modified + 2 docs): version_gate_service.dart (NEW), force_update_screen.dart (NEW), splash_screen.dart (~15 lines), pubspec.yaml (~1 line).
- 2026-05-25 — Phase Q10-FE: Leaderboard Real Data (in review, FE)
  - **Wires the leaderboard screen to live backend data.** Replaces 20 hardcoded `_RankUser` entries with real vendor rankings from `GET /api/vendor/leaderboard`.
  - **New `leaderboard_service.dart`:** Singleton HTTP service wrapping the endpoint via `ApiClient`. Accepts metric (xp/volume/trades/profit/streak) and limit params.
  - **New `leaderboard_provider.dart`:** Riverpod ChangeNotifier with `LeaderboardEntry` model, `LeaderboardMetric` enum (5 values), loading/error state, `fetchLeaderboard()`, `switchMetric()`, `refresh()`.
  - **`leaderboard_screen.dart` (rewrite):** 5 metric tabs (scrollable TabBar), pull-to-refresh, skeleton loading (8 cards), empty state, error state with retry, "Your Rank" banner when user is outside top N, `isYou` row highlighting with accent border + "YOU" chip, KYC verified badge, contextual metric display (value + subtext change per active tab). Podium badges (Gold/Silver/Bronze) preserved for top 3.
  - Files (3 + 2 docs): leaderboard_service.dart (NEW), leaderboard_provider.dart (NEW), leaderboard_screen.dart (rewrite).
- 2026-05-25 — Phase P1-FE: Audit Fixes — theme migration + queue promotion + GHS→USD (in review, FE)
  - **Full end-to-end flow audit** discovered 3 P0/P1 issues fixed in this PR:
  - **ProfileDetailsScreen theme migration.** All hardcoded dark colors replaced with `themeProvider.colors.*`. Same pattern as TradeSummaryScreen (PR #54). Light/snow themes now work on this screen.
  - **GHS→USD in new_trade_request snackbar.** The `main.dart` trade-request notification showed "wants to trade X GHS" — last stale GHS reference after Phase F2 corrected the P2P model to USD.
  - **WaitingRoomScreen queue_promoted handler.** Adapted to handle promotion WITHOUT a tradeId (correct behavior per Phase P1 BE: slot opened, buyer should re-initiate). Pops to marketplace with a success snackbar instead of crashing on empty orderId.
  - **Deferred:** Dual socket connections (TradeProvider + SocketService) filed as Phase P2. KycVerificationScreen hardcoded colors filed as cosmetic debt.
  - Files: profile_details_screen.dart (rewrite), main.dart (~1 line), waiting_room_screen.dart (~20 lines).
- 2026-05-25 — Phase N-FE: Queue/Waiting Room Wiring + Demo Readiness Sweep (in review, FE)
  - **Wires the orphan `WaitingRoomScreen` into the live P2P trade flow.** `initiateTrade()` now returns `TradeInitiationResult` distinguishing immediate trade (HTTP 200/201) from queued (HTTP 202). Buyer auto-navigates to the waiting room when vendor is at max concurrent trades. Socket-powered real-time position updates (`queue_position_update`) and auto-promotion to `ActiveTradeScreen` (`queue_promoted` / `queue_update` events).
  - **Leave Queue wired.** "LEAVE QUEUE" button calls `PUT /api/ai/queue/:queueId/leave` with loading state + error handling.
  - **FCM deep-link.** New `/queue` GoRoute (query params: `queueId`, `position`, `adId`). `OPEN_QUEUE` action added to `handleNotificationTap`.
  - **Demo readiness sweep.** All 12 flows statically traced end-to-end and verified: Auth, P2P, Queue, Vendor, Trade Accounts, AZM Earn/Spend, Savings, Social, Settings (11+system themes), Notifications, Connectivity. Found and fixed 1 critical bug: `VendorTradeExecution` back button used `context.go('/vendor-dashboard')` (non-existent route) → replaced with `Navigator.of(context).pop()`.
  - **Known cosmetic debt:** `TradeSummaryScreen` hardcodes dark colors. Deferred to polish PR.
  - Files (5 + 2 docs): marketplace_provider, p2p_marketplace_screen, waiting_room_screen (rewrite), app_router, vendor_trade_execution (nav fix).
- 2026-05-25 — Phase F2-FE: P2P Architecture Correction — global fiat wallet bridge (merged 2026-05-25, PR #52)
  - **Frontend companion to BE PR #66 (Phase F2).** 15 files (3 new, 12 modified) + 2 docs. Corrects the entire P2P marketplace UI from a GHS↔USDC exchange model to the correct global fiat wallet liquidity bridge model.
  - **Trade Account management UI.** New screen (`trade_accounts_screen.dart`) with full CRUD for 11 supported payment method types (Zelle, CashApp, Venmo, PayPal, Apple Pay, Google Pay, Wise, Revolut, Gift Card, Western Union, Wire Transfer). Add-account bottom sheet with type grid → dynamic form → submit flow. Status badges (APPROVED/PENDING/REJECTED). Reachable from Settings → Payment and Vendor Dashboard.
  - **Marketplace corrected.** `AdListing` model adds `adType` (SELL/BUY), `tradeAccountId`, `pricePerUSD` (replaces `rate`). Trade confirm sheet uses USD input (1:1 with USDC, no oracle rate). SELL ads require buyer payment details (dynamically rendered per method type). `initiateTrade()` sends `buyerPaymentDetails`.
  - **Vendor ad creator corrected.** TradeAccount single-select (only APPROVED accounts) replaces old fiat account multi-select. GHS oracle pricing section replaced with flat 2% fee explanation. Sends `tradeAccountId`.
  - **GHS→USD across all trade screens.** Active trade, trade summary, trade cards, vendor execution — all now show `$` instead of `GH₵`. Default currency is USD.
- 2026-05-25 — Phase E2-FE: AZM Spend UI — fee discount + ad boost (in review, FE)
  - **Frontend companion to BE PR #63 (Phase E2).** Five files: new AZM spend service (HTTP client for `/api/azm/spend/*`), new Riverpod provider (spend options state + real-time debit injection), withdrawal screen fee-discount selector, vendor dashboard ad-boost sheet, socket `azm_spend` listener.
  - **Withdrawal fee discount.** New "USE AZM TO REDUCE FEE" section in the MoMo withdrawal flow. Three tier chips (25% Off / 10 AZM, 50% Off / 25 AZM, Free / 50 AZM) with affordability badges. Selecting a tier updates the fee preview live (strikethrough + green discounted amount). AZM debited before the withdrawal fires; failure gracefully falls back to standard fee.
  - **Ad boost purchase.** New "BOOST AD" button on every active ad card in the vendor dashboard. Opens a bottom sheet with three duration options (24h / 3 days / 7 days) showing costs and descriptions. Boosted ads show a green "BOOSTED" badge with countdown timer. Already-boosted ads show an "EXTEND" button.
  - **Real-time updates.** Socket service now listens for `azm_spend` events and immediately updates `balanceDataProvider.azmBalance` + notifies the AZM spend provider to refresh affordability state.
- 2026-05-25 — Phase E1-FE: AZM Earn UI — rewards screen + real-time socket (in review, FE)
  - **Frontend companion to BE PR #62 (Phase E1).** Five files: new AZM service (HTTP client for `/api/azm/*`), new Riverpod provider (paginated state + real-time injection), new AZM Rewards screen (summary + earn guide + history list), socket `azm_reward` listener, and tappable AZM chip on hologram card.
  - **AZM chip navigates to full screen.** Tapping the AZM balance chip on the hologram card opens the new `AzmRewardsScreen`. AZM values display without `$` prefix (loyalty points, not USD).
  - **Real-time updates.** The socket service now listens for `azm_reward` events and immediately updates `balanceDataProvider.azmBalance` + notifies the AZM provider to prepend the new reward to the history list.
  - **Earn rates discovery.** Collapsible "How to Earn" card fetches live rates from `GET /api/azm/rates` (public endpoint) so users always see current reward schedule.
- 2026-05-25 — Phase D-3: AZM architecture correction — AZM is independent loyalty ledger (docs only, FE)
  - **CRITICAL ARCHITECTURE CORRECTION.** Phase D-2 (BE PR #59) incorrectly interpreted "AZM is not a blockchain token" as "delete azmBalance and derive it as `availableBalance × rate`." The correct interpretation: AZM is an independent platform reward point (like Binance BNB or airline miles) backed by its own database column.
  - **FE impact: NONE.** The FE never merged the D-2 cleanup PR (#48). All `azmBalance` references in `user_model.dart`, `hologram_provider.dart`, `auth_provider.dart`, `socket_service.dart`, and `withdrawal_screen.dart` remain intact and correct.
  - **Action taken:** PR #48 (Phase D-2 FE cleanup) is abandoned/closed — do NOT merge it. The FE code is already correct as-is.
  - **BE companion:** Phase D-3 (BE) restores the `azmBalance` column that D-2 dropped. The FE's existing JSON parsing (`toDouble(json['azmBalance'])`) will work seamlessly once D-3 BE lands.
  - **AZM design (corrected in §1 + §2 below):** AZM = independent loyalty-point ledger. Earn: trade completions, referrals, login streaks, achievements. Spend: fee discounts, premium ad-tier unlocks, boosted visibility. NOT derived from USDC × rate.
- 2026-05-25 — Phase H4: Connectivity banner — premium offline awareness (frontend, in review)
  - **Closes the audit's H/H2 deferred line: "`connectivity_plus` banner — needs adding the package + native config."** Phase H shipped the haptic vocabulary, page transitions and skeleton loaders; H2/H3 wired slide-to-confirm and biometric. H4 is the missing piece — the app now KNOWS when it's offline and tells the user, instead of spinning forever on a dead network.
  - **`pubspec.yaml`:** adds `connectivity_plus: ^6.1.0`. No native config required — the package handles iOS / Android permissions out-of-the-box on the supported platforms (the iOS `Info.plist` and Android manifest already declare network usage for the existing http + socket_io_client traffic).
  - **`lib/services/connectivity_service.dart`** (NEW, ~70 LOC). Wraps `Connectivity().onConnectivityChanged` into a Riverpod `StreamProvider<bool>` that emits `true` when at least one interface is up (wifi / mobile / ethernet / vpn / bluetooth / other) and `false` when fully offline (`ConnectivityResult.none`). Initial state seeded by `checkConnectivity()` so the banner doesn't flash on cold-launch. Fail-open on probe error so a transient connectivity_plus glitch doesn't strand the user behind a permanent banner. A companion `isOnlineProvider` exposes a synchronous bool for retry-button gating.
  - **`lib/widgets/azaman_connectivity_banner.dart`** (NEW, ~150 LOC). Slide-down strip that overlays every screen via a `Stack`, so the user's screens never reflow when connectivity flips (no jolt every time you walk through a tunnel). Shows a danger-coloured "You are offline — Showing your last loaded data. Some actions are paused." card. On reconnect, briefly flashes a success-green "Reconnected" tick for ~1.4s before sliding back up. Tied into `AzamanHaptics.warn()` on disconnect and `AzamanHaptics.confirm()` on reconnect — same vocabulary as the rest of the app.
  - **`lib/main.dart`:** wires the banner into `MaterialApp.router(builder:)` so it overlays every routed screen with one mount. No per-screen migration. Keeps the Phase H `AnnotatedRegion<SystemUiOverlayStyle>` wrapper outside so the banner sits inside the themed status-bar overlay correctly.
  - **What this changes for the user:**
    - Walks into a building with no signal → banner appears within a second; screens show their last fetched data instead of spinning forever.
    - Comes back into signal → banner flashes green, then slides up; the existing socket reconnect logic in `trade_provider.dart` and `socket_service.dart` handles the actual data reconnect.
    - Captive portals and "wifi connected but no internet" cases are NOT caught by this PR — that requires a real probe to a known endpoint. Filed as Phase H5 follow-up if it becomes painful in practice.
  - **Re-test sweep folded in.** Walked the existing socket reconnect path (Phase G `home_summary_provider.refresh()` + Phase J socket `balance_update` handler) — the banner is presentational only; no socket / API code paths change. The Phase H `AzamanHaptics.warn()` two-beat haptic on disconnect feels distinct from the `confirm()` medium tap on reconnect — verified by reading both signatures inline. The Phase B2-FE `notifications_updated` handler is in a separate code path and unaffected.
  - Files (5): `pubspec.yaml`, `lib/services/connectivity_service.dart` (new), `lib/widgets/azaman_connectivity_banner.dart` (new), `lib/main.dart` (~+8 lines), `FRONTEND_AUDIT.md` + `AZAMAN_MASTER_SOUL.md` — this entry.
- 2026-05-25 — Phase B2-FE: Multi-device notification sync (FE PR #45, merged 2026-05-25)
  - **Closes the FE half of Phase B2.** Backend PR #50 (merged 2026-05-25) shipped a `notifications_updated` socket event from `markAsRead` and `markAllAsRead` so other open sessions of the same user could refresh their badge. The FE didn't listen for it and didn't have a "mark all read" affordance — half the sync was dead until this PR.
  - **`lib/providers/notification_provider.dart`:** new socket handler in `_initSocketListener` for `notifications_updated`. Two subtypes: `MARKED_READ` (single id → `_applyMarkAsReadLocal(id)`) and `MARKED_ALL_READ` (→ `_applyMarkAllAsReadLocal()`). Both helpers are idempotent so the user-initiated path's own server-emitted echo is a no-op.
  - **`markAllAsRead()` method added.** Optimistic local mutation, then PATCH `/notifications/read-all`, returns the server's affected-row count (or null on failure so callers can surface a retry banner). The BE then echoes `notifications_updated MARKED_ALL_READ` back over socket — other devices clear their entire badge in one round-trip.
  - **`lib/screens/notification_hub_screen.dart`:** new "Mark all read" `AppBar` action button, visible only when `unreadCount > 0`. Tap fires `AzamanHaptics.confirm()` → optimistic mark-all → API call → `AzamanHaptics.commit()` on success or a danger snackbar on failure. Added `RefreshIndicator` wrapping every tab's `ListView` (works on both populated and empty states so users can retry after a transient fetch failure). Tab switches now fire `AzamanHaptics.toggle()` and notification taps fire `AzamanHaptics.nav()` for the same haptic vocabulary as the rest of the app.
  - **No FE coordination required from any other surface** — same as B2 BE: clients that don't listen for the new socket event stay on the pull-to-refresh model unchanged.
  - **Verified end-to-end (re-test sweep folded in):** the existing `new_notification` socket handler + `addNotification` dedup-by-id still work alongside the new event channels. The optimistic-then-server pattern matches the existing `markAsRead` design. Pull-to-refresh re-uses the existing `refresh()` method that's already on the notifier.
  - Files (4): `lib/providers/notification_provider.dart` (~+90 lines), `lib/screens/notification_hub_screen.dart` (~+70 lines, refactor), `FRONTEND_AUDIT.md` + `AZAMAN_MASTER_SOUL.md` — this entry.
- 2026-05-25 — Phase M: Wiring + orphan sweep (frontend, FE PR #44, merged 2026-05-25)
  - Closes the audit's §13 orphan inventory. **11 confirmed-dead orphan files deleted** (`account_deactivation.dart` duplicate, `admin_spy_screen.dart` duplicate, `admin_war_room.dart` + `_alerts.dart` orphans, `chat_screen.dart`, `notification_screen.dart` duplicate, root `signup_screen.dart` duplicate, `trade_appeal_sheet.dart`, `user_dashboard.dart` dev sandbox, `wallet_screen.dart`, `fiat_wallet_screen.dart`) — each verified by grep to have zero inbound imports.
  - **5 orphan screens wired** into reachable surfaces: `ProfileDetailsScreen`, `ReferralScreen`, `AccountDeactivationScreen` get tiles in `settings_screen.dart` (new "Account" section at top + "Delete Account" tile in "Other"); `MessagesHubScreen` and `LeaderboardScreen` are reachable via the new `/messages` + `/leaderboard` GoRoutes for FCM deep-link targeting (no in-app surface yet).
  - **GoRouter expanded from 4 to 13 named routes.** The new ones: `/settings`, `/profile/edit`, `/account/activity`, `/account/delete`, `/friends`, `/messages`, `/referral`, `/leaderboard`, `/marketplace`, `/savings`. The full set of FCM-deep-linkable surfaces now has stable names.
  - **`handleNotificationTap` action vocabulary expanded.** Was `OPEN_TRADE` + `OPEN_DISPUTE` only (so 95% of FCM notifications landed on a black screen on cold-launch). Now also handles `PING_TOPUP`, `OPEN_FRIEND_REQUEST`, `OPEN_FRIEND_CHAT`, `VIEW_SAVINGS`, `OPEN_AD` — mirroring the `actionPayload.action` strings the BE emits. Unknown actions silently no-op so a future BE-only rollout doesn't crash older clients in the wild.
  - **Note on `user_dashboard.dart`:** Phase J modified this file to clean up `lockedBalance` references, but post-merge analysis confirmed it had zero inbound imports (true orphan). Phase M deletes it; the Phase J edit was discarded with the file. No functional impact — the active dashboard surface is the bottom-nav home screen, not this dev sandbox.
  - **Out of scope, deferred to a follow-up.** Promoting all 67 imperative `Navigator.push` callsites to GoRoutes (sibling-to-sibling inside a feature gains nothing from named routes). Wiring `LeaderboardScreen` into `vendor_dashboard.dart` (UI surface that doesn't exist yet). Wiring `MessagesHubScreen` into the bottom nav (would conflict with the existing 5-tab structure + `FriendsHubScreen`). Removing the AppBar chat icon (audit §6 P1 — visual tradeoff with no clear winner).
- 2026-05-25 — Phase J: schema cleanup — drop dead V1 fields (FE PR #43 + BE PR #41, merged 2026-05-25)
  - Frontend half of the coordinated cleanup. Stops reading the two write-dead JSON keys (`lockedBalance`, `ghsBalance`) that the backend dropped from the `User` schema in the same wave. Phase B's audit (findings C and D) confirmed both columns were read-only display data that had always returned 0.0.
  - **`lib/models/user_model.dart`:** drops `lockedBalance` and `ghsBalance` from the `User` class (constructor, fromJson, copyWith). Comment block points future readers at the audit findings + the hologram model.
  - **`lib/providers/auth_provider.dart`:** `updateBalance(...)` no longer accepts `lockedBalance`. Callers should pass `escrowLockedBalance` (the V2 field).
  - **`lib/providers/hologram_provider.dart`:** `BalanceData` drops both fields. The orphan `ghsBalanceProvider` is removed; consumers should use `hologramBalanceProvider` (which computes `availableBalance × oracleRate` — the actual GHS hologram). `totalLocked` now sums only V2 buckets (`escrowLockedBalance + disputeEscrowBalance`).
  - **`lib/providers/trade_provider.dart`:** socket `balance_update` handler reads V2 fields (`vendorUnallocatedBalance`, `escrowLockedBalance`, `disputeEscrowBalance`) instead of the dropped legacy keys.
  - **`lib/services/socket_service.dart`:** both `balance_update` handlers (Ref + plain-Ref variants) drop the dropped keys; comment block documents the Phase J change.
  - **`lib/screens/auth/{login,signup}_screen.dart`:** stop reading `lockedBalance` when constructing the post-login `User`.
  - **`lib/screens/vendor_dashboard.dart`:** `_lockedBalance` renamed `_escrowLockedBalance` and rebound to the V2 column from the REST response and the socket envelope. **The "LOCKED (IN ESCROW)" UI label now shows real numbers** — it had been bound to the write-dead `lockedBalance` since the V2 split, so it had reported $0.00 for every vendor regardless of active trade volume. Genuine bug fix folded in.
  - **`lib/screens/vendor_deposit_screen.dart`:** same swap. The "X USDT locked in escrow" subtitle now appears for vendors with active trades.
  - **Backwards compatibility:** older app builds in the wild that still read the dropped JSON keys parse defensively to `0.0` — the same value the keys held when present, so no functional regression. The vendor escrow display is the only behaviour change, and it is a pure improvement (false-zero → true value).
- 2026-05-25 — Phase P3: Unified socket architecture (FE, in review)
  - Major architectural refactor: consolidated the two concurrent socket.io connections (SocketService V4 + TradeProvider's own socket) into a single authenticated connection in SocketService V5.
  - Eliminates: duplicate bandwidth (2x TCP per user), race conditions on balance_update, unauthenticated TradeProvider socket (never sent JWT), confusion about which socket owned which events.
  - SocketService now owns: balance_update, rate_update, azm_reward, azm_spend, trade_update, market_update, new_notification, notifications_updated, new_trade_request, trade_completed, plus all trade-room join/leave.
  - TradeProvider V3 is now socket-free — delegates all socket ops to SocketService. Retains: AppRole, notification count, vendor ad CRUD, Yellow Card rate cache.
  - All 12 demo flows verified against unified socket path.
- 2026-05-25 — Phase P2-FE: Theme sweep of 6 vendor/utility screens (PR #56, merged 2026-05-25)
- 2026-05-25 — Phase P1-FE: Audit fixes — profile theme + GHS→USD + queue promotion (PR #55, merged 2026-05-25)
- 2026-05-25 — Phase P1-BE: Queue socket events + auto-processing (BE PR #67, merged 2026-05-25)
  - BE now emits queue_promoted + queue_position_update, auto-processes queue on trade complete/cancel, fixed broken global.* refs in processNextInQueue.
- 2026-05-25 — Phase H3: Slide-to-confirm + biometric pre-gate on every financial confirm (FE PR #42, merged 2026-05-25)
  - Closes the audit's H2 "out of scope, deferred" item: the vendor's Release-crypto button on `vendor_trade_execution.dart`. The AlertDialog "Confirm & Release" was replaced with a slide-to-confirm bottom sheet showing a richer trade summary (releasing crypto amount, buyer-paid fiat amount, payment method, do-not-release-on-screenshot warning).
  - Adds an opt-in biometric pre-gate (`AzamanBiometricGate`) wrapped around every existing slide: vendor release, withdrawal (mobile money + crypto), savings goal fund/withdraw, friends transfer (send + request), and the buyer's "I HAVE PAID" flow on `upload_proof.dart` (also upgraded from ElevatedButton → SlideToConfirm in this PR). When the user has enabled "Biometric on financial actions" in Security Settings the slide fires the system Face ID / Touch ID / passcode prompt with action-specific copy ("Authenticate to release crypto", "Authenticate to send mobile money", etc.) before the action runs. When biometric lock is OFF the gate is a no-op and the slide fires immediately.
  - New "Biometric Lock" card in `security_settings.dart`. Toggle is itself biometric-gated in BOTH directions — turning ON requires authenticate(), turning OFF also requires authenticate(). A pickpocket with an unlocked phone can't disable the lock and then drain funds.
  - **`SlideToConfirm` widget hardening (Phase H3 review-pass changes baked in):** new `enabled` prop mirrors `ElevatedButton(onPressed: null)` semantics so a slider with an unmet precondition (e.g. no upload-proof image) rejects drags before committing. Public `SlideToConfirmState` so callers can hold a `GlobalKey` and `reset()` the slider after a cancelled biometric prompt. `didUpdateWidget` re-arms on the `isLoading: true → false` and `enabled: false → true` edges. `BiometricService.authenticate({String? reason})` now accepts reason and pipes to `local_auth.localizedReason` (was hard-coded). `BiometricService.isAvailable` tightened to `canCheckBiometrics && isDeviceSupported()` (was OR — let passcode-only devices pass). Heavy `commit()` haptic moved INSIDE the gated action so a cancelled auth doesn't fire a phantom "transaction sent" buzz.
  - Out of scope, deferred to Phase H4 / future polish: slide-to-confirm on `chat_transfer_modal` (transfer-inside-chat), gating the dispute-open AlertDialog (low-frequency action, lower priority), wiring biometric onto the existing PIN screen (which is its own auth path).
- 2026-05-24 — Phase H2: Slide-to-confirm on financial actions (frontend, in review)
  - Wires the existing SlideToConfirm widget into the highest-risk financial confirms. Stacked on Phase H.
  - Withdrawal screen: ElevatedButton → SlideToConfirm. Disabled state preserved (when form incomplete or already submitting). Swipe routes through the existing _submit() so all validation + balance double-checks fire unchanged.
  - Savings goal sheet (_AmountPromptSheet for fund/withdraw): same swap. Slide CTA color + label propagate from the parent sheet (Fund = success-green, Withdraw = warning-yellow).
  - Friends transfer modal: already wired with SlideToConfirm prior; verified intact.
  - Out of scope, deferred: active_trade_screen "Release crypto" button (Phase H3 — large surface), biometric prompt before slide fires (Phase H3, local_auth already in pubspec).
- 2026-05-24 — Phase H: Premium polish pass (frontend, in review)
  - Cross-cutting visual + tactile polish across every existing surface. Stacked on Phase G. Frontend-only.
  - **Review-pass fixes folded in same commit (post-first-push):** ThemeProvider no longer clobbers the framework's onPlatformBrightnessChanged setter (now a WidgetsBindingObserver), SSO success snackbar fires AFTER pushReplacement, home summary reads the correct trade fields (amountFiat/amountCrypto, not the non-existent amountGhs/amountUsdc), TradeStatus active set matches the Prisma enum (was including non-existent AWAITING_RELEASE; now correctly includes PENDING), rate-history append moved out of LiveMarketSection.build into HomeSummaryNotifier.refresh, Withdrawal payload reads payoutMethod/network instead of a non-existent currency column. Dropped orphan flutter/services.dart imports across three files, fixed theme-picker hairline divider collapse, updated stale 4-tab comment in main.dart.
  - Custom page transitions (slide+fade, 240ms, easeOutCubic) wired globally via ThemeData.pageTransitionsTheme — every existing Navigator.push picks it up automatically.
  - Status bar + system nav bar styles flip with the theme (AnnotatedRegion<SystemUiOverlayStyle> wrapping MaterialApp.router). Closes the audit's §11 bug where switching to a Light theme left a white status bar with white icons.
  - Haptic vocabulary: AzamanHaptics.nav/toggle/confirm/commit/warn replaces ad-hoc HapticFeedback.lightImpact() calls across home/settings/theme-picker.
  - SkeletonBlock (was orphan) wired into TodayWidget cold-load + LiveMarketSection rate/sparkline cold-load. Subsequent refreshes keep the previous snapshot stable so the UI never blinks.
  - AzamanConfirmSheet replaces the AlertDialog sign-out in settings_screen. Same return contract as showDialog<bool>, so future sweeps (Phase H2) swap one line.
  - Out of scope, deferred to H2: slide_to_confirm on financial confirms, custom font, connectivity_plus banner, list-screen skeleton sweep.
- 2026-05-24 — Phase G: Home overhaul (frontend, in review)
  - Replaced the static "brochure" home screen (hardcoded Core Assets at $1.00 forever, hardcoded Platform News, dead pull-to-refresh) with a dynamic dashboard.
  - New `lib/widgets/today_widget.dart` — 4 stat tiles (Active Trades, Pending Withdrawals, Friend Requests, Unread Notifications) backed by a single aggregated /home-summary fan-out. Each tile navigates to the right destination (TradesTabScreen / FriendsHubScreen / GoRouter `/notifications`); pending withdrawals open an in-place bottom sheet listing the recent rows.
  - New `lib/widgets/live_market_section.dart` — replaces hardcoded Core Assets. Live USD->GHS rate from /api/oracle/rates with source attribution and a 24-sample in-memory sparkline rendered via fl_chart. Stable-peg rows for USDC / USDT / AZM at $1.00 (no fake price movement; the hologram model is 1:1 USDC).
  - New `lib/services/home_summary_service.dart` + `lib/providers/home_summary_provider.dart` — single Future.wait fan-out to /api/oracle/rates, /api/trades/history (active filter), /api/wallet/history (PENDING filter), /api/friends/requests, /api/notifications/unread-count. Per-section error fields so a single failure degrades to `—` rather than blocking the whole render.
  - Pull-to-refresh actually re-fetches now (was `Future.delayed(1s)` — literally a sleep). Hologram balance auto-updates via the existing socket.io `balance_update` channel; the home page also kicks `authProvider.fetchUserDetails()` as a best-effort hydration.
  - Platform News block removed (was hardcoded mock data; no /api/news endpoint exists yet — re-add when one ships).
  - Animated balance counter — already in place inside HologramBalanceCard via TweenAnimationBuilder + AnimatedSwitcher. Verified untouched. The audit's call for `animated_flip_counter` is already satisfied; saved a dependency.
  - Roadmap mirrored across both repos: Phase G is `IN REVIEW`. Backend has no Phase G code change.
- 2026-05-24 — Phase F: Settings overhaul (frontend + small backend change-password endpoint, in review)
  - Closes the original user-stated UI pain point ("the actual settings page... it's not proper"). Phase 0 patched the theme grid layout; Phase F is the structural fix.
  - Apple/Binance row-tile layout for SettingsScreen. Six sections (Appearance / Notifications / Preferences / Security & Privacy / Payment / Other), each a rounded card of nav rows + toggle rows. Currency/Language dropdowns moved to iOS-style bottom-sheet pickers.
  - New ThemePickerScreen as a child screen of Settings. Full-page picker with a *live home preview* card at the top (miniature hologram balance + quick-actions row, repaints in the selected theme), a dedicated "Auto" row for the new system-follow option, and the same Phase 0 swatch-stripe tile aesthetic for the 11 explicit themes.
  - AzamanTheme.system added at index 11 (preserves SharedPreferences indices for existing users). ThemeProvider subscribes to `onPlatformBrightnessChanged` and resolves `.system` to dark/light at read-time. Flipping iOS / Android dark mode now repaints the whole app live.
  - SSO buttons wired on login + signup. New SsoService routes `POST /api/auth/sso { idToken, provider }` through the central apiClient and hydrates AuthProvider on success. The native idToken-acquisition step throws a typed `SsoNotConfiguredException` today (the pubspec doesn't yet include firebase_auth + google_sign_in + sign_in_with_apple) — caught by both screens to render a clean "SSO requires native config" modal. Phase K will add the SDKs + native capabilities; the wiring stays.
  - "Change Password" tile wired to a new backend endpoint added in this PR's BE companion: POST /api/security/change-password (bcrypt verify current → bcrypt hash new → write SECURITY_ACCOUNT audit notification). Refuses on SSO-only accounts and on identical-password attempts.
  - "Account Activity" tile wired to GET /api/users/me/security-logs (paginated, pull-to-refresh + infinite scroll, contextual icons + relative timestamps).
  - Two-Factor & PIN screen (`security_settings.dart`) — formerly orphan despite being fully wired to `/api/security/2fa/*` and `/pin/*` — is now reachable from the Security & Privacy section.
  - Roadmap mirrored across both repos: Phase F is `IN REVIEW`. AUDIT.md and FRONTEND_AUDIT.md changelogs updated.
- 2026-05-24 — Phase E: Savings completion (frontend, in review)
  - Goal cards in SavingsScreen are now tappable. Tap opens a bottom sheet (lib/widgets/savings_goal_sheet.dart) with goal summary, Fund / Withdraw action tiles, and a Pause/Resume toggle.
  - Wires four backend endpoints the frontend was previously not calling: POST /savings/goals/:id/deposit, POST /savings/goals/:id/withdraw, PUT /savings/goals/:id/pause, PUT /savings/goals/:id/resume.
  - Withdraw on locked + not-matured goals shows a 2% early-penalty preview before submission.
  - Roadmap in AUDIT.md / FRONTEND_AUDIT.md updated: Phase E is now IN REVIEW; Phase C is DONE (PR #36 merged).
- 2026-05-24 — Phase C: Crypto deposit wiring + unified roadmap (PR #36, merged)
  - Wired the orphan CryptoDepositScreen via a new DepositChooserSheet from the Home Quick Action. Users can now actually deposit Polygon USDC.
  - Verified WithdrawalScreen, TransferModal, FiatDepositFlowScreen, and SavingsScreen (create) are already correctly wired to live backend endpoints — the audit's "P0 not wired" claims for these were stale.
  - Confirmed real gap (deferred to Phase E): SavingsScreen uses 2 of 8 backend savings endpoints — fund/withdraw/pause/resume not yet on the frontend.
  - Wrote a UNIFIED ROADMAP block now mirrored in both AUDIT.md (backend) and FRONTEND_AUDIT.md (frontend) as the single source of truth for "what's next."
- 2026-05-24 — Phase 0: Visible Wins (PR #35, merged)
  - Removed leaked Firebase service-account key from working tree; hardened .gitignore. Manual rotation in Firebase console still required.
  - Inverted vendor pull tab role gating: tab now shows for everyone; vendors → VendorDashboard, non-vendors → VendorApplyScreen.
  - Wired Home Quick Actions (Buy/Sell/Deposit Fiat/Savings) to live screens — previously decorative.
  - Rebuilt settings theme picker grid (3-col, swatch stripe, live theme preview per tile).
  - Deleted dead lib/theme/app_theme.dart and orphan lib/screens/actual_settings_screen.dart.
  - Audit notes (FRONTEND_AUDIT.md) updated with the full Phase 0 ledger and three stale findings flagged.

1. THE HOLOGRAM LEDGER & TREASURY
The 1:1 Rule: User balances are NEVER stored as local fiat (GHS). They are stored strictly as USDC.

The Hologram: Displayed fiat values are a dynamic UI calculation: User USDC Balance × Live Yellow Card Rate = Displayed GHS.

AZM Loyalty Points: AZM is a **separate, independent** platform reward currency.
It is NOT a blockchain token. It is NOT derived from USDC × rate. It is its own
database column (`azmBalance`) with its own earn/spend mechanics. Think Binance BNB
rewards or airline frequent-flyer miles. Users cannot buy AZM directly — they earn
it through platform engagement. Users can spend AZM on premium features but cannot
withdraw it as fiat or crypto.

Tri-Wallet Treasury: Platform liquidity is divided into SYSTEM_MASTER_CRYPTO (cold/warm), SYSTEM_HOT_WALLET (automated withdrawals/gas), and SYSTEM_FIAT_POOL (corporate local payouts).

2. THE GREAT ACCOUNT SPLIT (DATABASE SCHEMA)
A user's funds are strictly partitioned. Do not use legacy fields (e.g., lockedBalance).

availableBalance: Total liquid USDC funds (trading, spending, withdrawals).

vendorUnallocatedBalance: USDC isolated by a vendor to back active ads.

escrowLockedBalance: USDC currently frozen in an active P2P trade.

disputeEscrowBalance: USDC quarantined during an active dispute.

azmBalance: **Independent loyalty-point ledger (AZM).** NOT derived from any
other column. NOT a blockchain token. Users earn AZM through platform activities
(trade completions, referrals, login streaks, achievements) and spend AZM on
premium features (fee discounts, ad-tier unlocks, boosted visibility). Backend-
controlled; never directly purchasable or withdrawable as fiat/crypto.

3. FRONTEND IMMUTABILITY & UI STANDARDS
The frontend UI is carefully designed. It must not regress.

Dashboard UI: The user balance card must remain slender, dark/glassmorphic, and alive (animations). The top balance view and API refresh timer are permanently locked components.

Riverpod Granularity: Streams (like live Yellow Card rates) must only repaint their specific text widgets using ref.watch(provider.select(...)). They must NEVER trigger a rebuild of the layout/card components.

Apple Wallet Ads: The P2P marketplace utilizes a CustomScrollView and SliverPersistentHeader to stack ad cards at the top of the viewport when scrolled.

Trade Chat UI: Must feature a draggable countdown timer pill overlay. Extending time (+15m) triggers a visual bubble that merges into the pill with a haptic ripple.

4. BACKEND EXECUTION & REVENUE
Single Source of Truth: Trade releases happen ONLY through p2p.service.completeTrade. No alternative socket or controller paths are permitted.

The Arbitrage Shield (2% Exit Fee): Fiat withdrawals incur a 2% fee calculated off the Yellow Card rate. This is split: 1% to SYSTEM_PROFIT_FEES, and 1% to the user matching the referredByCode (Influencer).

External Gas: 100% of the MATIC network gas fee is deducted from the user's transfer amount on external crypto withdrawals.

5. DUAL-CHAT SYSTEM
Trade Chats (Escrow): Temporary, tied to a tradeId, equipped with the draggable timer pill and direct payee widget.

Personal P2P Chats (Social): Permanent, located in the Messages Hub. Includes a "+" button to instantly send/request crypto inside the chat, guarded by biometric authentication (FaceID/PIN).

6. AI COMMAND & SMART AFFORDANCES
Smart Ad Matchmaking: When toggled, the AI re-ranks the marketplace to prioritize ads using the user's historically preferred fiat payment methods.

AI CFO: A background worker monitoring the SYSTEM_HOT_WALLET. If MATIC gas or fiat reserves drop below thresholds, it fires natural-language alerts to the Admin.

AI Dispute Memory: Suggests dispute resolutions to the Admin by referencing historical actions in the DisputeResolutionLog.


---

15. UI/UX SPRINT FRAMEWORK (Phase UI-1 → UI-5, 2026-05-26)

**Product Decision (2026-05-26).** A coordinated 5-task sprint to declutter the
visual surface, realign payout/deposit logic in the settings drawer, and
introduce a unique transactional-tickets workspace inside chat. Tasks 3-5
require backend collaboration; Task 1-2 are pure frontend. Each task is
shipped as its own PR pair where backend work is involved.

15.1 TASK 1 — UI DE-CLUTTERING (FE-only, this PR — Phase UI-1)

Status: IN REVIEW (this PR).

Four cosmetic strips:
1. Header chat icon removed (`lib/main.dart`). Bottom nav already carries Chat.
2. Vendor pull tab first-popup: "Start Application" button removed; replaced
   with text block prompting users to visit the official website. The 3-pull
   gate is now the only in-app application path.
3. Vendor ad cards: "Trade Now" button removed. Card-tap → vertical flip-open
   animation is the sole interaction gateway. Trade form lives on the back
   face of the flip card.
4. Settings drawer: bulky "Withdrawal Addresses" portal tile replaced with a
   slender list-tile pattern (`_buildSlenderTile`) that future drawer payment
   entries reuse.

15.2 TASK 2 — DRAWER PAYOUT/DEPOSIT REALIGNMENT (FE-only — Phase UI-2)

Status: IN REVIEW (FE PR).

Three cleanups landed:
1. Drawer "MERCHANT PROTOCOLS" section renamed "PAYMENT ADDRESSES" and now
   hosts two slender tiles (Deposit Addresses + Withdrawal Addresses) inside
   a single bordered card. Down/up arrow icons signal funds-in vs funds-out.
   The duplicate Withdrawal Addresses tile that lived under "RECOMMENDED" is
   removed.
2. Settings → Payment "Trade Accounts" tile REMOVED. Trade Accounts hold
   global fiat handles (Zelle, CashApp, Venmo, PayPal, Apple Pay, Google Pay,
   Wise, Revolut, Gift Cards, Western Union, Wire Transfer) used exclusively
   by vendors for P2P ad placements. The vendor dashboard's "MANAGE TRADE
   ACCOUNTS" button is now the only entry point.
3. `saved_wallets_screen.dart` `_isValidPayoutWallet` filter hardened with an
   explicit blocklist of all 11 global-fiat method types. Even legacy
   conflated rows can't leak through.

15.3 TASK 3 — CHAT MEDIA INFRASTRUCTURE (FE + BE — Phase UI-3)

Status: IN REVIEW (BE + FE PR pair).

**Backend deliverables (shipped):**
- Schema migration extends `MessageType` and `DirectMessageType` enums with
  IMAGE / VIDEO / DOCUMENT / AUDIO / LINK (plus TICKET_LINK reserved for
  UI-4). Both `Message` and `DirectMessage` get seven nullable media
  columns. New `LinkPreviewCache` table with sha256 URL key, 24h TTL.
- `services/linkPreviewService.js` — server-side OG fetcher with
  normalisation, 6s budget, 256KB HTML cap, OK/FAILED/TIMEOUT/BLOCKED
  status discriminator.
- Four typed authenticated multipart endpoints (`/api/chat/upload/image|
  audio|video|document`) with kind-specific size/mime gating. Per-user
  storage subdirectory `uploads/chat/<userId>/<kind>/<filename>`.
- `POST /api/chat/link-preview` for OG metadata resolution.
- `directMessageController.sendMessage` accepts the seven media fields and
  the `metadata.ticketId` reservation slot.
- Legacy `/api/chat/upload-media` retained (image-only, 8MB, unauth) for
  backwards compat with older clients.

**Frontend deliverables (shipped):**
- `lib/services/chat_media_service.dart` — typed envelopes for the four
  upload endpoints + link preview. `multipart()` calls go through
  `apiClient` so JWT auth attaches automatically.
- `lib/widgets/chat_media_bubble.dart` — canonical `ChatMediaBubble` that
  renders all five kinds (Image, Video, Audio, Document, Link). The same
  widget drops into direct chat, trade chat, ticket workspaces (UI-4),
  and vault grids (UI-5) without re-implementation.
- `pubspec.yaml` — `file_picker: ^8.1.4` added for document selection.
  `image_picker`, `record`, `open_filex` already present.

**Deferred to a polish PR (non-blocking):** in-bubble inline audio playback
with scrubber + an in-app hold-to-record audio recorder UI. The upload
endpoint already accepts pre-computed waveform peaks so the recorder can
drop in without backend changes.

15.4 TASK 4 — TICKETS ENGINE (FE + BE — Phase UI-4)

Status: IN REVIEW (BE + FE PR pair). **Highest-impact feature in the sprint.**

Tickets are isolated, trackable chat workspaces generated inside an existing
peer-to-peer chat conversation to record a specific business deal,
transaction, or agreement. They are NOT trades — trades are the formal
escrow-backed P2P marketplace flow. Tickets are lightweight social-
transactional records that two parties create to track an off-platform deal,
service swap, or escrow arrangement they're negotiating.

**Backend deliverables (shipped):**
- New `Ticket` + `TicketMessage` Prisma models with `TicketType`
  (BUY/SELL/ESCROW/SERVICE_SWAP) and `TicketStatus` (OPEN/CLOSED/CANCELLED)
  enums. `Friendship.localNicknames` JSONB column shipped now (Phase UI-5
  uses it). `TicketMessage` reuses every Phase UI-3 media column so
  `chat_media_bubble.dart` renders identically.
- Six REST endpoints (`/api/tickets`): create, list (paginated), detail,
  send-message, status-change (close/cancel/reopen with legal-transition
  guard), presence-ping. All `protect`-gated.
- `services/ticketSocketService.js` for `join_ticket` / `leave_ticket` /
  `ticket_typing`. Server-emitted: `ticket_created`, `ticket_message`,
  `ticket_status_changed`, `ticket_presence_update`.
- Status changes inject a `TICKET_LINK` event card into the parent
  friendship chat. Tickets do NOT touch any wallet column or trigger
  AZM rewards — they are pure chat artifacts.

**Frontend deliverables (shipped):**
- `lib/services/ticket_service.dart` — typed REST client.
- `lib/providers/ticket_provider.dart` — two Riverpod families
  (`ticketDashboardProvider` + `ticketWorkspaceProvider`).
- `lib/screens/tickets/ticket_dashboard_screen.dart` — 3-tab
  Open/Closed/Cancelled list with FAB.
- `lib/screens/tickets/ticket_create_sheet.dart` — structured creation
  form (name, type, target amount + currency, memo).
- `lib/screens/tickets/ticket_workspace_screen.dart` — isolated chat
  surface with header card, presence banner, message list (reuses
  `ChatMediaBubble`), close/cancel/reopen menu.
- `lib/screens/friends/friend_chat_screen.dart`: legacy "Transfer" icon
  REPLACED with the prominent Ticket button. New `TICKET_LINK` event
  card renderer in the parent chat feed. New socket listener for the
  presence banner.

15.4.1 HEADER NAV & PRESENCE
- Remove the existing "Send Money" icon (`Icons.swap_horiz_rounded` /
  `Icons.attach_money_rounded`) from the top-right of the personal chat
  AppBar. Replace with a prominent **Ticket Button** (`Icons.confirmation_number_rounded`).
  Send-money still reachable via the in-chat `+` send-funds button.
- **Presence indicator.** When user A taps into a ticket workspace, the
  main chat surface for both A and B shows a system banner:
  *"<friendName> is currently viewing the ticket window."* Implemented
  via socket `ticket_presence_update` (fanned out to room
  `friend_chat_${friendshipId}`).

15.4.2 TICKET DASHBOARD
Tapping the Ticket Button opens an overlay/view containing:
- Tabbed list: **Open Tickets** | **Closed Tickets** | **Cancelled Tickets**.
- Floating Action Button (`+`) at bottom-right to spawn a new workspace.
- Each row shows: ticket name, type badge (Buy/Sell/Escrow/Service Swap),
  target amount + currency, last activity timestamp, status chip.

15.4.3 TICKET CREATION FORM
The `+` button launches a clean form requiring:
- **Ticket Name** (String, required, 80 char max)
- **Transaction Type** (Enum: BUY / SELL / ESCROW / SERVICE_SWAP)
- **Target Value/Amount** (Decimal field) + **Asset Currency Selector**
  (USD, GHS, USDC, USDT, AZM, plus other major fiat — same picker shape as
  the trade-confirm sheet)
- **Memo / Terms of Deal** (Text field, 500 char max)

15.4.4 MAIN CHAT FEED INTEGRATION
- On successful ticket creation, the backend automatically injects a
  `TICKET_CREATED` event card directly into the parent chat stream showing
  ticket icon + ticket name + type + target amount.
- **Interactive Bridge.** Both parties tap the event card → deep-link into
  that specific isolated ticket's chat workspace.

15.4.5 BACKEND DATA MODEL (proposed)
- **`Ticket` model:** `id`, `friendshipId` (FK), `creatorId`, `counterpartyId`,
  `name`, `type` (enum), `targetAmount` (Decimal(20,8)), `targetCurrency`,
  `memo`, `status` (OPEN | CLOSED | CANCELLED), `createdAt`, `closedAt`,
  `cancelledAt`, `lastActivityAt`. Indexed on (`friendshipId`, `status`,
  `lastActivityAt DESC`).
- **`TicketMessage` model:** Same shape as `PersonalChatMessage` but scoped
  to a `ticketId`. Same media types (text, image, video, document, audio,
  link, transfer). Reuses Task 3's media infrastructure.
- **Endpoints:**
  - `POST /api/tickets` — create ticket (body: friendshipId, name, type,
    targetAmount, targetCurrency, memo). Returns ticket + injects event into
    parent chat.
  - `GET /api/tickets?friendshipId=&status=` — list tickets for a friendship,
    paginated.
  - `GET /api/tickets/:id` — full ticket detail + last 50 messages.
  - `POST /api/tickets/:id/messages` — send a message in the ticket.
  - `PATCH /api/tickets/:id/status` — close or cancel.
  - `POST /api/tickets/:id/presence` — emit presence ping (socket-bridged).
- **Socket events:**
  - `ticket_created` (room: `friendship_${id}`) — dashboard refresh + parent
    chat injection.
  - `ticket_message` (room: `ticket_${id}`) — new message in workspace.
  - `ticket_presence_update` (room: `friendship_${id}`) — A is viewing
    ticket X / A left ticket X.
  - `ticket_status_changed` — closed / cancelled / reopened.

15.5 TASK 5 — CHAT PROFILE + TRANSACTION VAULT (FE + BE — Phase UI-5)

Status: IN REVIEW (BE + FE PR pair).

Tapping a user's avatar/profile image inside any chat window routes to an
upgraded **Chat Profile Detail Screen** with a structured layout:

**Identity Tier (shipped).**
- Avatar, username, "Friends since {Mon Year}", three stat pills
  (Mutual trades / Their trades / Completion %), KYC verified badge.
- Inline edit pencil → dialog to set / modify / clear a **custom local
  nickname** for this contact. Stored on the BE under the observer's
  userId in `Friendship.localNicknames` JSON map (synced via `PATCH
  /api/friends/:friendshipId/nickname`) so it follows the user across
  devices. The nickname overrides the username in the profile screen
  header (with the original username retained as a `@username` subtitle).

**Media & Ledger Vault (Tabbed) (shipped).**
Tabs aggregate all historical items shared inside this thread:
1. **Media** — 3-column grid of images + videos, chronologically sorted.
   Mixes DirectMessage and TicketMessage rows; ticket-source items show
   a green "TICKET" ribbon overlay.
2. **Docs & Links** — list of documents (mime-aware icons, filenames,
   byte sizes) and link cards (OG title + site name).
3. **Tickets** — all open/closed/cancelled tickets between the two
   parties (reuses Phase UI-4 dashboard data; sorted by lastActivityAt).
4. **Receipts** — immutable records of direct P2P off-ticket money
   transfers between these two users (the existing "send money with
   reason" PeerTransfer flow). First-class transaction artifacts with
   reference IDs, masked amounts, status badges, direction arrows, and
   downloadable PDFs (reuses Phase Q11 receipt infrastructure, extended
   with `generateTransferReceipt`).

This cleanly differentiates casual balance transfers from structured
ticket deals, and gives both parties a permanent ledger of their
financial interactions.

**Backend additions (shipped).**
- `Friendship.localNicknames` JSON map: `{ "<observerUserId>": "<nickname>" }`
  — shipped with Phase UI-4's migration.
- New aggregator endpoints (all participant-gated):
  - `GET /api/friends/:friendshipId/profile` → identity tier
  - `PATCH /api/friends/:friendshipId/nickname` → set/clear local nickname
  - `GET /api/friends/:friendshipId/media?type=&cursor=` — paginated images/
    videos.
  - `GET /api/friends/:friendshipId/docs-links?cursor=` — paginated docs +
    link previews.
  - `GET /api/friends/:friendshipId/receipts?cursor=` — paginated P2P
    transfer receipts. Each row: id, amount, currency, reference (memo/
    reason), direction, status, createdAt, downloadUrl.
- Tickets vault tab is served by the existing `GET /api/tickets?friendshipId=`
  from Phase UI-4 — no new endpoint needed.
- New `GET /api/receipts/transfer/:id` endpoint that reuses Phase Q11's
  `receiptService.js` PDF generator, extended with
  `generateTransferReceipt(transfer, observer)`.

15.6 EXECUTION ORDER

| Task | Phase | Repos | Status |
|------|-------|-------|--------|
| 1 — UI De-cluttering | UI-1 | FE | IN REVIEW |
| 2 — Drawer Payout/Deposit Realignment | UI-2 | FE | IN REVIEW |
| 3 — Chat Media Infrastructure | UI-3 | FE + BE | IN REVIEW |
| 4 — Tickets Engine | UI-4 | FE + BE | IN REVIEW |
| 5 — Chat Profile + Transaction Vault | UI-5 | FE + BE | IN REVIEW |

Tasks 4 and 5 share Task 3's media infrastructure (audio/image/video/doc/link)
so Task 3 is a hard prerequisite for Task 4's full scope (text-only Tickets MVP
could ship in parallel).
