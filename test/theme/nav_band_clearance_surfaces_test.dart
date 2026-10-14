// NAV BAND CLEARANCE — surface regression tests (PR #151).
//
// The contract tests in nav_band_clearance_test.dart pin the Scaffold
// behaviour the abstraction reads. THESE tests pin the actual root-tab
// SURFACES: every scrollable ending under the persistent band must pad
// with the LIVE published clearance + kNavBandGap — never a magic
// number. Each test mounts the surface inside the same shell shape the
// app uses (Scaffold(extendBody: true) + a fixed-height band), so the
// assertion catches any regression back to a hardcoded guess.

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/story_provider.dart';
import 'package:azaman/screens/friends/friends_hub_screen.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/theme/nav_band_clearance.dart';
import 'package:azaman/widgets/collapsible_business_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The band stand-in — 92px, well above the old magic guesses (60/120),
/// so a surface still hardcoding one of them fails the expectation.
class _FixedBand extends StatelessWidget implements PreferredSizeWidget {
  const _FixedBand({required this.height});

  final double height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}

const _bandHeight = 92.0;
const _expectedClearance = _bandHeight + kNavBandGap;

Widget _shell(Widget page) => MaterialApp(
      home: Scaffold(
        extendBody: true,
        bottomNavigationBar: const _FixedBand(height: _bandHeight),
        body: page,
      ),
    );

// ── Marketplace fixtures ────────────────────────────────────────────────────

BusinessProfile _biz(int i) => BusinessProfile(
      id: 'biz$i',
      bizId: 'BIZ-biz$i',
      businessName: 'Business $i',
      category: 'RETAIL',
      isVerified: true,
      isSuspended: false,
      kybStatus: 'VERIFIED',
      totalEscrows: 3,
      completedEscrows: 3,
      userId: 1,
      totalVolume: 100,
      averageRating: 4.5,
      username: 'vendor-$i',
    );

/// Resolves the seeding search immediately with results.
class _ResultsSearchNotifier extends BusinessSearchNotifier {
  _ResultsSearchNotifier() : super(BusinessService());

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {
    state = state.copyWith(
      results: [for (var i = 0; i < 15; i++) _biz(i)],
      isLoading: false,
      hasMore: false,
      clearCursor: true,
    );
  }
}

/// Stays loading forever — drives the shimmer list.
class _LoadingSearchNotifier extends BusinessSearchNotifier {
  _LoadingSearchNotifier() : super(BusinessService());

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {
    state = state.copyWith(isLoading: true);
  }
}

// ── Friends fixtures ───────────────────────────────────────────────────────

class _FakeFriends extends FriendProvider {
  _FakeFriends(super.ref) {
    // The inbox body shows a spinner while loading — settle it
    // immediately, and seed friends so the inbox renders real rows
    // (the clearance sliver follows them).
    isLoading = false;
    friends = [
      for (var i = 0; i < 20; i++)
        {
          'friendshipId': 'f$i',
          'unreadCount': i % 3,
          'friend': {'id': 100 + i, 'username': 'friend$i'},
          'latestMessage': {
            'content': 'message $i',
            'createdAt': DateTime(2026, 10, 1)
                .add(Duration(minutes: i))
                .toIso8601String(),
          },
        },
    ];
  }

  @override
  Future<void> refreshAll() async {}
  @override
  Future<void> fetchFriends() async {}
  @override
  Future<void> fetchUnreadCount() async {}

  @override
  Future<void> searchUsers(String query) async {
    // Same shape the real service returns; synchronous so the test frame
    // after enterText already shows the results list.
    searchResults = [
      for (var i = 0; i < 15; i++)
        {'id': 100 + i, 'username': 'ama$i'},
    ];
    isLoading = false;
    notifyListeners();
  }
}

class _FakeFeed extends StoryFeedNotifier {
  _FakeFeed() {
    state = const AsyncValue.data([]);
  }

  @override
  Future<void> load() async {}
}

class _FakeGroups extends GroupListNotifier {
  _FakeGroups();

  @override
  Future<List<GroupSummary>> build() async => const [];
}

Future<void> _pumpFriends(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        friendProvider.overrideWith((ref) => _FakeFriends(ref)),
        storyFeedProvider.overrideWith((ref) => _FakeFeed()),
        groupListProvider.overrideWith(() => _FakeGroups()),
      ],
      child: _shell(const FriendsHubScreen()),
    ),
  );
  // One-shot child timers (rail entrance etc.) and the .animate()
  // entrance passes (staggered header fades) must fully elapse so no
  // timer is pending at teardown.
  await tester.pump(const Duration(milliseconds: 1500));
}

void main() {
  testWidgets(
    'marketplace results list pads with the live band clearance + gap',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            businessSearchProvider
                .overrideWith((ref) => _ResultsSearchNotifier()),
          ],
          child: _shell(const MarketplaceHomeScreen()),
        ),
      );
      // The seeding search fires from a post-frame callback; give it, the
      // staggered entrance (delay i*50ms + 300ms per bar) and the one-shot
      // child timers enough time to fully elapse so nothing is pending at
      // teardown.
      await tester.pumpAndSettle();

      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('marketplace_results_list')),
      );
      expect((list.padding as EdgeInsets).bottom, _expectedClearance);
    },
  );

  testWidgets(
    'marketplace results: last row ends the gap above the band when scrolled to the end',
    (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            businessSearchProvider
                .overrideWith((ref) => _ResultsSearchNotifier()),
          ],
          child: _shell(const MarketplaceHomeScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('marketplace_results_list')),
      );
      final position = list.controller!.position;
      position.jumpTo(position.maxScrollExtent);
      // Let the scroll-driven (100ms) collapse/opacity passes elapse.
      await tester.pumpAndSettle();

      final band = tester.getRect(find.byType(_FixedBand));
      final lastBar = tester.getRect(
        find.byType(CollapsibleBusinessBar).last,
      );

      // Reachability contract: after bottoming out, the last card's end
      // sits the full breathing gap above the band's top edge — never
      // behind it.
      expect(lastBar.bottom, lessThanOrEqualTo(band.top - kNavBandGap + 0.5));
    },
  );

  testWidgets(
    'marketplace shimmer pads with the live band clearance + gap (was hardcoded 60)',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            businessSearchProvider
                .overrideWith((ref) => _LoadingSearchNotifier()),
          ],
          child: _shell(const MarketplaceHomeScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('marketplace_shimmer_list')),
      );
      // The old hardcoded 60 sat the last skeleton rows behind a ~92px
      // band. The loading list must read the same live clearance.
      expect((list.padding as EdgeInsets).bottom, _expectedClearance);
    },
  );

  testWidgets(
    'friends inbox clearance sliver pads with the live band clearance + gap',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpFriends(tester);

      // skipOffstage: the clearance sliver sits after the last inbox
      // row, past the fold on the seeded list.
      final sliver = tester.widget<SliverPadding>(
        find.byKey(
          const ValueKey('inbox_nav_clearance_sliver'),
          skipOffstage: false,
        ),
      );
      expect((sliver.padding as EdgeInsets).bottom, _expectedClearance);
    },
  );

  testWidgets(
    'friends search results list pads with the live band clearance + gap',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpFriends(tester);

      // Open search and type — the fake resolves synchronously.
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'ama');
      await tester.pump(const Duration(milliseconds: 600));

      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('friends_search_results_list')),
      );
      expect((list.padding as EdgeInsets).bottom, _expectedClearance);
    },
  );
}
