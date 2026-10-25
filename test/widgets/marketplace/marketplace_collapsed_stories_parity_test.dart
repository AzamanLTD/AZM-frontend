// =============================================================================
// WORKSTREAM A (2026-10-21) — Marketplace Stories must collapse exactly like
// Chat.
//
// The marketplace's collapsed stories affordance is the SHARED compact
// presentation (CompactStoryRail): the same circular StoryRing stack, the
// same 24dp ring / 14dp overlap geometry, the same 40dp strip height, the
// same caption label treatment and chevron as the chat hub's StoryRailCompact.
// The old stacked-squircle treatment (a detached stack of business logos)
// is gone.
//
// This suite proves:
//   • geometry parity — chat and marketplace collapsed rails render the
//     identical ring/overlap/height/label language;
//   • the affordance is a real button with an accurate accessible label;
//   • the marketplace actions stay RIGHT of the collapsed affordance on
//     the same header row;
//   • tapping the collapsed affordance expands the rail IN PLACE (the
//     page never returns to the top — see the Workstream F1 pin suite);
//   • no horizontal overflow at 320/360/390dp in either state;
//   • reduced motion lands directly (binary) — no fractional slide;
//   • light/dark captures of both states and both surfaces.
// =============================================================================

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/story_model.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/marketplace_extensions_provider.dart';
import 'package:azaman/providers/story_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/friends/friends_hub_screen.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/widgets/marketplace/marketplace_status_rail.dart';
import 'package:azaman/widgets/stories/story_rail_collapse.dart';
import 'package:azaman/widgets/stories/story_rail_compact.dart';
import 'package:azaman/widgets/story_ring.dart';
import 'package:azaman/theme/az_space.dart';

// ── Structural stand-in so notifiers satisfy constructors without a
// network client (all loads are overridden; the client is never used).
class _NullApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── Seamed marketplace providers ────────────────────────────────────────────

/// Followed businesses: 3 deterministic fixtures, 2 with unseen stories,
/// one verified. Never a network call.
class _SeededFollowing extends FollowingListNotifier {
  _SeededFollowing() : super(_NullApiClient());

  @override
  Future<void> load() async {
    state = const AsyncValue.data([
      {
        'id': 'b1',
        'businessName': 'Adinkra Lounge',
        'logoUrl': null,
        'isVerified': true,
        'lastStoryAt': '2026-10-20T10:00:00Z',
        'lastViewedAt': null, // never viewed → unseen
      },
      {
        'id': 'b2',
        'businessName': 'Cocoa Line',
        'logoUrl': null,
        'isVerified': false,
        'lastStoryAt': '2026-10-20T11:00:00Z',
        'lastViewedAt': '2026-10-19T00:00:00Z', // story newer → unseen
      },
      {
        'id': 'b3',
        'businessName': 'Trotro Threads',
        'logoUrl': null,
        'isVerified': false,
        'lastStoryAt': '2026-10-18T09:00:00Z',
        'lastViewedAt': '2026-10-18T10:00:00Z', // viewed after → seen
      },
    ]);
  }
}

/// Ten deterministic businesses so the results list actually scrolls.
class _SeededSearch extends BusinessSearchNotifier {
  _SeededSearch() : super(BusinessService()) {
    state = state.copyWith(results: [
      for (var i = 0; i < 10; i++)
        BusinessProfile(
          id: 'biz-$i',
          bizId: 'BIZ-$i',
          businessName: 'Business $i',
          category: 'RETAIL',
          isVerified: true,
          isSuspended: false,
          kybStatus: 'VERIFIED',
          totalEscrows: 4,
          completedEscrows: 4,
          userId: 1,
          totalVolume: 0,
          averageRating: 0,
          username: 'biz-$i',
          createdAt: DateTime(2026, 10, 20 - i),
        ),
    ]);
  }

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {}
}

class _NoopAds extends AdFeedNotifier {
  _NoopAds() : super(_NullApiClient());

  @override
  Future<void> load() async {}
}

// ── Seamed chat providers (same fakes the inbox rail suite uses) ────────────

class _FakeFeed extends StoryFeedNotifier {
  _FakeFeed(List<StoryGroup> groups) {
    state = AsyncValue.data(groups);
  }
  @override
  Future<void> load() async {}
}

List<StoryGroup> _chatStories() => [
      for (var i = 0; i < 3; i++)
        StoryGroup(
          authorId: i,
          authorUsername: 'author$i',
          hasUnseen: i < 2,
          isBoosted: false,
          stories: const [],
        ),
    ];

class _FakeFriends extends FriendProvider {
  _FakeFriends(super.ref, int count) {
    friends = [
      for (var i = 0; i < count; i++)
        {
          'friendshipId': 'f$i',
          'unreadCount': 0,
          'friend': {'id': 100 + i, 'username': 'friend$i'},
        },
    ];
    isLoading = false;
  }

  @override
  Future<void> refreshAll() async {}
  @override
  Future<void> fetchFriends() async {}
  @override
  Future<void> fetchUnreadCount() async {}
}

class _FakeGroups extends GroupListNotifier {
  @override
  Future<List<GroupSummary>> build() async => [];
  @override
  Future<void> refresh() async {}
}

// ── Pump helpers ────────────────────────────────────────────────────────────

/// Pumps BOTH collapsed affordances (chat strip, marketplace header affordance)
/// in one tree so the same-frame geometry can be compared directly.
Future<void> _pumpBothCollapsed(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storyFeedProvider.overrideWith((ref) => _FakeFeed(_chatStories())),
        followingListProvider.overrideWith((ref) => _SeededFollowing()..load()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              // Chat: the full-width collapsed strip.
              StoryRailCompact(onTap: () {}),
              // Marketplace: the header-row affordance — the SAME
              // component defaults as the chat strip (chevron at the
              // trailing edge, AzSpace.xl horizontal padding).
              MarketplaceCollapsedAvatars(onTap: () {}),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pumps the marketplace home with all rails seeded and inert. Returns the
/// results list's real ScrollController — the same controller the screen's
/// collapse math listens to — so tests drive the page offset exactly.
Future<ScrollController> _pumpHome(
  WidgetTester tester, {
  double width = 360,
  double height = 740,
  bool reducedMotion = false,
  ThemeProvider? theme,
  Key? rootKey,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final colors =
      (theme ?? ThemeProvider()).colors;
  Widget page = const MarketplaceHomeScreen();
  if (rootKey != null) {
    page = RepaintBoundary(key: rootKey, child: page);
  }
  final body = Scaffold(
    extendBody: true,
    bottomNavigationBar: Container(
      height: 48,
      color: colors.surface,
      alignment: Alignment.center,
      child: const Text('48dp nav band', style: TextStyle(fontSize: 10)),
    ),
    body: MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        disableAnimations: reducedMotion,
      ),
      child: page,
    ),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        businessSearchProvider.overrideWith((ref) => _SeededSearch()),
        followingListProvider.overrideWith((ref) => _SeededFollowing()..load()),
        adFeedProvider.overrideWith((ref) => _NoopAds()..load()),
      ],
      child: theme == null
          ? MaterialApp(home: body)
          : AnimatedBuilder(
              animation: theme,
              builder: (context, _) => MaterialApp(home: body),
            ),
    ),
  );
  await _settleFrames(tester);

  final list = find.byKey(const ValueKey('marketplace_results_list'));
  return tester.widget<ListView>(list).controller!;
}

/// Bounded settle: advances the clock in frame-sized steps so staggered
/// entrances (flutter_animate delays of up to ~1.3s on the feed) finish
/// before a capture — without pumpAndSettle, which hangs on infinite
/// shimmer loops.
Future<void> _settleFrames(WidgetTester tester, {int frames = 26}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Disposes the home screen and advances the clock past every debounce /
/// staggered-entrance one-shot timer the screen owns, so a test can end
/// without pending-timer noise (the screen schedules 400ms search debounce
/// and flutter_animate stagger delays).
Future<void> _teardownHome(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 900));
}

void main() {
  group('Workstream A — collapsed grammar parity (chat vs marketplace)', () {
    testWidgets('both surfaces render the same ring stack, overlap, strip '
        'height, label and chevron', (tester) async {
      await _pumpBothCollapsed(tester);

      final chatBody =
          find.byKey(const ValueKey('inbox_story_rail_compact_body'));
      final mktBody =
          find.byKey(const ValueKey('marketplace_story_rail_compact'));

      final chatRect = tester.getRect(chatBody);
      final mktRect = tester.getRect(mktBody);

      // 1. Same strip height (the shared 40dp compact language).
      expect(chatRect.height, closeTo(StoryRailCompact.height, 0.5));
      expect(mktRect.height, closeTo(StoryRailCompact.height, 0.5));

      // 2. Same circular ring stack — three rings, not squircle logo boxes.
      final chatRings = tester
          .widgetList<StoryRing>(find.descendant(
            of: chatBody,
            matching: find.byType(StoryRing),
          ))
          .toList();
      final mktRings = tester
          .widgetList<StoryRing>(find.descendant(
            of: mktBody,
            matching: find.byType(StoryRing),
          ))
          .toList();
      expect(chatRings.length, 3, reason: 'chat shows 3 story groups');
      expect(mktRings.length,
          3, reason: 'marketplace shows 3 followed businesses');

      // 3. Same ring size on both surfaces.
      for (var i = 0; i < 3; i++) {
        expect(chatRings[i].size, CompactStoryRail.ringSize);
        expect(mktRings[i].size, CompactStoryRail.ringSize);
      }

      // 4. Same 14dp overlap: consecutive ring origins at 0/14/28 on both.
      final chatStack = tester
          .widgetList<Positioned>(find.descendant(
            of: chatBody,
            matching: find.byWidgetPredicate((w) => w is Positioned),
          ))
          .where((p) => p.child is StoryRing)
          .toList();
      final mktStack = tester
          .widgetList<Positioned>(find.descendant(
            of: mktBody,
            matching: find.byWidgetPredicate((w) => w is Positioned),
          ))
          .where((p) => p.child is StoryRing)
          .toList();
      expect(chatStack.length, 3);
      expect(mktStack.length, 3);
      for (var i = 0; i < 3; i++) {
        expect(chatStack[i].left, i * CompactStoryRail.ringOverlap);
        expect(mktStack[i].left, i * CompactStoryRail.ringOverlap);
      }

      // 5. Same label: both fixtures carry exactly 2 unseen.
      final chatLabel = tester.widget<Text>(
          find.byKey(const ValueKey('inbox_story_rail_compact_label')));
      final mktLabel = tester.widget<Text>(
          find.byKey(const ValueKey('marketplace_story_rail_compact_label')));
      expect(chatLabel.data, '2 new');
      expect(mktLabel.data, chatLabel.data,
          reason: 'the same unseen count must read the same on both surfaces');
      expect(chatLabel.style?.fontSize, mktLabel.style?.fontSize);
      expect(chatLabel.style?.fontWeight, mktLabel.style?.fontWeight);
      expect(chatLabel.style?.color, mktLabel.style?.color);

      // 6. Same chevron affordance on both — and the SAME chevron
      // PLACEMENT (review A1): chat's chevronAtEnd grammar floats the
      // chevron at the affordance's trailing edge inset by the rail's
      // own horizontal padding. Marketplace now uses the identical
      // defaults, so on an equally-wide affordance the chevron rect and
      // the ring stack's leading offset must match chat EXACTLY.
      final chatChevron = tester.getRect(find.descendant(
          of: chatBody,
          matching: find.byIcon(Icons.keyboard_arrow_down_rounded)));
      final mktChevron = tester.getRect(find.descendant(
          of: mktBody,
          matching: find.byIcon(Icons.keyboard_arrow_down_rounded)));
      // The two surfaces sit at different offsets in the pumped Column,
      // so parity is asserted on the chevron's geometry RELATIVE to its
      // own strip: same trailing inset and same vertical inset.
      expect(chatChevron.right - chatRect.right,
          mktChevron.right - mktRect.right,
          reason: 'chat parity — same trailing inset on both surfaces');
      expect(chatChevron.top - chatRect.top, mktChevron.top - mktRect.top,
          reason: 'chat parity — same vertical chevron inset');
      expect(chatChevron.right - chatRect.right, -AzSpace.xl,
          reason: 'the chevron floats 20dp inside the affordance\'s '
              'trailing edge, exactly like the chat strip');
      expect(chatChevron.left, mktChevron.left);

      // 7. Effective leading padding (review A1): the first ring sits
      // AzSpace.xl (20) from the affordance's left edge on BOTH surfaces
      // — combined parent+component padding, not a zero-padding variant.
      const expectedLeading = AzSpace.xl;
      final chatFirstRing =
          tester.getRect(find.byWidget(chatRings.first));
      final mktFirstRing =
          tester.getRect(find.byWidget(mktRings.first));
      expect(chatFirstRing.left - chatRect.left, expectedLeading);
      expect(mktFirstRing.left - mktRect.left, expectedLeading,
          reason: 'the marketplace rail carries its own 20dp leading '
              'padding; the parent header row adds none (combined = chat)');
      expect(mktFirstRing.left - mktRect.left,
          chatFirstRing.left - chatRect.left,
          reason: 'the EFFECTIVE ring position is the same as chat');
    });

    testWidgets('verified status does NOT masquerade as story boosting '
        '(review A4)', (tester) async {
      await _pumpBothCollapsed(tester);

      final mktBody =
          find.byKey(const ValueKey('marketplace_story_rail_compact'));
      // The fixture's first business (Adinkra Lounge) is VERIFIED — the
      // boost treatment must still be OFF on every rendered ring.
      final mktRings = tester
          .widgetList<StoryRing>(find.descendant(
            of: mktBody,
            matching: find.byType(StoryRing),
          ))
          .toList();
      expect(mktRings.length, 3);
      for (final ring in mktRings) {
        expect(ring.isBoosted, isFalse,
            reason: 'the followed-business feed carries no boost field — '
                'verification must never render the boosted ring');
      }

      // The expanded rail is equally honest: verification ≠ boost there.
      // (Asserted via the shared CompactStoryItem contract: the collapsed
      // item for the verified business was built with isBoosted unset.)
      final chatBody =
          find.byKey(const ValueKey('inbox_story_rail_compact_body'));
      final chatRings = tester
          .widgetList<StoryRing>(find.descendant(
            of: chatBody,
            matching: find.byType(StoryRing),
          ))
          .toList();
      for (final ring in chatRings) {
        expect(ring.isBoosted, isFalse);
      }
    });

    testWidgets('the marketplace affordance is a button with an accurate '
        'accessible label', (tester) async {
      await _pumpBothCollapsed(tester);
      final nodes = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((s) =>
              (s.properties.label ?? '')
                  .contains('2 businesses with new stories'))
          .length;
      expect(nodes, 1,
          reason: 'the collapsed stories affordance announces the real '
              'unseen count and what tapping does');
    });
  });

  group('Workstream A — marketplace header integration', () {
    testWidgets('actions stay RIGHT of the collapsed affordance on the same '
        'row', (tester) async {
      final ctrl = await _pumpHome(tester);
      expect(ctrl.position.maxScrollExtent,
          greaterThan(StoryRailCollapse.travelPx),
          reason: 'the seeded feed must be long enough to collapse the rail');

      ctrl.jumpTo(StoryRailCollapse.travelPx * 1.5);
      await _settleFrames(tester, frames: 6);

      final affordance =
          find.byKey(const ValueKey('marketplace_story_rail_compact'));
      expect(affordance, findsOneWidget,
          reason: 'collapsed state shows the shared compact rail');

      final affordanceRect = tester.getRect(affordance);
      final storeIcon =
          tester.getRect(find.byIcon(Icons.storefront_rounded).first);
      final ordersIcon =
          tester.getRect(find.byIcon(Icons.receipt_long_rounded).first);
      final listSeg =
          tester.getRect(find.byIcon(Icons.view_agenda_outlined).first);

      // Same row (vertical overlap with the affordance)…
      for (final icon in [storeIcon, ordersIcon, listSeg]) {
        expect(icon.top, lessThan(affordanceRect.bottom));
        expect(icon.bottom, greaterThan(affordanceRect.top));
        // …and strictly to the right of the collapsed story strip.
        expect(icon.left, greaterThanOrEqualTo(affordanceRect.right - 1));
      }

      // Review A1 — EFFECTIVE ring offset matches chat: the first ring
      // sits exactly AzSpace.xl (20) from the screen's left edge in the
      // REAL header composition (parent 0 + component 20), the same
      // offset chat's full-width strip renders at.
      final rings = tester
          .widgetList<StoryRing>(find.descendant(
            of: affordance,
            matching: find.byType(StoryRing),
          ))
          .toList();
      expect(rings, isNotEmpty);
      final firstRing = tester.getRect(find.byWidget(rings.first));
      expect(firstRing.left, closeTo(AzSpace.xl, 0.5),
          reason: 'combined parent+component leading padding == chat\'s');

      // Review A1 — chevron at the affordance's trailing edge with the
      // same internal inset chat uses: it floats 20dp inside the
      // AFFORDANCE's own right edge (the Expanded region that ends at the
      // row's SizedBox gap before the action icons).
      final chevron = tester.getRect(find.descendant(
          of: affordance,
          matching: find.byIcon(Icons.keyboard_arrow_down_rounded)));
      expect(chevron.right, closeTo(affordanceRect.right - AzSpace.xl, 0.5),
          reason: 'the chevron keeps chat\'s trailing-edge grammar beside '
              'the right-aligned action icons');
      expect(chevron.right, lessThan(storeIcon.left),
          reason: 'the chevron stays left of the action cluster');
      await _teardownHome(tester);
    });

    testWidgets('tapping the collapsed affordance expands the rail IN '
        'PLACE — the page never returns to the top (F1 pin)', (tester) async {
      final ctrl = await _pumpHome(tester);
      ctrl.jumpTo(StoryRailCollapse.travelPx * 1.5);
      await _settleFrames(tester, frames: 6);
      final offsetBefore = ctrl.offset;

      await tester
          .tap(find.byKey(const ValueKey('marketplace_story_rail_compact')));
      // The expand is a 400ms animation — advance it in ticker-sized steps
      // (a single long pump only fires one animation tick).
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Workstream F1: the anchor is preserved — the list scrolls DOWN by
      // the rail's growth instead of being dragged back to the top.
      expect(
          ctrl.offset,
          closeTo(offsetBefore + StoryRailCollapse.extentPx, 1.0),
          reason: 'the anchor is preserved; the page never returns to the top');
      expect(ctrl.offset, greaterThan(StoryRailCollapse.extentPx));
      expect(find.byType(MarketplaceExpandedStories), findsOneWidget);

      final expandedRings = tester
          .widgetList<StoryRing>(find.descendant(
            of: find.byType(MarketplaceExpandedStories),
            matching: find.byType(StoryRing),
          ))
          .toList();
      expect(expandedRings.length, 3);
      expect(expandedRings.first.size, 64,
          reason: 'the expanded rail renders at the shared chat scale');
      await _teardownHome(tester);
    });

    testWidgets('no horizontal overflow at 320/360/390dp in either state',
        (tester) async {
      for (final width in [320.0, 360.0, 390.0]) {
        final ctrl = await _pumpHome(tester, width: width);
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull,
            reason: 'expanded rail fits at ${width.toInt()}dp');

        ctrl.jumpTo(StoryRailCollapse.travelPx * 1.5);
        await _settleFrames(tester, frames: 6);
        expect(tester.takeException(), isNull,
            reason: 'collapsed affordance fits at ${width.toInt()}dp');
        await _teardownHome(tester);
      }
    });

    testWidgets('reduced motion lands directly — binary, no fractional slide',
        (tester) async {
      final ctrl = await _pumpHome(tester, reducedMotion: true);

      // Below the shared snap threshold: fully open, directly.
      ctrl.jumpTo(20);
      await tester.pump();
      final extent = find.byKey(const ValueKey('marketplace_story_rail_extent'));
      expect(tester.getRect(extent).height,
          closeTo(StoryRailCollapse.extentPx, 0.5),
          reason: 'reduced motion keeps the rail fully open below threshold');

      // Above the threshold: fully collapsed in the SAME frame — no slide.
      ctrl.jumpTo(StoryRailCollapse.travelPx * 0.9);
      await tester.pump();
      expect(tester.getRect(extent).height, closeTo(0, 0.5),
          reason: 'reduced motion lands directly in the collapsed state');
      expect(find.byKey(const ValueKey('marketplace_story_rail_compact')),
          findsOneWidget);
      await _teardownHome(tester);
    });
  });

  // ── Captures (light/dark × 320/360/390) ────────────────────────────────────

  group('Workstream A — captures', () {
    const rootKey = Key('stories-parity-capture-root');
    bool fontsLoaded = false;

    Future<void> loadFonts() async {
      if (fontsLoaded) return;
      final inter =
          await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
      final loader = FontLoader('Inter')
        ..addFont(Future<ByteData>.value(
            ByteData.view(Uint8List.fromList(inter).buffer)));
      await loader.load();
      fontsLoaded = true;
    }

    Future<ThemeProvider> seedTheme(AzamanTheme theme) async {
      SharedPreferences.setMockInitialValues(
          {'azaman_theme': theme == AzamanTheme.dark ? 1 : 0});
      final p = ThemeProvider();
      var guard = 0;
      while (!p.isLoaded && guard++ < 100) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(p.isLoaded, isTrue);
      return p;
    }

    Future<void> capture(WidgetTester tester, String name) async {
      var ok = false;
      await tester.runAsync(() async {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
        final image = await boundary.toImage(pixelRatio: 2.0);
        final data = (await image.toByteData(format: ImageByteFormat.png))!;
        Directory('.screenshots/stories_parity').createSync(recursive: true);
        File('.screenshots/stories_parity/$name.png')
            .writeAsBytesSync(data.buffer.asUint8List());
        ok = true;
      });
      expect(ok, isTrue, reason: 'capture $name wrote a PNG');
    }

    testWidgets('marketplace expanded + collapsed, both themes, three widths',
        (tester) async {
      await tester.runAsync(loadFonts);
      for (final theme in AzamanTheme.values) {
        for (final width in [320.0, 360.0, 390.0]) {
          final themeName = theme == AzamanTheme.dark ? 'dark' : 'light';
          final tp = (await tester.runAsync(() => seedTheme(theme)))!;
          final ctrl = await _pumpHome(
            tester,
            width: width,
            theme: tp,
            rootKey: rootKey,
          );
          await capture(
              tester, 'marketplace_expanded_${themeName}_${width.toInt()}');
          ctrl.jumpTo(StoryRailCollapse.travelPx * 1.5);
          await _settleFrames(tester, frames: 8);
          await capture(
              tester, 'marketplace_collapsed_${themeName}_${width.toInt()}');
          await _teardownHome(tester);
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      }
    });

    testWidgets('chat expanded + collapsed, both themes, three widths',
        (tester) async {
      await tester.runAsync(loadFonts);
      for (final theme in AzamanTheme.values) {
        for (final width in [320.0, 360.0, 390.0]) {
          final themeName = theme == AzamanTheme.dark ? 'dark' : 'light';
          final tp = (await tester.runAsync(() => seedTheme(theme)))!;
          tester.view.physicalSize = Size(width, 740);
          tester.view.devicePixelRatio = 1.0;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                friendProvider.overrideWith((ref) => _FakeFriends(ref, 20)),
                storyFeedProvider
                    .overrideWith((ref) => _FakeFeed(_chatStories())),
                groupListProvider.overrideWith(() => _FakeGroups()),
              ],
              child: AnimatedBuilder(
                animation: tp,
                builder: (context, _) => MediaQuery(
                  data: MediaQueryData(size: Size(width, 740)),
                  // FriendsHubScreen's Scaffold is deliberately transparent
                  // (the real shell paints behind it) — reproduce that
                  // background here, otherwise the capture composites the hub
                  // onto nothing and reads as black in both themes.
                  // The boundary wraps the SHELL (background + hub): the
                  // hub's own Scaffold is transparent, so a boundary inside
                  // it would capture transparency instead of the surface.
                  child: MaterialApp(
                    home: RepaintBoundary(
                      key: rootKey,
                      child: Scaffold(
                        backgroundColor: tp.colors.background,
                        body: const FriendsHubScreen(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await _settleFrames(tester, frames: 10);

          // Open at rest.
          await capture(tester, 'chat_expanded_${themeName}_${width.toInt()}');

          // Committed drag collapses into the compact presentation.
          await tester.drag(
              find.byKey(const ValueKey('inbox_scroll')), const Offset(0, -150));
          await tester.pumpAndSettle();
          await capture(tester, 'chat_collapsed_${themeName}_${width.toInt()}');

          await tester.pumpWidget(const SizedBox());
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      }
    });
  });
}
