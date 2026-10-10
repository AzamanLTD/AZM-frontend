import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/screens/friends/friend_chat_screen.dart';
import 'package:azaman/screens/group_chat/group_chat_screen.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/screens/contacts_screen.dart';
import 'package:azaman/screens/story_viewer_screen.dart';
import 'package:azaman/widgets/chat_unread_badge.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:azaman/widgets/scale_tap.dart';
import 'package:azaman/widgets/nav_transitions.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';
import 'package:azaman/widgets/azaman_sheet.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/widgets/inbox/inbox_entry.dart';
import 'package:azaman/widgets/inbox/inbox_row.dart';
import 'package:azaman/widgets/stories/inbox_story_rail_sliver.dart';
import 'package:azaman/widgets/stories/story_rail_compact.dart';
import 'package:azaman/widgets/stories/story_rail_strip.dart'
    show StoryRailMetrics;
import 'package:azaman/widgets/stories/story_rail_snap_physics.dart';

class FriendsHubScreen extends ConsumerStatefulWidget {
  const FriendsHubScreen({super.key});

  @override
  ConsumerState<FriendsHubScreen> createState() => _FriendsHubScreenState();
}

class _FriendsHubScreenState extends ConsumerState<FriendsHubScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  /// One scroll owner for rail + rows (Overhaul 04 §2).
  ///
  /// UX pass C: the rail is OPEN BY DEFAULT. The rail is a fixed-extent
  /// sliver before the center, so its open detent is the compile-time
  /// `-StoryRailMetrics.height` — starting the position THERE (instead of
  /// post-frame jumping to `minScrollExtent`) means the FIRST painted
  /// frame already shows the open rail: no visible initial-position jump.
  final ScrollController _inboxScroll = ScrollController(
    initialScrollOffset: -StoryRailMetrics.height,
  );
  static const _centerKey = ValueKey('inbox_center');

  /// Flips on open/closed transitions only (never per frame) so the compact
  /// strip's live region announces "Stories shown/hidden" exactly once.
  /// Starts OPEN — the rail's default state (UX pass C).
  final ValueNotifier<bool> _railOpenNotifier = ValueNotifier<bool>(true);

  @override
  void initState() {
    super.initState();
    _inboxScroll.addListener(_onInboxScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(friendProvider).refreshAll();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _inboxScroll.removeListener(_onInboxScroll);
    _inboxScroll.dispose();
    _railOpenNotifier.dispose();
    super.dispose();
  }

  bool get _railOpen {
    if (!_inboxScroll.hasClients) return false;
    final pos = _inboxScroll.position;
    if (!pos.hasContentDimensions || !pos.hasPixels) return false;
    return pos.minScrollExtent < 0 && pos.pixels <= pos.minScrollExtent + 0.5;
  }

  void _onInboxScroll() {
    final open = _railOpen;
    if (open != _railOpenNotifier.value) _railOpenNotifier.value = open;
  }

  void _openRail() {
    if (!_inboxScroll.hasClients) return;
    final pos = _inboxScroll.position;
    if (!pos.hasContentDimensions) return;
    final target = pos.minScrollExtent;
    if (target >= 0) return;
    if (!AzMotion.of(context).travel) {
      _inboxScroll.jumpTo(target);
      return;
    }
    _inboxScroll.animateTo(
      target,
      duration: MotionTokens.emphasized,
      curve: MotionTokens.enter,
    );
  }

  void _closeRail() {
    if (!_inboxScroll.hasClients) return;
    if (!AzMotion.of(context).travel) {
      _inboxScroll.jumpTo(0);
      return;
    }
    _inboxScroll.animateTo(
      0,
      duration: MotionTokens.standard,
      curve: MotionTokens.exit,
    );
  }

  void _toggleSearch() {
    HapticFeedback.selectionClick();
    if (!_isSearching && _railOpen) _closeRail();
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        ref.read(friendProvider).clearSearch();
      }
    });
  }

  void _onSearchChanged(String query) {
    ref.read(friendProvider).searchUsers(query);
  }

  Future<void> _pickAndCreateStory() async {
    // NEW-A: the whole camera → editor → creation chain now lives in the
    // router (/story-camera owns it); this screen just enters the flow.
    context.push(AzRoutes.storyCamera);
  }

  Future<void> _openRequestsSheet() async {
    HapticFeedback.selectionClick();
    if (_isSearching) {
      setState(() {
        _isSearching = false;
        _searchController.clear();
      });
      ref.read(friendProvider).clearSearch();
    }

    await ref.read(friendProvider).fetchPendingRequests();
    if (!mounted) return;

    final colors = ref.read(themeProvider).colors;

    // NEW-B: Panel weight. The request list is unbounded — a user can have any
    // number of pending requests — and the old code faked a maxHeight of 0.72
    // rather than using a detent. The Panel supplies that, and the list scrolls
    // through the sheet's own controller.
    await AzamanSheet.showPanel<void>(
      context,
      builder: (sheetContext, scrollController) {
        return Consumer(
          builder: (context, ref, _) {
            final provider = ref.watch(friendProvider);
            final bottomInset = MediaQuery.of(sheetContext).padding.bottom;
            // NEW-B: the weight owns surface, radius, safe-area and the
            // handle, so the old Container + handle bar are deleted.
            return Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Requests',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (provider.pendingRequests.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colors.softSurface,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${provider.pendingRequests.length}',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(sheetContext),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: colors.softSurface,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            HugeIconsSolid.cancel01,
                            color: colors.textPrimary,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _buildRequestsSheetBody(
                      colors,
                      provider,
                      scrollController,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddFriendDialog(Map<String, dynamic> user) {
    final colors = ref.read(themeProvider).colors;
    final messageController = TextEditingController();

    // NEW-B: Panel weight. A keyboard-bound form with a free-text message —
    // unbounded height, and a Send commit that must survive the keyboard
    // opening. The weight owns surface, radius, safe-area and the handle.
    AzamanSheet.showPanel<void>(
      context,
      builder: (ctx, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colors.softSurface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    (user['username'] ?? '?')[0].toUpperCase(),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  user['username'] ?? 'Unknown',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'ID: ${user['id']}',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: colors.softSurface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: messageController,
                    maxLength: 200,
                    maxLines: 3,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Say something... (optional)',
                      hintStyle: TextStyle(
                        color: colors.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                      contentPadding: const EdgeInsets.all(14),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      counterStyle: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: () async {
                      final success = await ref
                          .read(friendProvider)
                          .sendRequest(
                            user['id'],
                            messageController.text.trim(),
                          );
                      if (!ctx.mounted || !mounted) return;
                      Navigator.pop(ctx);
                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Friend request sent to ${user['username']}!',
                            ),
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Send Friend Request',
                        style: TextStyle(
                          color: colors.isDark ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      messageController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final provider = ref.watch(friendProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child:
                        Text(
                              'Inbox',
                              key: const ValueKey('inbox_title'),
                              style: AzText.titleXl.copyWith(
                                color: colors.textPrimary,
                              ),
                            )
                            .animate()
                            .fadeIn(duration: 300.ms)
                            .slideY(begin: 0.1, end: 0),
                  ),
                  ScaleTap(
                        onTap: () => pushWithVerticalTransition(
                          context,
                          const ContactsScreen(),
                        ),
                        child: Container(
                          width: 42,
                          height: 42,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: colors.softSurface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.textTertiary.withValues(
                                alpha: 0.08,
                              ),
                              width: 0.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.contacts_rounded,
                            color: colors.textPrimary,
                            size: 18,
                          ),
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 60.ms, duration: 300.ms)
                      .scale(
                        begin: const Offset(0.8, 0.8),
                        end: const Offset(1, 1),
                      ),
                  ScaleTap(
                        onTap: _openRequestsSheet,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: colors.softSurface,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colors.textTertiary.withValues(
                                    alpha: 0.08,
                                  ),
                                  width: 0.5,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.person_add_rounded,
                                color: colors.textPrimary,
                                size: 20,
                              ),
                            ),
                            if (provider.pendingRequests.isNotEmpty)
                              Positioned(
                                top: -2,
                                right: -2,
                                child: ChatUnreadBadge(
                                  count: provider.pendingRequests.length,
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 120.ms, duration: 300.ms)
                      .scale(
                        begin: const Offset(0.8, 0.8),
                        end: const Offset(1, 1),
                      ),
                  const SizedBox(width: 8),
                  ScaleTap(
                        onTap: _toggleSearch,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: _isSearching
                                ? colors.accent.withValues(alpha: 0.12)
                                : colors.softSurface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _isSearching
                                  ? colors.accent.withValues(alpha: 0.2)
                                  : colors.textTertiary.withValues(alpha: 0.08),
                              width: 0.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            _isSearching
                                ? HugeIconsSolid.cancel01
                                : Icons.search_rounded,
                            color: _isSearching
                                ? colors.accent
                                : colors.textPrimary,
                            size: 20,
                          ),
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 180.ms, duration: 300.ms)
                      .scale(
                        begin: const Offset(0.8, 0.8),
                        end: const Offset(1, 1),
                      ),
                ],
              ),
            ),

            if (_isSearching) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.softSurface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(
                        HugeIconsSolid.search01,
                        color: colors.textTertiary,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          onChanged: _onSearchChanged,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search by username or ID',
                            hintStyle: TextStyle(
                              color: colors.textTertiary,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 8),

            Expanded(
              child: _isSearching
                  ? _buildSearchResults(colors, provider)
                  : _buildInbox(colors, provider),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(AzamanColors colors, FriendProvider provider) {
    if (provider.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colors.accent, strokeWidth: 2),
      );
    }

    if (_searchController.text.length < 2) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              HugeIconsSolid.userSearch01,
              size: 44,
              color: colors.textTertiary,
            ),
            const SizedBox(height: 14),
            Text(
              'Search by username or ID',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Type at least 2 characters',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (provider.searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HugeIconsSolid.search01, size: 44, color: colors.textTertiary),
            const SizedBox(height: 14),
            Text(
              'No users found',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      itemCount: provider.searchResults.length,
      itemBuilder: (context, index) {
        final user = provider.searchResults[index];
        final requestSent = user['requestSent'] == true;
        final isFriend = user['isFriend'] == true;

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.softSurface,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  (user['username'] ?? '?')[0].toUpperCase(),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user['username'] ?? 'Unknown',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'ID: ${user['id']}',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (isFriend)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Friends',
                    style: TextStyle(
                      color: colors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (requestSent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.softSurface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Sent',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap: () => _showAddFriendDialog(user),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Add',
                      style: TextStyle(
                        color: colors.isDark ? Colors.black : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Inbox (Overhaul 04 · UX pass C) ──────────────────────────────────
  // The chat list is the only vertical scroll owner. The story rail is a
  // sliver *before* the center, so it lives at negative offsets — and the
  // hub STARTS at the open detent: the rail is open by default on entry.
  // Scrolling into the message list collapses it into the compact strip
  // (snap physics: deliberate band resistance, casual flicks spring back);
  // returning to the top stops at CLOSED (offset 0) — no automatic reopen.

  Widget _buildInbox(AzamanColors colors, FriendProvider provider) {
    final travel = AzMotion.of(context).travel;
    final groupsAsync = ref.watch(groupListProvider);
    final groups = groupsAsync.valueOrNull ?? const <GroupSummary>[];

    if (provider.isLoading &&
        provider.friends.isEmpty &&
        (groupsAsync.isLoading || groups.isEmpty)) {
      return Center(
        child: CircularProgressIndicator(color: colors.accent, strokeWidth: 2),
      );
    }

    final entries = _entries(provider, groups);

    return CustomScrollView(
      key: const ValueKey('inbox_scroll'),
      controller: _inboxScroll,
      center: _centerKey,
      physics: StoryRailSnapPhysics(
        travel: travel,
        parent: const AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        // Before center → negative offsets → the OPEN detent sits at
        // minScrollExtent, where the controller starts (UX pass C).
        InboxStoryRailSliver(
          controller: _inboxScroll,
          onOpenGroup: (groups, i) => StoryViewerScreen.open(
            context,
            groups: groups,
            initialGroupIndex: i,
          ),
          onCreate: _pickAndCreateStory,
        ),
        // Center → offset 0 at the top of the viewport.
        SliverMainAxisGroup(
          key: _centerKey,
          slivers: [
            SliverToBoxAdapter(
              // CORRECTION J: the compact strip is the story rail's
              // COLLAPSED presentation — as the rail reveals, the strip
              // collapses away, so the open rail is never duplicated by
              // a smaller strip underneath.
              child: StoryRailCompact(
                onTap: _openRail,
                railOpen: _railOpenNotifier,
                reveal: _inboxScroll,
              ),
            ),
            if (entries.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _emptyInbox(colors),
              )
            else
              SliverList.separated(
                itemCount: entries.length,
                separatorBuilder: (_, __) => _softRule(colors),
                itemBuilder: (context, i) {
                  final e = entries[i];
                  return InboxRow(
                    entry: e,
                    onTap: () => _openEntry(e),
                    // Row actions arrive with 07 (G1); no affordance until then.
                    onLongPress: null,
                  );
                },
              ),
            const SliverPadding(padding: AzSpace.navClearance),
          ],
        ),
      ],
    );
  }

  /// Friends (typed via [InboxEntry.fromFriend]) and groups in one list,
  /// pinned first then most-recent activity — the same ordering the old
  /// `_ChatListEntry` produced.
  List<InboxEntry> _entries(
    FriendProvider provider,
    List<GroupSummary> groups,
  ) {
    final currentUsername = ref.read(authProvider).user?.username ?? '';
    final list = <InboxEntry>[
      for (final f in provider.friends)
        InboxEntry.fromFriend(f, currentUsername: currentUsername),
      for (final g in groups) InboxEntry.fromGroup(g),
    ]..sort(InboxEntry.compare);
    return list;
  }

  void _openEntry(InboxEntry e) {
    HapticFeedback.selectionClick();
    if (e.kind == InboxKind.group) {
      pushWithVerticalTransition(context, GroupChatScreen(groupId: e.id));
      return;
    }
    pushWithVerticalTransition(
      context,
      FriendChatScreen(
        friendshipId: e.id,
        friendUsername: e.title,
        friendId: e.friendId ?? 0,
      ),
    ).then((_) {
      if (!mounted) return;
      ref.read(friendProvider).fetchFriends();
      ref.read(friendProvider).fetchUnreadCount();
    });
  }

  /// The soft 1px band between rows (a flat divider read as a hard rule).
  Widget _softRule(AzamanColors colors) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(horizontal: 2),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: colors.isDark ? 0.35 : 0.07),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ),
    ),
  );

  Widget _emptyInbox(AzamanColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PremiumGlassContainer(
                  blur: 20,
                  opacity: 0.05,
                  borderRadius: 60,
                  padding: const EdgeInsets.all(28),
                  child: Icon(
                    HugeIconsStroke.userGroup,
                    color: colors.accent,
                    size: 56,
                  ),
                )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.05, 1.05),
                  duration: 2000.ms,
                  curve: Curves.easeInOut,
                ),
            const SizedBox(height: 28),
            Text(
              'Your inbox is empty',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                letterSpacing: -0.4,
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
            const SizedBox(height: 10),
            Text(
              'Add friends by their Azaman ID to start chatting.',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
            const SizedBox(height: 24),
            GestureDetector(
                  onTap: () => pushWithVerticalTransition(
                    context,
                    const ContactsScreen(),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      'Find Friends',
                      style: TextStyle(
                        color: colors.isDark ? Colors.black : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .animate()
                .fadeIn(delay: 400.ms, duration: 400.ms)
                .slideY(begin: 0.1, end: 0),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsSheetBody(
    AzamanColors colors,
    FriendProvider provider,
    ScrollController scrollController,
  ) {
    if (provider.isLoading && provider.pendingRequests.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: colors.accent, strokeWidth: 2),
      );
    }

    if (provider.pendingRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              HugeIconsStroke.userGroup,
              size: 44,
              color: colors.textTertiary,
            ),
            const SizedBox(height: 14),
            Text(
              'No requests',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return AzPullToRefresh(
      onRefresh: () => ref.read(friendProvider).fetchPendingRequests(),
      color: colors.accent,
      backgroundColor: colors.card,
      child: ListView.separated(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 28),
        itemCount: provider.pendingRequests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final request = provider.pendingRequests[index];
          return _buildRequestSheetTile(request, colors);
        },
      ),
    );
  }

  Widget _buildRequestSheetTile(
    Map<String, dynamic> request,
    AzamanColors colors,
  ) {
    final requester = request['requester'] ?? request['sender'] ?? {};
    final username = requester['username'] ?? request['username'] ?? 'Unknown';
    final message = request['message'] ?? '';
    final id = request['id']?.toString() ?? '';
    final time = _formatRelativeTime(
      request['createdAt'] ?? request['updatedAt'] ?? request['sentAt'],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: colors.softSurface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(15),
                ),
                alignment: Alignment.center,
                child: Text(
                  username.isNotEmpty ? username[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message.toString().trim().isNotEmpty
                          ? message.toString().trim()
                          : 'Wants to connect',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (time.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    time,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    await ref.read(friendProvider).acceptRequest(id);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Accept',
                      style: TextStyle(
                        color: colors.isDark ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    await ref.read(friendProvider).rejectRequest(id);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colors.divider, width: 1),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Decline',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(dynamic timestamp) {
    if (timestamp == null) return '';
    final dt = timestamp is DateTime
        ? timestamp
        : DateTime.tryParse(timestamp.toString());
    return InboxEntry.relativeTime(dt);
  }
}
