import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/screens/friends/friend_chat_screen.dart';
import 'package:azaman/screens/group_chat/group_chat_screen.dart';
import 'package:hugeicons_pro/hugeicons.dart';


class FriendsHubScreen extends ConsumerStatefulWidget {
  const FriendsHubScreen({super.key});

  @override
  ConsumerState<FriendsHubScreen> createState() => _FriendsHubScreenState();
}

class _FriendsHubScreenState extends ConsumerState<FriendsHubScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(friendProvider).refreshAll();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    HapticFeedback.selectionClick();
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
    final maxHeight = MediaQuery.of(context).size.height * 0.72;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final provider = ref.watch(friendProvider);
            final bottomInset = MediaQuery.of(sheetContext).padding.bottom;
            return Container(
              constraints: BoxConstraints(maxHeight: maxHeight + bottomInset),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(18, 10, 18, bottomInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.textTertiary.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
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
                    Expanded(child: _buildRequestsSheetBody(colors, provider)),
                  ],
                ),
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textTertiary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colors.softSurface,
                    shape: BoxShape.circle,
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
                      counterStyle: TextStyle(color: colors.textTertiary, fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: () async {
                      final success = await ref.read(friendProvider).sendRequest(
                        user['id'],
                        messageController.text.trim(),
                      );
                      if (!ctx.mounted || !mounted) return;
                      Navigator.pop(ctx);
                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Friend request sent to ${user['username']}!'),
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
            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Inbox',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 27,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _openRequestsSheet,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: colors.softSurface,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            HugeIconsStroke.userGroup,
                            color: colors.textPrimary,
                            size: 20,
                          ),
                        ),
                        if (provider.pendingRequests.isNotEmpty)
                          Positioned(
                            top: -1,
                            right: -1,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: colors.danger,
                                shape: BoxShape.circle,
                                border: Border.all(color: colors.background, width: 1.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      _toggleSearch();
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _isSearching
                            ? colors.accent.withValues(alpha: 0.12)
                            : colors.softSurface,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        _isSearching ? HugeIconsSolid.cancel01 : HugeIconsStroke.userGroup,
                        color: _isSearching ? colors.accent : colors.textPrimary,
                        size: 20,
                      ),
                    ),
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
                      Icon(HugeIconsSolid.search01, color: colors.textTertiary, size: 18),
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
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
                  : _buildChatsTab(colors, provider),
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
            Icon(HugeIconsSolid.userSearch01, size: 44, color: colors.textTertiary),
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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.softSurface,
                  shape: BoxShape.circle,
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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

  Widget _buildChatsTab(AzamanColors colors, FriendProvider provider) {
    if (provider.isLoading && provider.friends.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: colors.accent, strokeWidth: 2),
      );
    }

    if (provider.friends.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                HugeIconsStroke.userGroup,
                color: colors.textPrimary,
                size: 116,
              ),
              const SizedBox(height: 28),
              Text(
                'Your inbox is empty',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Conversations will show up here.',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final groupsAsync = ref.watch(groupListProvider);
    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(friendProvider).fetchFriends();
        await ref.read(groupListProvider.notifier).refresh();
      },
      color: colors.accent,
      backgroundColor: colors.card,
      child: groupsAsync.when(
        loading: () => _buildFriendsList(provider.friends, colors),
        error: (_, __) => _buildFriendsList(provider.friends, colors),
        data: (groups) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            children: [
              if (groups.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
                  child: Text(
                    'GROUPS',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                for (final g in groups)
                  _GroupChatTile(group: g, colors: colors),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'FRIENDS',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
              for (final f in provider.friends)
                _buildFriendTile(f, colors),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFriendsList(List<Map<String, dynamic>> friends, AzamanColors colors) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      itemCount: friends.length,
      itemBuilder: (context, index) => _buildFriendTile(friends[index], colors),
    );
  }

  Widget _buildFriendTile(Map<String, dynamic> friend, AzamanColors colors) {
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
    final currentUsername = ref.watch(authProvider).user?.username ?? '';
    final bool isMentioned = currentUsername.isNotEmpty &&
        lastMessage.contains('@$currentUsername');
    final friendshipId = friend['friendshipId']?.toString() ??
        friend['id']?.toString() ??
        '';
    final friendIdRaw =
        friendObj['id'] ?? friend['friendId'] ?? friend['userId'] ?? 0;
    final friendId = friendIdRaw is int
        ? friendIdRaw
        : int.tryParse(friendIdRaw.toString()) ?? 0;

    final completedTransactions =
        (friendObj['completedTransactions'] ?? 0) is int
            ? friendObj['completedTransactions'] as int
            : int.tryParse('${friendObj['completedTransactions']}') ?? 0;
    final ratingRaw = friendObj['rating'];
    final rating = ratingRaw is num ? ratingRaw.toDouble() : null;
    final isVerifiedVendor = friendObj['isVerifiedVendor'] == true;
    final bool hasUnread = unread > 0;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
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
          ref.read(friendProvider).fetchFriends();
          ref.read(friendProvider).fetchUnreadCount();
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hasUnread
              ? colors.accent.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.softSurface,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : '?',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),
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
                            fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (isVerifiedVendor) ...[
                        const SizedBox(width: 4),
                        Icon(HugeIconsSolid.checkmarkCircle01,
                            color: colors.accent, size: 13),
                      ],
                    ],
                  ),
                  if (rating != null || completedTransactions > 0) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (rating != null) ...[
                          Icon(HugeIconsSolid.star, color: colors.warning, size: 11),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastMessage.isNotEmpty ? lastMessage : 'Start chatting...',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hasUnread ? colors.textSecondary : colors.textTertiary,
                            fontSize: 13,
                            fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isMentioned ? colors.warning : colors.accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isMentioned) ...[
                                Text(
                                  '@',
                                  style: TextStyle(
                                    color: colors.isDark ? Colors.black : Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 2),
                              ],
                              Text(
                                unread > 99 ? '99+' : '$unread',
                                style: TextStyle(
                                  color: colors.isDark ? Colors.black : Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  lastTime,
                  style: TextStyle(
                    color: hasUnread ? colors.accent : colors.textTertiary,
                    fontSize: 12,
                    fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsSheetBody(AzamanColors colors, FriendProvider provider) {
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
            Icon(HugeIconsStroke.userGroup, size: 44, color: colors.textTertiary),
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

    return RefreshIndicator(
      onRefresh: () => ref.read(friendProvider).fetchPendingRequests(),
      color: colors.accent,
      backgroundColor: colors.card,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
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

  Widget _buildRequestSheetTile(Map<String, dynamic> request, AzamanColors colors) {
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
                  shape: BoxShape.circle,
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
                      border: Border.all(
                        color: colors.divider,
                        width: 1,
                      ),
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

class _GroupChatTile extends StatelessWidget {
  final GroupSummary group;
  final AzamanColors colors;
  const _GroupChatTile({required this.group, required this.colors});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupChatScreen(groupId: group.id),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
        ),
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
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (group.isSusuEnabled) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'SUSU',
                            style: TextStyle(
                              color: colors.warning,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
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
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(HugeIconsSolid.arrowRight01, color: colors.textTertiary, size: 16),
          ],
        ),
      ),
    );
  }
}

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
      width: 48,
      height: 48,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 8,
            child: _bubble(char: firstChar, size: 28, color: colors.accent, fontSize: 11),
          ),
          Positioned(
            bottom: 2,
            left: 0,
            child: _bubble(char: secondChar, size: 24, color: colors.accentSecondary, fontSize: 10),
          ),
          Positioned(
            bottom: 0,
            right: 2,
            child: _bubble(char: thirdChar, size: 24, color: colors.success, fontSize: 10),
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
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: colors.background, width: 1.5),
      ),
      child: Text(
        char,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
