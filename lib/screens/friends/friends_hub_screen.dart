// =============================================================================
// AZAMAN V3 — FRIENDS HUB SCREEN
//
// Main friends screen with Chats/Requests tabs, user search overlay,
// and friend request dialog. Entry point for the social friends system.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/screens/friends/friend_chat_screen.dart';
import 'package:azaman/screens/group_chat/group_chat_screen.dart';

class FriendsHubScreen extends ConsumerStatefulWidget {
  const FriendsHubScreen({super.key});

  @override
  ConsumerState<FriendsHubScreen> createState() => _FriendsHubScreenState();
}

class _FriendsHubScreenState extends ConsumerState<FriendsHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Load data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(friendProvider).refreshAll();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
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

  void _showAddFriendDialog(Map<String, dynamic> user) {
    final colors = ref.read(themeProvider).colors;
    final messageController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // User info
              CircleAvatar(
                radius: 30,
                backgroundColor: colors.accent.withOpacity(0.2),
                child: Text(
                  (user['username'] ?? '?')[0].toUpperCase(),
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                user['username'] ?? 'Unknown',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'ID: ${user['id']}',
                style: TextStyle(color: colors.textTertiary, fontSize: 13),
              ),
              const SizedBox(height: 20),

              // Message field
              TextField(
                controller: messageController,
                style: TextStyle(color: colors.textPrimary),
                maxLength: 200,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Say something... (optional)',
                  hintStyle: TextStyle(color: colors.textTertiary),
                  filled: true,
                  fillColor: colors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  counterStyle: TextStyle(color: colors.textTertiary),
                ),
              ),
              const SizedBox(height: 16),

              // Send button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final success = await ref.read(friendProvider).sendRequest(
                      user['id'],
                      messageController.text.trim(),
                    );
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Friend request sent to ${user['username']}!'),
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor:
                        colors.isDark ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Send Friend Request',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      // Phase H10 BUGFIX (2026-05-27): the message controller was
      // allocated outside the builder but never disposed. Each open
      // of this sheet leaked one TextEditingController. .whenComplete
      // fires whether the sheet was confirmed or dismissed.
      messageController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final provider = ref.watch(friendProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search users...',
                  hintStyle: TextStyle(color: colors.textTertiary),
                  border: InputBorder.none,
                ),
                onChanged: _onSearchChanged,
              )
            : Text(
                'Friends',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search_rounded,
              color: colors.textPrimary,
            ),
            onPressed: _toggleSearch,
          ),
        ],
        bottom: _isSearching
            ? null
            : TabBar(
                controller: _tabController,
                indicatorColor: colors.accent,
                labelColor: colors.accent,
                unselectedLabelColor: colors.textTertiary,
                tabs: [
                  const Tab(text: 'Chats'),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Requests'),
                        if (provider.pendingRequests.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colors.danger,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${provider.pendingRequests.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
      body: _isSearching
          ? _buildSearchResults(colors, provider)
          : TabBarView(
              controller: _tabController,
              children: [
                _buildChatsTab(colors, provider),
                _buildRequestsTab(colors, provider),
              ],
            ),
    );
  }

  // ===========================================================================
  // SEARCH RESULTS OVERLAY
  // ===========================================================================

  Widget _buildSearchResults(AzamanColors colors, FriendProvider provider) {
    if (provider.isLoading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }

    if (_searchController.text.length < 2) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search_rounded,
                size: 48, color: colors.textTertiary),
            const SizedBox(height: 12),
            Text(
              'Search by username or ID',
              style: TextStyle(color: colors.textSecondary, fontSize: 15),
            ),
            Text(
              'Type at least 2 characters',
              style: TextStyle(color: colors.textTertiary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (provider.searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded,
                size: 48, color: colors.textTertiary),
            const SizedBox(height: 12),
            Text(
              'No users found',
              style: TextStyle(color: colors.textSecondary, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: provider.searchResults.length,
      itemBuilder: (context, index) {
        final user = provider.searchResults[index];
        final requestSent = user['requestSent'] == true;
        final isFriend = user['isFriend'] == true;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: colors.accent.withOpacity(0.2),
              child: Text(
                (user['username'] ?? '?')[0].toUpperCase(),
                style: TextStyle(
                  color: colors.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              user['username'] ?? 'Unknown',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'ID: ${user['id']}',
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
            trailing: isFriend
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Friends',
                      style: TextStyle(
                          color: colors.success,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  )
                : requestSent
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.textTertiary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Sent',
                          style: TextStyle(
                              color: colors.textTertiary, fontSize: 12),
                        ),
                      )
                    : TextButton(
                        onPressed: () => _showAddFriendDialog(user),
                        style: TextButton.styleFrom(
                          backgroundColor: colors.accent.withOpacity(0.1),
                          foregroundColor: colors.accent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Add',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // CHATS TAB
  // ===========================================================================

  Widget _buildChatsTab(AzamanColors colors, FriendProvider provider) {
    if (provider.isLoading && provider.friends.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }

    if (provider.friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline_rounded,
                size: 56, color: colors.textTertiary),
            const SizedBox(height: 16),
            Text(
              'No friends yet',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Search for users and add them as friends',
              style: TextStyle(color: colors.textTertiary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _toggleSearch,
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text('Find Friends'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.isDark ? Colors.black : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Master Sprint v2 (2026-05-27): the Chats tab now includes group
    // chats above the 1:1 list. Susu-enabled groups carry a SUSU pill
    // and the row links straight into the group chat (the susu dashboard
    // is reachable from the chat header). Casual groups appear without
    // the pill.
    final groupsAsync = ref.watch(groupListProvider);
    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(friendProvider).fetchFriends();
        await ref.read(groupListProvider.notifier).refresh();
      },
      color: colors.accent,
      child: groupsAsync.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: provider.friends.length,
          itemBuilder: (context, index) =>
              _buildFriendTile(provider.friends[index], colors),
        ),
        error: (_, __) => ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: provider.friends.length,
          itemBuilder: (context, index) =>
              _buildFriendTile(provider.friends[index], colors),
        ),
        data: (groups) {
          final children = <Widget>[];
          if (groups.isNotEmpty) {
            children.add(Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                'GROUPS',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ));
            for (final g in groups) {
              children.add(_GroupChatTile(group: g, colors: colors));
            }
            children.add(Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                'FRIENDS',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ));
          }
          for (final f in provider.friends) {
            children.add(_buildFriendTile(f, colors));
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: children,
          );
        },
      ),
    );
  }

  Widget _buildFriendTile(Map<String, dynamic> friend, AzamanColors colors) {
    // Phase UI-7 (2026-05-27): the BE returns the friend list with a
    // nested shape — `{ friendshipId, friend: {...}, latestMessage: {...},
    // unreadCount, friendSince }`. The previous tile read `friend['username']`
    // / `friend['lastMessage']` as flat keys, which silently fell through to
    // "Unknown" / "" because those keys never existed at the top level. We
    // now read from the nested objects, with the legacy flat keys retained
    // as fallback so any older socket payload that still arrives flat
    // (rare — friend_provider's transfer-received handler) still renders.
    final friendObj = friend['friend'] is Map<String, dynamic>
        ? friend['friend'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final latestMessage = friend['latestMessage'] is Map<String, dynamic>
        ? friend['latestMessage'] as Map<String, dynamic>
        : null;

    final username = (friendObj['username'] ??
            friend['username'] ??
            friend['friendUsername'] ??
            'Unknown')
        .toString();
    final lastMessage = (latestMessage?['content'] ?? friend['lastMessage'] ?? '')
        .toString();
    final lastTime = _formatRelativeTime(
        latestMessage?['createdAt'] ?? friend['lastMessageTime']);
    final unread = (friend['unreadCount'] ?? 0) is int
        ? friend['unreadCount'] as int
        : int.tryParse('${friend['unreadCount']}') ?? 0;
    final friendshipId = friend['friendshipId']?.toString() ??
        friend['id']?.toString() ??
        '';
    final friendIdRaw =
        friendObj['id'] ?? friend['friendId'] ?? friend['userId'] ?? 0;
    final friendId = friendIdRaw is int
        ? friendIdRaw
        : int.tryParse(friendIdRaw.toString()) ?? 0;

    // Phase UI-7: trust signals from the BE (defensive fallback to 0/null
    // so older deploys without the new fields still render the row).
    final completedTransactions =
        (friendObj['completedTransactions'] ?? 0) is int
            ? friendObj['completedTransactions'] as int
            : int.tryParse('${friendObj['completedTransactions']}') ?? 0;
    final ratingRaw = friendObj['rating'];
    final rating = ratingRaw is num ? ratingRaw.toDouble() : null;
    final isVerifiedVendor = friendObj['isVerifiedVendor'] == true;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FriendChatScreen(
              friendshipId: friendshipId,
              friendUsername: username,
              friendId: friendId,
            ),
          ),
        ).then((_) {
          // Refresh when coming back
          ref.read(friendProvider).fetchFriends();
          ref.read(friendProvider).fetchUnreadCount();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            // Profile pic placeholder
            CircleAvatar(
              radius: 24,
              backgroundColor: colors.accent.withOpacity(0.15),
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : '?',
                style: TextStyle(
                  color: colors.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Username + trust line + last message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: unread > 0
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (isVerifiedVendor) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified_rounded,
                            color: colors.accent, size: 13),
                      ],
                    ],
                  ),
                  // Phase UI-7: persistent trust line under the name —
                  // ⭐ rating · N Completed Transactions. Suppressed
                  // entirely when the friend has no signal yet (no
                  // rating + zero completed) so brand-new accounts
                  // don't carry a misleading "0 Completed" stamp.
                  if (rating != null || completedTransactions > 0) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (rating != null) ...[
                          Icon(Icons.star_rounded,
                              color: colors.warning, size: 11),
                          const SizedBox(width: 2),
                          Text(
                            rating.toStringAsFixed(1),
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            width: 2,
                            height: 2,
                            decoration: BoxDecoration(
                              color: colors.textTertiary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(
                            '$completedTransactions completed',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textTertiary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    lastMessage.isNotEmpty ? lastMessage : 'Start chatting...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: unread > 0
                          ? colors.textSecondary
                          : colors.textTertiary,
                      fontSize: 13,
                      fontWeight:
                          unread > 0 ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),

            // Time + unread badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  lastTime,
                  style: TextStyle(
                    color: unread > 0 ? colors.accent : colors.textTertiary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                if (unread > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: TextStyle(
                        color: colors.isDark ? Colors.black : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // REQUESTS TAB
  // ===========================================================================

  Widget _buildRequestsTab(AzamanColors colors, FriendProvider provider) {
    if (provider.isLoading && provider.pendingRequests.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }

    if (provider.pendingRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add_disabled_rounded,
                size: 48, color: colors.textTertiary),
            const SizedBox(height: 12),
            Text(
              'No pending requests',
              style: TextStyle(color: colors.textSecondary, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(friendProvider).fetchPendingRequests(),
      color: colors.accent,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: provider.pendingRequests.length,
        itemBuilder: (context, index) {
          final request = provider.pendingRequests[index];
          return _buildRequestTile(request, colors);
        },
      ),
    );
  }

  Widget _buildRequestTile(
      Map<String, dynamic> request, AzamanColors colors) {
    final requester = request['requester'] ?? request['sender'] ?? {};
    final username = requester['username'] ?? request['username'] ?? 'Unknown';
    final message = request['message'] ?? '';
    final id = request['id']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: colors.accentSecondary.withOpacity(0.2),
                child: Text(
                  username.isNotEmpty ? username[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: colors.accentSecondary,
                    fontWeight: FontWeight.bold,
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
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (requester['id'] != null)
                      Text(
                        'ID: ${requester['id']}',
                        style: TextStyle(
                            color: colors.textTertiary, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),

          // Message
          if (message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '"$message"',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Accept / Reject buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => ref.read(friendProvider).acceptRequest(id),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Accept',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => ref.read(friendProvider).rejectRequest(id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.danger,
                    side: BorderSide(color: colors.danger.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Reject',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _formatRelativeTime(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp.toString()).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) return 'now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      if (diff.inHours < 24) return '${diff.inHours}h';
      if (diff.inDays < 7) return '${diff.inDays}d';
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }
}


// =============================================================================
// GROUP CHAT TILE — Master Sprint v2 (2026-05-27)
//
// Renders a row in the Chats tab for a GroupSummary. The avatar is a
// composite of three overlapping circles drawn via _GroupBubbleAvatar so
// the row is instantly recognisable as a group thread vs a 1:1 friend.
//
// Susu-enabled groups show a SUSU pill next to the title; casual groups
// show no pill. Tapping the row opens the group chat screen.
// =============================================================================
class _GroupChatTile extends StatelessWidget {
  final GroupSummary group;
  final AzamanColors colors;
  const _GroupChatTile({required this.group, required this.colors});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupChatScreen(groupId: group.id),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            _GroupBubbleAvatar(group: group, colors: colors),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (group.isSusuEnabled) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              colors.warning,
                              colors.warning.withOpacity(0.7),
                            ]),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'SUSU',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${group.members.length} members',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.textTertiary, size: 16),
          ],
        ),
      ),
    );
  }
}

/// Composite group avatar — three overlapping circles. Top-left bubble
/// gets the first member's initial, bottom-right gets the second, and
/// the back bubble carries the group's first letter so the cluster is
/// instantly recognisable as "a group" without rendering 5+ stacked
/// avatars (which would look cluttered at this row size).
class _GroupBubbleAvatar extends StatelessWidget {
  final GroupSummary group;
  final AzamanColors colors;
  const _GroupBubbleAvatar({required this.group, required this.colors});

  @override
  Widget build(BuildContext context) {
    final members = group.members;
    final firstChar = group.name.isEmpty ? '?' : group.name[0].toUpperCase();
    final secondChar = members.isNotEmpty
        ? (members.first.username ?? '?').substring(0, 1).toUpperCase()
        : '?';
    final thirdChar = members.length > 1
        ? (members[1].username ?? '?').substring(0, 1).toUpperCase()
        : '+';
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        children: [
          // Back bubble (group identity)
          Positioned(
            top: 0,
            left: 8,
            child: _bubble(
              char: firstChar,
              size: 26,
              color: colors.accent,
              fontSize: 11,
            ),
          ),
          // Front-left bubble (first member)
          Positioned(
            bottom: 2,
            left: 0,
            child: _bubble(
              char: secondChar,
              size: 22,
              color: colors.accentSecondary,
              fontSize: 10,
            ),
          ),
          // Front-right bubble (second member or +)
          Positioned(
            bottom: 0,
            right: 0,
            child: _bubble(
              char: thirdChar,
              size: 22,
              color: colors.success,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble({
    required String char,
    required double size,
    required Color color,
    required double fontSize,
  }) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.40), color.withOpacity(0.15)],
        ),
        border: Border.all(color: colors.background, width: 1.5),
      ),
      child: Text(
        char,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
