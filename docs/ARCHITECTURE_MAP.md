# AZAMAN — Experience Architecture Map (Overhaul Phase 0 / F1)

**Baseline:** `main` @ `6810007` (after #135 storefront shell, #136 Add Cash + typography).
**Scope:** this map is the Phase 0 audit required by the Deep Experience Overhaul brief (§4 Deliverable A). It names the canonical component for each area, lists duplicates / dead code to resolve in later parts, and records who owns vertical scroll on each screen. Every row was verified with `git grep` on the baseline commit; `path:line` anchors are indicative and will drift.

The foundation primitives introduced alongside this map live in `lib/experience/` and are **additive** — no existing screen changes in F1. Later parts (M1 marketplace discovery, M2 verticals, C1 chat hub, S1/S2 stories, G1 Susu/groups, K1 companion) consume them.

---

## 1. Canonical components (keep, extend)

| Area | Canonical | Notes |
|------|-----------|-------|
| App shell / tab roots | `lib/main.dart` (`FriendsHubScreen()` ~L556, `MarketplaceHomeScreen()` ~L558) | Tabs: Home 0, Chat 1, Marketplace 2 |
| Nav foundation | `lib/widgets/contextual_nav_band.dart` (`AppShellBus`/`appShellBus`, `ContextualNavBand`), `lib/widgets/premium_bottom_nav.dart` (`PremiumBottomNav(trailing:)`, `navScrollCompression`, `TabScrollRegistry`, `NavRetapController`), `PlusLauncherTrigger` | Context-reactive nav work anchors here; there is no search field in the nav today |
| Chat tab root | `lib/screens/friends/friends_hub_screen.dart` `FriendsHubScreen` | Owns inbox, story rail, friend search, requests sheet |
| Personal chat | `lib/screens/friends/friend_chat_screen.dart` | `premiumChatProvider(ChatContextParams(context: ChatContext.friend, contextId: friendshipId))` |
| Group chat | `lib/screens/group_chat/group_chat_screen.dart` + `group_profile_screen.dart` | `groupDetailProvider`, `susuInitiationStatusProvider(groupId)`, `groupActionsProvider` |
| Chat engine | `lib/providers/premium_chat_provider.dart` `PremiumChatNotifier` | Socket events `friend_message`, `new_group_message`, `message_ack`, `reaction_updated`, … |
| Message actions | `lib/services/message_action_service.dart` (`searchMessages`, …) | Search exists; mute/pin/archive/block/report have **no** backend endpoint yet (G1 gateway) |
| Stories | `lib/providers/story_provider.dart` `storyFeedProvider`, `lib/models/story_model.dart` `StoryGroup`/`StoryItem`, `lib/widgets/story_ring.dart` | Endpoints `/stories/feed`, `/stories/:id/view\|boost\|reply`, `/stories` multipart, highlights, analytics |
| Susu | `lib/models/susu_model.dart` (`SusuFrequency`, `SusuSuppliedRate`), `lib/providers/susu_provider.dart` (`susuDetailV2Provider`, `susuCyclesProvider`, `susuMembersProvider`, `susuSuppliedRateProvider`), `lib/services/susu_service.dart` | Group ↔ Susu link via `GroupSummary.susuGroupId/susuStatus` |
| Groups model | `lib/providers/group_chat_provider.dart` `GroupSummary{members: List<GroupMember>}`, `groupListProvider` | `GroupMember.userId`, `removedAt` |
| Friends model | `lib/providers/friend_provider.dart` `friendProvider` (`friends: List<Map<String,dynamic>>`) | Friend maps carry `friendshipId` with legacy `id` fallback (see `friends_hub_screen.dart` ~L1068) |
| Marketplace home | `lib/screens/marketplace/marketplace_home_screen.dart` (`_MarketplaceHomeMode.portal/explore`) | `businessSearchProvider`, `nearbySearchProvider`, `featuredBusinessesProvider`, `savedBusinessesProvider`, `cartProvider` |
| Storefront | `lib/screens/marketplace/market_storefront_shell.dart` `MarketStorefrontShell` + `MarketStorefrontSnaps{info .46, overview .62, shopping .78}`, hosted by `business_profile_screen.dart` | Content is injected via `productsBuilder` and callbacks; M2 adds vertical content there only |
| Business hours | `BusinessLocation.operatingHours` (`lib/models/business_models.dart`), parsed by `business_card.dart` `_isOpenNow()/_parseTime` | `businessMeta` is for showcase URLs, **not** hours |
| Vertical grammar | `lib/marketplace/experience/marketplace_experience_capabilities.dart` (`MarketplaceExperienceCatalog`), `lib/marketplace/experiences/marketplace_experience_blueprint.dart`, `lib/widgets/marketplace/marketplace_vertical_experience_stage.dart` | `LOGISTICS`=Transit, `FOOD_BEVERAGE`=Restaurants, `HOSPITALITY`(+legacy `REAL_ESTATE`)=Hotels, `RETAIL`=Retail |
| Flip-book menu | `lib/widgets/marketplace/restaurant_native_menu_journey.dart` `RestaurantNativeMenuJourney` + `restaurant_menu_journey_adapter.dart` | `sections: List<CatalogSection>`, `dishesById` |
| Sheets | `lib/theme/az_sheet.dart` `AzSheetWeight {whisper, panel, stage}`, `AzSheetGeometry`, `AzamanSheet.showPanel` | Use for every new bottom sheet |
| Motion | `lib/theme/motion_tokens.dart` `MotionTokens`, `lib/theme/az_motion.dart` `AzMotion` | `AzMotion.of(ctx).travel` is **the** reduced-motion gate |
| Radius | `lib/theme/az_radius.dart` `AzRadius` (xs 4, sm 8, md 12, lg 16, xl 20, xxl 28, pill) | No `card` token; cards use `lg` |
| Typography | `lib/theme/az_text.dart` `AzText` (`uiFamily = 'ComicNeue'`, `numericFamily = 'Inter'`, `money()`, `delta()`) | Landed in #136 |
| Haptics | `lib/utils/azaman_haptics.dart` `AzamanHaptics` (`selection`, `threshold`, `commit`, `confirm`, `nav`, `warn`, `moneyLanded`, …) | Never call `HapticFeedback.*` directly in new code |
| Realtime | `lib/services/socket_service.dart` `SocketService`, `lib/services/realtime_event_deduper.dart` `RealtimeEventDeduper.accept(eventId)` (256 entries) | Reuse the deduper for story reactions & companion events |
| In-app notification surfaces | `lib/main.dart` `_showSocketNotificationBanner` → `lib/widgets/in_app_push_banner.dart` `InAppPushBanner.show`; `lib/services/push_notification_service.dart` `_handleForeground`; `lib/providers/friend_provider.dart` `_handleFriendMessage` | These are the mute seams for G1 |
| Placement | `lib/widgets/liquid/liquid_placement.dart` `solvePanel(...)`, `LiquidSafeArea`, `PanelPlacement` | Anchored popovers |
| Demo mode | `lib/config.dart` `AppConfig.demoMode` / `enableDemoMode()`, `lib/data/demo_interceptor.dart` `DemoInterceptor` | The single demo flag; `DemoGuard` (below) delegates to it |
| Goldens | `test/goldens/golden_harness.dart` `pumpGoldenSurface`, `loadGoldenFonts` | Pinned size/DPR/font/disableAnimations |

### 1.1 Foundation primitives added in F1 (`lib/experience/`)

| File | Provides |
|------|----------|
| `az_spatial_mode.dart` | `AzSpatialMode` — where the user *is* (`portal`, `explore`, `preview`, `detail`, `fullScreenMedia`, `shopping`, `focusedAction`, `social`, `transactionalConfirmation`); `isCalm`, `isImmersive` |
| `az_intent.dart` | `AzIntent` — what the user is trying to *do*; `isDestructive`, `movesMoney`, `commitHaptic()` via `AzamanHaptics` |
| `az_surface.dart` | `AzSurfaceKind` + `AzSurfaceSpec.of(kind)` — one styling contract per surface kind, token-only radii |
| `motion/az_snap_solver.dart` | `AzSnapSolver(detents, commitFraction, flingVelocity).resolve(position, velocity)` — deterministic detent snapping |
| `motion/az_pull_reveal_controller.dart` | `AzPullRevealController` — extent 0..1 with drag/commit for pull-reveals outside a scrollable |
| `motion/az_identity_morph.dart` | `AzIdentityTag.business/user/group/story`, `AzIdentityMorph(tag, travel, child)` — Hero only when travel is allowed |
| `gateways/az_gateway_result.dart` | `AzGatewayResult<T>` sealed: `AzOk` / `AzFailed` / `AzUnsupported(reason)`; `valueOrNull`, `map` |
| `gateways/room_membership_resolver.dart` | `AzRoomId` (`friend:<id>` / `group:<id>`), `RoomMembershipResolver`, `LookupRoomMembershipResolver`, `ProviderRoomMembershipResolver`, `FixedRoomMembershipResolver` — unknown room → `false`, never a literal `true` |
| `demo/demo_guard.dart` | `DemoGuard.enabled` (delegates to `AppConfig.demoMode`), `assertEnabled(adapter)` |

Gateway files to be introduced by later parts (all return `AzGatewayResult` and expose a `capabilities` set so menus are built from what is actually implemented): `story_gateway.dart` (S1/S2), `chat_actions_gateway.dart` (G1), `marketplace_discovery_gateway.dart` (M1), `susu_membership_gateway.dart` (G1), `service_flow_gateway.dart` (M2), `companion_gateway.dart` (K1).

### 1.2 Motion language → tokens

| Word | Meaning | Implementation default |
|------|---------|------------------------|
| Glide | short spatial travel on context change | `MotionTokens.standard` + `MotionTokens.enter`, translate ≤ 24dp |
| Lift | reveal teaching a hidden surface | `AzPullRevealController` / `AzSnapSolver`, `MotionTokens.emphasized` |
| Nest | detail emerges from its launcher | `AzIdentityMorph` + `AzamanSheet.showPanel` |
| Peel | progressive media reveal | header `shrinkOffset` (C1), viewer dismiss scale (S1) |
| Dock | controls settle compact | `AnimatedPadding`/`AnimatedSize` with `MotionTokens.control` |
| Seal | final lock-in after money moved | `AzamanHaptics.moneyLanded` + a single 350 ms scale-in, **never** a loop |

---

## 2. Duplicates / dead / conflicting (resolve in the named part)

| Finding | Evidence | Action |
|---------|----------|--------|
| `lib/screens/messages_hub_screen.dart` `MessagesHubScreen` duplicates the inbox + story rail | Only referenced from `lib/router/app_router.dart:279`; the tab root is `FriendsHubScreen` | Deprecated. Not deleted in F1; C1 re-points the route to `FriendsHubScreen`, a follow-up removes the file |
| Story rail rendered three ways | `friends_hub_screen.dart` horizontal `ListView.builder`; `messages_hub_screen.dart`; `widgets/marketplace/marketplace_status_rail.dart` `MarketplaceExpandedStories` | C1 introduces one `StoryRailStrip` for chat; M1 reuses `MarketplaceExpandedStories` for merchant stories |
| Three-dot in personal chat is a placeholder | `friend_chat_screen.dart:606` `IconButton(icon: Icon(Icons.more_vert), onPressed: _openChatProfile)` | G1 replaces with a real `ChatActionsSheet` built from gateway capabilities |
| `Inbox` header hardcodes `fontSize: 28, w800` | `friends_hub_screen.dart:336` | C1 → `AzText` title tier |
| Marketplace has its own `_MarketplaceHomeMode` enum + `_searchExpanded` local search | `marketplace_home_screen.dart:63, 107, 113` | M1 introduces a single `marketplaceSearchProvider` the nav pill and explore screen both read. `_MarketplaceHomeMode` stays (screen mode, not nav state) |
| Story viewer is single-group | `story_viewer_screen.dart` has one progress controller and no horizontal `PageView` | S1 rebuilds as multi-creator viewer |
| Story editor keeps one stroke (`List<Offset> _drawPoints`, :101) and ad-hoc `_OverlayItem` (:40) | `story_editor_screen.dart` | S2 introduces a `StoryScene` document + reducer with undo |
| Hub body is `Column(... Expanded(ListView))` → story rail outside the scroll owner | `friends_hub_screen.dart` build | C1 converts to one `CustomScrollView` |
| `StoryCameraScreen` simulates a preview (`image_picker` only; no `camera` dep) | `pubspec.yaml` | S2 is an explicit decision point (real camera vs picker) |
| Companion membership check | no production code yet; the reviewed draft had `_isMemberOf => true` | Resolved in F1 by `RoomMembershipResolver`; K1 must inject it |

---

## 3. Scroll-owner inventory

| Screen | Vertical owners today | Target |
|--------|----------------------|--------|
| FriendsHub | `Column` → fixed rail + `ListView.separated` | one `CustomScrollView` (C1) |
| FriendChat | `ListView.builder(reverse: true)` | unchanged; search jumps use `Scrollable.ensureVisible` (G1) |
| BusinessProfile | `MarketStorefrontShell`: `DraggableScrollableSheet` with `MarketStorefrontSnaps` | unchanged — M2 adds content via `productsBuilder` only |
| MarketplaceHome | `RefreshIndicator` → portal `Column` / explore list | portal becomes a `CustomScrollView` (M1) |
| StoryViewer | none (`Stack`) | horizontal `PageView` + vertical drag owned by the page (S1) |

---

## 4. Guardrails (apply per screen in every later part)

1. Any surface that re-renders on a drag tick (`shrinkOffset`, sheet extent, odometer) is wrapped in `RepaintBoundary` **at the leaf**, not around the whole screen.
2. Scroll-driven visuals read offsets through `AnimatedBuilder`/`ValueListenableBuilder` on the controller, never `setState` on the screen.
3. Provider reads inside item builders are `ref.watch(provider.select(...))` for the single field needed.
4. Futures used by `FutureBuilder` are created in `initState`/notifiers, never in `build`.
5. Every `AnimationController`/`VideoPlayerController`/`StreamSubscription` has a matching dispose; `PageView` children stop work when not current.
6. No `Timer.periodic` for interaction state. The only timers allowed are semantic (story progress uses an `AnimationController`; placeholder rotation uses a ticker that is stopped on focus).
7. Reduced motion is `AzMotion.of(ctx).travel`; with travel off the **semantic end state** must still be reached after a single frame.
8. Capability truth: a menu item exists only if its gateway reports the capability; `AzUnsupported` hides the action instead of rendering a dead button.
9. Demo adapters are only constructed behind `DemoGuard.enabled` via `ProviderScope(overrides: [...])`, never inside production provider bodies.

## 5. Test conventions

- Pure solvers (`AzSnapSolver`, scene reducers, membership derivations) get plain `test()` files under `test/experience/`.
- Widget behaviour tests pump with `tester.pump(MotionTokens.emphasized)` after gestures; assert via controller getters or `find.byKey`.
- Reduced-motion tests wrap in `MediaQuery(data: MediaQueryData(disableAnimations: true))` **inside** `MaterialApp.home` and assert the semantic end state after a single `pump()`.
- Goldens use `pumpGoldenSurface` with deterministic fixtures (no network images). Never regenerate goldens to make a suite pass; a regeneration is its own reviewable commit.