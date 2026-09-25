// =============================================================================
// CHAT PROFILE PROVIDER — Phase UI-5 (2026-05-26)
//
// Riverpod state for the Chat Profile + Vault screen. One family per
// friendship; auto-disposes when the screen pops.
//
// Owns:
//   • profile         — identity tier + my nickname for the friend
//   • mediaItems      — vault tab 1 (images + videos, mixed direct + ticket)
//   • docsLinkItems   — vault tab 2 (documents + link previews)
//   • receiptItems    — vault tab 4 (P2P transfer receipts)
//
// Tickets (vault tab 3) are served by the existing `ticketDashboardProvider`
// from Phase UI-4 — this provider doesn't duplicate the state.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/chat_profile_service.dart';

class ChatProfileState {
  final ChatProfileResponse? profile;
  final List<VaultItem> mediaItems;
  final List<VaultItem> docsLinkItems;
  final List<ReceiptItem> receiptItems;
  final bool profileLoading;
  final bool mediaLoading;
  final bool docsLoading;
  final bool receiptsLoading;
  final bool nicknameUpdating;
  // Phase UI-POLISH: cursor pagination on the receipts vault tab.
  final bool receiptsHasMore;
  final String? receiptsNextCursor;
  final bool receiptsLoadingMore;
  final String? error;

  const ChatProfileState({
    this.profile,
    this.mediaItems = const [],
    this.docsLinkItems = const [],
    this.receiptItems = const [],
    this.profileLoading = false,
    this.mediaLoading = false,
    this.docsLoading = false,
    this.receiptsLoading = false,
    this.nicknameUpdating = false,
    this.receiptsHasMore = false,
    this.receiptsNextCursor,
    this.receiptsLoadingMore = false,
    this.error,
  });

  ChatProfileState copyWith({
    ChatProfileResponse? profile,
    List<VaultItem>? mediaItems,
    List<VaultItem>? docsLinkItems,
    List<ReceiptItem>? receiptItems,
    bool? profileLoading,
    bool? mediaLoading,
    bool? docsLoading,
    bool? receiptsLoading,
    bool? nicknameUpdating,
    bool? receiptsHasMore,
    String? receiptsNextCursor,
    bool? receiptsLoadingMore,
    bool clearReceiptsCursor = false,
    String? error,
    bool clearError = false,
  }) {
    return ChatProfileState(
      profile: profile ?? this.profile,
      mediaItems: mediaItems ?? this.mediaItems,
      docsLinkItems: docsLinkItems ?? this.docsLinkItems,
      receiptItems: receiptItems ?? this.receiptItems,
      profileLoading: profileLoading ?? this.profileLoading,
      mediaLoading: mediaLoading ?? this.mediaLoading,
      docsLoading: docsLoading ?? this.docsLoading,
      receiptsLoading: receiptsLoading ?? this.receiptsLoading,
      nicknameUpdating: nicknameUpdating ?? this.nicknameUpdating,
      receiptsHasMore: receiptsHasMore ?? this.receiptsHasMore,
      receiptsNextCursor: clearReceiptsCursor
          ? null
          : (receiptsNextCursor ?? this.receiptsNextCursor),
      receiptsLoadingMore: receiptsLoadingMore ?? this.receiptsLoadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ChatProfileNotifier extends StateNotifier<ChatProfileState> {
  final String friendshipId;
  final ChatProfileService _service;

  ChatProfileNotifier(this.friendshipId, this._service)
      : super(const ChatProfileState());

  /// First-load: fetches profile + all four vault datasets in parallel.
  /// Subsequent tab switches don't re-fetch unless the user pulls to
  /// refresh — vault datasets are cheap but we don't want to thrash.
  Future<void> primeAll() async {
    if (state.profileLoading) return;
    state = state.copyWith(
      profileLoading: true,
      mediaLoading: true,
      docsLoading: true,
      receiptsLoading: true,
      clearError: true,
    );
    try {
      final results = await Future.wait([
        _service.getProfile(friendshipId),
        _service.getMedia(friendshipId),
        _service.getDocsAndLinks(friendshipId),
        _service.getReceipts(friendshipId),
      ]);
      final receiptsResp = results[3] as VaultListResponse<ReceiptItem>;
      state = state.copyWith(
        profile: results[0] as ChatProfileResponse,
        mediaItems: (results[1] as VaultListResponse<VaultItem>).items,
        docsLinkItems: (results[2] as VaultListResponse<VaultItem>).items,
        receiptItems: receiptsResp.items,
        receiptsHasMore: receiptsResp.hasMore,
        receiptsNextCursor: receiptsResp.nextCursor,
        clearReceiptsCursor: receiptsResp.nextCursor == null,
        profileLoading: false,
        mediaLoading: false,
        docsLoading: false,
        receiptsLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        profileLoading: false,
        mediaLoading: false,
        docsLoading: false,
        receiptsLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> refreshProfile() async {
    state = state.copyWith(profileLoading: true);
    try {
      final p = await _service.getProfile(friendshipId);
      state = state.copyWith(profile: p, profileLoading: false);
    } catch (e) {
      state = state.copyWith(profileLoading: false, error: e.toString());
    }
  }

  Future<void> refreshMedia() async {
    state = state.copyWith(mediaLoading: true);
    try {
      final r = await _service.getMedia(friendshipId);
      state = state.copyWith(mediaItems: r.items, mediaLoading: false);
    } catch (e) {
      state = state.copyWith(mediaLoading: false, error: e.toString());
    }
  }

  Future<void> refreshDocsLinks() async {
    state = state.copyWith(docsLoading: true);
    try {
      final r = await _service.getDocsAndLinks(friendshipId);
      state = state.copyWith(docsLinkItems: r.items, docsLoading: false);
    } catch (e) {
      state = state.copyWith(docsLoading: false, error: e.toString());
    }
  }

  Future<void> refreshReceipts() async {
    state = state.copyWith(receiptsLoading: true);
    try {
      final r = await _service.getReceipts(friendshipId);
      state = state.copyWith(
        receiptItems: r.items,
        receiptsHasMore: r.hasMore,
        receiptsNextCursor: r.nextCursor,
        clearReceiptsCursor: r.nextCursor == null,
        receiptsLoading: false,
      );
    } catch (e) {
      state = state.copyWith(receiptsLoading: false, error: e.toString());
    }
  }

  /// Phase UI-POLISH: cursor-based pagination for the Receipts vault
  /// tab. The FE shows a "Load more" button at the bottom of the list
  /// when `receiptsHasMore` is true; tapping it appends the next page.
  Future<void> loadMoreReceipts() async {
    if (!state.receiptsHasMore ||
        state.receiptsLoadingMore ||
        state.receiptsNextCursor == null) {
      return;
    }
    state = state.copyWith(receiptsLoadingMore: true);
    try {
      final r = await _service.getReceipts(
        friendshipId,
        cursor: state.receiptsNextCursor,
      );
      state = state.copyWith(
        receiptItems: [...state.receiptItems, ...r.items],
        receiptsHasMore: r.hasMore,
        receiptsNextCursor: r.nextCursor,
        clearReceiptsCursor: r.nextCursor == null,
        receiptsLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(
          receiptsLoadingMore: false, error: e.toString());
    }
  }

  /// Set or clear the caller's local nickname for this friend. Pass null
  /// or an empty string to clear it. Optimistic update — the local
  /// `myNicknameForFriend` field flips immediately, then the server call
  /// either confirms or rolls back via refreshProfile().
  Future<void> setNickname(String? nickname) async {
    if (state.profile == null || state.nicknameUpdating) return;
    final cleaned = (nickname ?? '').trim();
    final next = cleaned.isEmpty ? null : cleaned;

    final originalProfile = state.profile!;
    final optimistic = ChatProfileResponse(
      friendshipId: originalProfile.friendshipId,
      friendSince: originalProfile.friendSince,
      friendshipStatus: originalProfile.friendshipStatus,
      friend: originalProfile.friend,
      myNicknameForFriend: next,
      mutualTradesCompleted: originalProfile.mutualTradesCompleted,
    );
    state = state.copyWith(profile: optimistic, nicknameUpdating: true, clearError: true);
    try {
      await _service.setNickname(friendshipId, next);
      state = state.copyWith(nicknameUpdating: false);
    } catch (e) {
      // Rollback on failure
      state = state.copyWith(
        profile: originalProfile,
        nicknameUpdating: false,
        error: e.toString(),
      );
    }
  }
}

final chatProfileProvider = StateNotifierProvider.family
    .autoDispose<ChatProfileNotifier, ChatProfileState, String>(
  (ref, friendshipId) =>
      ChatProfileNotifier(friendshipId, ChatProfileService.instance),
);
