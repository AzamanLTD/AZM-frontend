// =============================================================================
// AZAMAN V3 — FRIEND PROVIDER
//
// Riverpod ChangeNotifier for the Social Friends System.
// Manages friend list, pending requests, search, and socket events.
//
// Usage:
//   final friends = ref.watch(friendProvider);
//   ref.read(friendProvider).fetchFriends();
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'package:azaman/config.dart';
import 'package:azaman/services/friend_service.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/providers/auth_provider.dart';

class FriendProvider with ChangeNotifier {
  final Ref _ref;
  final FriendService _service = FriendService();

  // ── State ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> friends = [];
  List<Map<String, dynamic>> pendingRequests = [];
  List<Map<String, dynamic>> searchResults = [];
  int unreadMessageCount = 0;
  bool isLoading = false;
  String? error;

  // ── Socket ────────────────────────────────────────────────────────────────
  IO.Socket? _socket;
  bool _socketInitialized = false;

  FriendProvider(this._ref) {
    _initSocket();
  }

  String? get _token => _ref.read(authProvider).user?.token;
  String? get _userId => _ref.read(authProvider).user?.id;

  // ===========================================================================
  // SOCKET SETUP
  // ===========================================================================

  void _initSocket() {
    if (_socketInitialized) return;

    final socket = SocketService.instance.rawSocket;
    if (socket == null) return;

    _socket = socket;
    _socketInitialized = true;

    // Listen for real-time friend events
    _socket!.on('friend_request_received', (data) {
      _handleFriendRequestReceived(data);
    });

    _socket!.on('friend_request_accepted', (data) {
      _handleFriendRequestAccepted(data);
    });

    _socket!.on('friend_message', (data) {
      _handleFriendMessage(data);
    });

    _socket!.on('friend_transfer_received', (data) {
      _handleTransferReceived(data);
    });
  }

  void _handleFriendRequestReceived(dynamic data) {
    if (data is Map<String, dynamic>) {
      pendingRequests.insert(0, data);
      notifyListeners();
    }
  }

  void _handleFriendRequestAccepted(dynamic data) {
    if (data is Map<String, dynamic>) {
      // Remove from pending, add to friends
      pendingRequests.removeWhere(
          (r) => r['id'].toString() == data['friendshipId'].toString());
      fetchFriends();
      notifyListeners();
    }
  }

  void _handleFriendMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      // Update unread count
      unreadMessageCount++;

      // Update the friend's last message preview in the list
      final friendshipId = data['friendshipId']?.toString();
      if (friendshipId != null) {
        final idx = friends.indexWhere(
            (f) => f['friendshipId']?.toString() == friendshipId);
        if (idx != -1) {
          // Phase UI-7 (2026-05-27): write the new message into the
          // nested `latestMessage` shape that matches the BE response,
          // so `_buildFriendTile` renders the preview consistently
          // whether it came from REST or this socket update. Also keep
          // the legacy flat fields for any older code path that still
          // reads them.
          final newLatest = {
            'content': data['content'] ?? data['message'] ?? '',
            'createdAt': data['createdAt'] ??
                DateTime.now().toIso8601String(),
            'isFromMe': false,
          };
          final unreadInt = (friends[idx]['unreadCount'] ?? 0) is int
              ? friends[idx]['unreadCount'] as int
              : int.tryParse('${friends[idx]['unreadCount']}') ?? 0;
          friends[idx] = {
            ...friends[idx],
            'latestMessage': newLatest,
            'lastMessage': newLatest['content'],
            'lastMessageTime': newLatest['createdAt'],
            'unreadCount': unreadInt + 1,
          };
          // Re-sort by latest message time so the row jumps to the top.
          friends.sort((a, b) {
            final aTime = (a['latestMessage'] is Map<String, dynamic>
                    ? (a['latestMessage'] as Map<String, dynamic>)['createdAt']
                    : null) ??
                a['lastMessageTime'] ??
                '';
            final bTime = (b['latestMessage'] is Map<String, dynamic>
                    ? (b['latestMessage'] as Map<String, dynamic>)['createdAt']
                    : null) ??
                b['lastMessageTime'] ??
                '';
            return bTime.toString().compareTo(aTime.toString());
          });
        }
      }
      notifyListeners();
    }
  }

  void _handleTransferReceived(dynamic data) {
    // Refresh friends list to show transfer message in chat preview
    fetchFriends();
  }

  // ===========================================================================
  // DATA FETCHING
  // ===========================================================================

  Future<void> fetchFriends() async {
    final token = _token;
    if (token == null) return;
    _initSocket();

    try {
      friends = await _service.getFriends(token);
      // The BE already returns rows ordered by Friendship.updatedAt DESC
      // (which is bumped by every direct message + peer transfer), so the
      // initial response ordering is correct. We re-sort defensively only
      // when the row carries a `latestMessage.createdAt` so an older BE
      // response missing that field doesn't shuffle a non-deterministic
      // ordering on top.
      friends.sort((a, b) {
        final aTime = (a['latestMessage'] is Map<String, dynamic>
                ? (a['latestMessage'] as Map<String, dynamic>)['createdAt']
                : null) ??
            a['lastMessageTime'] ??
            '';
        final bTime = (b['latestMessage'] is Map<String, dynamic>
                ? (b['latestMessage'] as Map<String, dynamic>)['createdAt']
                : null) ??
            b['lastMessageTime'] ??
            '';
        return bTime.toString().compareTo(aTime.toString());
      });
      notifyListeners();
    } catch (e) {
      debugPrint('FriendProvider.fetchFriends error: $e');
    }
  }

  Future<void> fetchPendingRequests() async {
    final token = _token;
    if (token == null) return;

    try {
      pendingRequests = await _service.getPendingRequests(token);
      notifyListeners();
    } catch (e) {
      debugPrint('FriendProvider.fetchPendingRequests error: $e');
    }
  }

  Future<void> fetchUnreadCount() async {
    final token = _token;
    if (token == null) return;

    try {
      unreadMessageCount = await _service.getUnreadCount(token);
      notifyListeners();
    } catch (e) {
      debugPrint('FriendProvider.fetchUnreadCount error: $e');
    }
  }

  // ===========================================================================
  // ACTIONS
  // ===========================================================================

  Future<void> searchUsers(String query) async {
    final token = _token;
    if (token == null) return;

    if (query.trim().length < 2) {
      searchResults = [];
      notifyListeners();
      return;
    }

    isLoading = true;
    notifyListeners();

    try {
      searchResults = await _service.searchUsers(query, token);
    } catch (e) {
      debugPrint('FriendProvider.searchUsers error: $e');
      searchResults = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> sendRequest(int addresseeId, String message) async {
    final token = _token;
    if (token == null) return false;

    try {
      await _service.sendFriendRequest(addresseeId, message, token);
      // Remove from search results or mark as sent
      searchResults = searchResults.map((u) {
        if (u['id'] == addresseeId) {
          return {...u, 'requestSent': true};
        }
        return u;
      }).toList();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('FriendProvider.sendRequest error: $e');
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> acceptRequest(String id) async {
    final token = _token;
    if (token == null) return false;

    try {
      await _service.acceptFriendRequest(id, token);
      pendingRequests.removeWhere((r) => r['id'].toString() == id);
      await fetchFriends();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('FriendProvider.acceptRequest error: $e');
      return false;
    }
  }

  Future<bool> rejectRequest(String id) async {
    final token = _token;
    if (token == null) return false;

    try {
      await _service.rejectFriendRequest(id, token);
      pendingRequests.removeWhere((r) => r['id'].toString() == id);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('FriendProvider.rejectRequest error: $e');
      return false;
    }
  }

  /// Refresh all friend-related data
  Future<void> refreshAll() async {
    isLoading = true;
    notifyListeners();

    await Future.wait([
      fetchFriends(),
      fetchPendingRequests(),
      fetchUnreadCount(),
    ]);

    isLoading = false;
    notifyListeners();
  }

  /// Clear search results
  void clearSearch() {
    searchResults = [];
    notifyListeners();
  }

  // ===========================================================================
  // CLEANUP
  // ===========================================================================

  @override
  void dispose() {
    disconnectSocket();
    super.dispose();
  }

  void disconnectSocket() {
    if (_socket != null) {
      _socket!.off('friend_request_received');
      _socket!.off('friend_request_accepted');
      _socket!.off('friend_message');
      _socket!.off('friend_transfer_received');
    }
    _socket = null;
    _socketInitialized = false;
  }
}

// =============================================================================
// RIVERPOD HANDLE
// =============================================================================
final friendProvider = ChangeNotifierProvider<FriendProvider>((ref) {
  return FriendProvider(ref);
});
