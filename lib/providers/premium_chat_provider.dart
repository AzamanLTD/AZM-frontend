// lib/providers/premium_chat_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:azaman/models/chat_message.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/socket_service.dart';
import 'dart:convert';

// ── Context descriptor ────────────────────────────────────────────────────
enum ChatContext { friend, trade, group, ticket }

class ChatContextParams {
  final ChatContext context;
  final String contextId; // friendshipId | tradeId | groupId | ticketId
  const ChatContextParams({required this.context, required this.contextId});
  @override bool operator ==(Object o) =>
    o is ChatContextParams && o.context == context && o.contextId == contextId;
  @override int get hashCode => Object.hash(context, contextId);
}

// ── State ─────────────────────────────────────────────────────────────────
class PremiumChatState {
  final List<ChatMessage> messages; // newest-first in memory, rendered reversed
  final bool isLoading;
  final bool hasMore;
  final bool isSending;
  final String? errorMessage;
  final Set<String> typingUserIds; // users currently typing
  final Map<int,String> groupMemberNames; // userId -> username for group avatar labels

  const PremiumChatState({
    this.messages = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.isSending = false,
    this.errorMessage,
    this.typingUserIds = const {},
    this.groupMemberNames = const {},
  });

  PremiumChatState copyWith({
    List<ChatMessage>? messages, bool? isLoading, bool? hasMore,
    bool? isSending, String? errorMessage,
    Set<String>? typingUserIds, Map<int,String>? groupMemberNames,
  }) => PremiumChatState(
    messages: messages ?? this.messages,
    isLoading: isLoading ?? this.isLoading,
    hasMore: hasMore ?? this.hasMore,
    isSending: isSending ?? this.isSending,
    errorMessage: errorMessage,
    typingUserIds: typingUserIds ?? this.typingUserIds,
    groupMemberNames: groupMemberNames ?? this.groupMemberNames,
  );
}

// ── Riverpod Provider ─────────────────────────────────────────────────────
final premiumChatProvider = StateNotifierProvider.autoDispose.family<
  PremiumChatNotifier, PremiumChatState, ChatContextParams>(
  (ref, params) => PremiumChatNotifier(ref, params),
);

// ── Notifier ──────────────────────────────────────────────────────────────
class PremiumChatNotifier extends StateNotifier<PremiumChatState> {
  final Ref _ref;
  final ChatContextParams _params;
  final _uuid = const Uuid();
  Timer? _typingTimer;
  static const _ackTimeout = Duration(seconds: 7);
  final Map<String, Timer> _ackTimers = {};

  PremiumChatNotifier(this._ref, this._params)
    : super(const PremiumChatState()) {
    _init();
  }

  String get _myUserId =>
    _ref.read(authProvider).user?.id?.toString() ?? '';

  void _init() {
    _joinRoom();
    loadMessages();
    _subscribeToSocket();
  }

  void _joinRoom() {
    final socket = SocketService.instance.rawSocket;
    if (socket == null) return;
    switch (_params.context) {
      case ChatContext.friend:
        SocketService.instance.joinFriendRoom(_params.contextId, _myUserId);
        break;
      case ChatContext.group:
        SocketService.instance.joinGroupRoom(_params.contextId, _myUserId);
        break;
      case ChatContext.trade:
        socket.emit('join_trade', {
          'tradeId': _params.contextId,
          'userId': _myUserId,
        });
        break;
      case ChatContext.ticket:
        socket.emit('join_ticket', {
          'ticketId': _params.contextId,
          'userId': _myUserId,
        });
        break;
    }
  }

  void _leaveRoom() {
    final socket = SocketService.instance.rawSocket;
    if (socket == null) return;
    switch (_params.context) {
      case ChatContext.friend:
        SocketService.instance.leaveFriendRoom(_params.contextId, _myUserId);
        break;
      case ChatContext.group:
        SocketService.instance.leaveGroupRoom(_params.contextId, _myUserId);
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _leaveRoom();
    _unsubscribeFromSocket();
    super.dispose();
  }

  // ── LOAD MESSAGES (paginated, newest first) ─────────────────────────────
  Future<void> loadMessages({bool loadMore = false}) async {
    if (state.isLoading) return;
    if (loadMore && !state.hasMore) return;
    state = state.copyWith(isLoading: true);
    try {
      final before = loadMore && state.messages.isNotEmpty
        ? state.messages.last.id : null;
      final endpoint = _messagesEndpoint(before: before);
      final res = await apiClient.get(endpoint);
      if (res.statusCode != 200) throw Exception('Load failed');
      final body = jsonDecode(res.body) as Map<String,dynamic>;
      final rawList = (body['messages'] ?? body['data'] ?? []) as List;
      final loaded = rawList.map((j) =>
        ChatMessage.fromJson(j as Map<String,dynamic>, myUserId: _myUserId,
          initialStatus: MessageStatus.read)).toList();
      // Always sort newest-first so the reverse:true ListView shows messages
      // in the correct order regardless of the order returned by the server.
      // (friend-chat endpoint returns chronological; group-chat returns DESC.)
      final merged = loadMore ? [...state.messages, ...loaded] : loaded;
      merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      state = state.copyWith(
        messages: merged,
        hasMore: body['hasMore'] == true,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, hasMore: false, errorMessage: e.toString());
    }
  }

  String _messagesEndpoint({String? before}) {
    final b = before != null ? '?before=$before&limit=50' : '?limit=50';
    switch (_params.context) {
      case ChatContext.friend:
        return '/friends/chat/${_params.contextId}/messages$b';
      case ChatContext.trade:
        return '/chat/messages/${_params.contextId}$b';
      case ChatContext.group:
        return '/group-chats/${_params.contextId}/messages$b';
      case ChatContext.ticket:
        return '/tickets/${_params.contextId}/messages$b';
    }
  }

  // ── OPTIMISTIC SEND ─────────────────────────────────────────────────────
  // Creates a local placeholder immediately, then sends over socket.
  // On message_ack, placeholder is upgraded with the server ID.
  // On message_error, placeholder is marked failed (retry button shows).
  Future<void> sendTextMessage(String text, {
    String? replyToId, String? replyToText, String? replyToSenderName,
  }) async {
    if (text.trim().isEmpty) return;
    final localId = _uuid.v4();
    final optimistic = ChatMessage.optimistic(
      localId: localId,
      senderId: _myUserId,
      senderUsername: _ref.read(authProvider).user?.username,
      text: text.trim(),
      replyToId: replyToId,
      replyToText: replyToText,
      replyToSenderName: replyToSenderName,
    );
    // Prepend to list (newest first)
    state = state.copyWith(messages: [optimistic, ...state.messages]);
    _emitSendEvent(localId, text.trim(), 'TEXT',
      replyToId: replyToId,
      replyToText: replyToText,
      replyToSenderName: replyToSenderName,
    );
  }

  Future<void> sendMediaMessage({
    required String mediaUrl,
    required String mediaType,
    required String messageType,
    String? mimeType, int? size, int? duration,
    List<int>? waveformPeaks,
    Map<String,dynamic>? linkPreview,
    String? caption,
  }) async {
    final localId = _uuid.v4();
    final kind = MessageKind.values.firstWhere(
      (k) => k.name.toUpperCase() == messageType.toUpperCase(),
      orElse: () => MessageKind.image);
    final optimistic = ChatMessage.optimistic(
      localId: localId,
      senderId: _myUserId,
      text: caption ?? '',
      kind: kind,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      mediaDuration: duration,
      waveformPeaks: waveformPeaks,
    );
    state = state.copyWith(messages: [optimistic, ...state.messages]);
    _emitSendEvent(localId, caption ?? '', messageType,
      mediaUrl: mediaUrl, mediaType: mediaType,
      mediaMimeType: mimeType, mediaSize: size,
      mediaDuration: duration, waveformPeaks: waveformPeaks,
      linkPreview: linkPreview,
    );
  }

  void _emitSendEvent(String localId, String content, String messageType, {
    String? replyToId, String? replyToText, String? replyToSenderName,
    String? mediaUrl, String? mediaType, String? mediaMimeType,
    int? mediaSize, int? mediaDuration, List<int>? waveformPeaks,
    Map<String,dynamic>? linkPreview,
  }) {
    // Ticket chat has NO socket send handler on the backend by design --
    // authoritative writes are REST-only. Skip straight to HTTP.
    if (_params.context == ChatContext.ticket) {
      _sendViaHttp(localId, content, messageType, replyToId: replyToId,
        replyToText: replyToText, replyToSenderName: replyToSenderName,
        mediaUrl: mediaUrl, mediaType: mediaType, mediaMimeType: mediaMimeType,
        mediaSize: mediaSize, mediaDuration: mediaDuration,
        waveformPeaks: waveformPeaks, linkPreview: linkPreview);
      return;
    }

    final socket = SocketService.instance.rawSocket;
    if (socket == null) {
      _sendViaHttp(localId, content, messageType, replyToId: replyToId,
        replyToText: replyToText, replyToSenderName: replyToSenderName,
        mediaUrl: mediaUrl, mediaType: mediaType, mediaMimeType: mediaMimeType,
        mediaSize: mediaSize, mediaDuration: mediaDuration,
        waveformPeaks: waveformPeaks, linkPreview: linkPreview);
      return;
    }

    final base = {
      'localId': localId, 'senderId': _myUserId, 'content': content, 'messageType': messageType,
      if (replyToId != null) 'replyToId': replyToId,
      if (replyToText != null) 'replyToText': replyToText,
      if (replyToSenderName != null) 'replyToSenderName': replyToSenderName,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (mediaType != null) 'mediaType': mediaType,
      if (mediaMimeType != null) 'mediaMimeType': mediaMimeType,
      if (mediaSize != null) 'mediaSize': mediaSize,
      if (mediaDuration != null) 'mediaDuration': mediaDuration,
      if (waveformPeaks != null) 'mediaWaveformPeaks': waveformPeaks,
      if (linkPreview != null) 'linkPreview': linkPreview,
    };

    switch (_params.context) {
      case ChatContext.friend:
        socket.emit('send_friend_message_v2', {
          ...base, 'friendshipId': _params.contextId, 'tempId': localId,
        });
        break;
      case ChatContext.trade:
        socket.emit('send_trade_message', {
          ...base, 'tradeId': _params.contextId,
        });
        break;
      case ChatContext.group:
        socket.emit('send_group_message', {
          ...base, 'groupId': _params.contextId, 'type': messageType,
        });
        break;
      case ChatContext.ticket:
        break;
    }

    // Safety-net watchdog. Cancelled by _cancelAckTimer() the instant any
    // ack-style event lands for this localId (message_ack, friend_message_saved,
    // or the room broadcast echoing our own message back to us).
    _ackTimers[localId]?.cancel();
    _ackTimers[localId] = Timer(_ackTimeout, () {
      _ackTimers.remove(localId);
      final stillPending = state.messages.any(
        (m) => m.localId == localId && m.status == MessageStatus.sending);
      if (stillPending) {
        _sendViaHttp(localId, content, messageType, replyToId: replyToId,
          replyToText: replyToText, replyToSenderName: replyToSenderName,
          mediaUrl: mediaUrl, mediaType: mediaType, mediaMimeType: mediaMimeType,
          mediaSize: mediaSize, mediaDuration: mediaDuration,
          waveformPeaks: waveformPeaks, linkPreview: linkPreview);
      }
    });
  }

  void _cancelAckTimer(String localId) {
    _ackTimers[localId]?.cancel();
    _ackTimers.remove(localId);
  }

  Future<void> _sendViaHttp(String localId, String content, String messageType, {
    String? replyToId, String? replyToText, String? replyToSenderName,
    String? mediaUrl, String? mediaType, String? mediaMimeType,
    int? mediaSize, int? mediaDuration, List<int>? waveformPeaks,
    Map<String,dynamic>? linkPreview,
  }) async {
    final endpoint = _httpSendEndpoint();
    if (endpoint == null) { _markFailed(localId); return; }

    final Map<String, dynamic> bodyMap;
    if (_params.context == ChatContext.group) {
      bodyMap = {
        'type': messageType, 'content': content,
        if (replyToId != null) 'replyToId': replyToId,
        if (replyToText != null) 'replyToText': replyToText,
        if (replyToSenderName != null) 'replyToSenderName': replyToSenderName,
        if (mediaUrl != null) 'media': {
          'url': mediaUrl, 'type': mediaType,
          if (mediaMimeType != null) 'mimeType': mediaMimeType,
          if (mediaSize != null) 'size': mediaSize,
          if (mediaDuration != null) 'duration': mediaDuration,
          if (waveformPeaks != null) 'waveformPeaks': waveformPeaks,
          if (linkPreview != null) 'linkPreview': linkPreview,
        },
      };
    } else {
      bodyMap = {
        'content': content, 'messageType': messageType,
        if (replyToId != null) 'replyToId': replyToId,
        if (replyToText != null) 'replyToText': replyToText,
        if (replyToSenderName != null) 'replyToSenderName': replyToSenderName,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (mediaType != null) 'mediaType': mediaType,
        if (mediaMimeType != null) 'mediaMimeType': mediaMimeType,
        if (mediaSize != null) 'mediaSize': mediaSize,
        if (mediaDuration != null) 'mediaDuration': mediaDuration,
        if (waveformPeaks != null) 'mediaWaveformPeaks': waveformPeaks,
        if (linkPreview != null) 'linkPreview': linkPreview,
      };
    }

    try {
      final res = await apiClient.post(endpoint, bodyMap);
      if (res.statusCode != 200 && res.statusCode != 201) { _markFailed(localId); return; }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) { _markFailed(localId); return; }
      final serverMsg = decoded['message'];
      if (serverMsg is Map<String, dynamic>) {
        final serverId = serverMsg['id']?.toString() ?? '';
        final rawTs = serverMsg['createdAt'];
        final ts = rawTs != null ? (DateTime.tryParse(rawTs.toString())?.toLocal() ?? DateTime.now()) : DateTime.now();
        if (serverId.isNotEmpty) {
          _updateMessage(localId, (m) => m.upgradeWithAck(serverId, ts));
        } else { _markFailed(localId); }
      } else { _markFailed(localId); }
    } catch (_) { _markFailed(localId); }
  }

  String? _httpSendEndpoint() {
    switch (_params.context) {
      case ChatContext.friend: return '/friends/chat/${_params.contextId}/messages';
      case ChatContext.group:  return '/group-chats/${_params.contextId}/messages';
      case ChatContext.ticket: return '/tickets/${_params.contextId}/messages';
      case ChatContext.trade:  return null;
    }
  }

  void retryMessage(String localId) {
    final idx = state.messages.indexWhere((m) => m.localId == localId);
    if (idx == -1) return;
    final msg = state.messages[idx];
    _updateMessage(localId, (m) { m.status = MessageStatus.sending; return m; });
    _emitSendEvent(localId, msg.text, msg.kind.name.toUpperCase(),
      mediaUrl: msg.mediaUrl, mediaType: msg.mediaType,
      replyToId: msg.replyToId, replyToText: msg.replyToText,
      replyToSenderName: msg.replyToSenderName,
    );
  }

  // ── SOCKET SUBSCRIPTIONS ────────────────────────────────────────────────
  void _subscribeToSocket() {
    final socket = SocketService.instance.rawSocket;
    if (socket == null) return;

    // message_ack — optimistic bubble transitions sending→sent
    socket.on('message_ack', (data) {
      if (data is! Map) return;
      final localId  = data['localId']?.toString() ?? '';
      final serverId = data['id']?.toString() ?? '';
      final ts       = data['createdAt'];
      final serverTs = ts != null
        ? DateTime.tryParse(ts.toString())?.toLocal() ?? DateTime.now()
        : DateTime.now();
      _cancelAckTimer(localId);
      _updateMessage(localId, (m) => m.upgradeWithAck(serverId, serverTs));
    });

    // legacy friend_message_saved
    socket.on('friend_message_saved', (data) {
      if (data is! Map) return;
      final localId  = data['tempId']?.toString() ?? '';
      final serverId = data['id']?.toString() ?? '';
      final ts       = data['createdAt'];
      final serverTs = ts != null
        ? DateTime.tryParse(ts.toString())?.toLocal() ?? DateTime.now()
        : DateTime.now();
      _cancelAckTimer(localId);
      _updateMessage(localId, (m) => m.upgradeWithAck(serverId, serverTs));
    });

    // message_delivered — single→double tick (grey)
    socket.on('message_delivered', (data) {
      if (data is! Map) return;
      final id = data['id']?.toString() ?? '';
      _updateMessageById(id, (m) {
        m.status = MessageStatus.delivered; return m;
      });
    });

    // messages_read / message_read — double tick turns blue
    socket.on('messages_read', (data) {
      if (data is! Map) return;
      final ctxId = data['contextId']?.toString() ?? '';
      if (ctxId != _params.contextId) return;
      final updated = state.messages.map((m) {
        if (m.isMe && m.status != MessageStatus.read) {
          m.status = MessageStatus.read;
        }
        return m;
      }).toList();
      state = state.copyWith(messages: updated);
    });
    socket.on('message_read', (data) {
      if (data is! Map) return;
      final id = data['id']?.toString() ?? '';
      _updateMessageById(id, (m) { m.status = MessageStatus.read; return m; });
    });

    // message_error — mark optimistic as failed
    socket.on('message_error', (data) {
      if (data is! Map) return;
      _markFailed(data['localId']?.toString() ?? '');
    });

    // new incoming messages
    final incomingEvents = _incomingEventNames();
    for (final ev in incomingEvents) {
      socket.on(ev, (data) {
        if (data is! Map) return;
        final incoming = ChatMessage.fromJson(
          Map<String,dynamic>.from(data as Map),
          myUserId: _myUserId,
          initialStatus: MessageStatus.sent,
        );
        // De-dupe: if we already have this localId (our own optimistic echo), skip
        final localId = incoming.localId;
        if (localId.isNotEmpty) _cancelAckTimer(localId);
        if (localId.isNotEmpty && state.messages.any((m) => m.localId == localId)) return;
        state = state.copyWith(messages: [incoming, ...state.messages]);
        // Auto-mark as read if this is our own chat screen
        _markRead();
      });
    }

    // reaction_updated
    socket.on('reaction_updated', (data) {
      if (data is! Map) return;
      final msgId = data['messageId']?.toString() ?? '';
      final rawR = data['reactions'];
      if (rawR is! Map) return;
      final newReactions = <String, List<int>>{};
      rawR.forEach((k, v) {
        if (v is List) newReactions[k.toString()] = v.whereType<int>().toList();
      });
      _updateMessageById(msgId, (m) => m.copyWith(reactions: newReactions));
    });

    // message_edited
    socket.on('message_edited', (data) {
      if (data is! Map) return;
      final msgId  = data['messageId']?.toString() ?? '';
      final newTxt = data['newContent']?.toString() ?? '';
      _updateMessageById(msgId, (m) =>
        m.copyWith(text: newTxt, isEdited: true));
    });

    // message_deleted
    socket.on('message_deleted', (data) {
      if (data is! Map) return;
      final msgId = data['messageId']?.toString() ?? '';
      _updateMessageById(msgId, (m) => m.copyWith(isDeleted: true));
    });

    // typing_started / typing_stopped
    socket.on('typing_started', (data) {
      if (data is! Map) return;
      final uid = data['userId']?.toString() ?? '';
      if (uid.isEmpty || uid == _myUserId) return;
      final updated = Set<String>.from(state.typingUserIds)..add(uid);
      state = state.copyWith(typingUserIds: updated);
    });
    socket.on('typing_stopped', (data) {
      if (data is! Map) return;
      final uid = data['userId']?.toString() ?? '';
      final updated = Set<String>.from(state.typingUserIds)..remove(uid);
      state = state.copyWith(typingUserIds: updated);
    });
    // backward-compat typing aliases
    socket.on('user_typing_personal', (d) => _handleLegacyTyping(d));
    socket.on('user_typing_trade',    (d) => _handleLegacyTyping(d));
    socket.on('friend_typing',        (d) => _handleLegacyTyping(d));
    socket.on('group_typing_started', (d) => _handleLegacyTyping(d, isTyping: true));
    socket.on('group_typing_stopped', (d) => _handleLegacyTyping(d, isTyping: false));
  }

  void _handleLegacyTyping(dynamic d, {bool? isTyping}) {
    if (d is! Map) return;
    final uid = (d['userId'] ?? d['friendId'])?.toString() ?? '';
    if (uid.isEmpty || uid == _myUserId) return;
    final typing = isTyping ?? (d['isTyping'] == true);
    final updated = Set<String>.from(state.typingUserIds);
    typing ? updated.add(uid) : updated.remove(uid);
    state = state.copyWith(typingUserIds: updated);
  }

  void _unsubscribeFromSocket() {
    final socket = SocketService.instance.rawSocket;
    if (socket == null) return;
    for (final ev in [
      'message_ack','message_delivered','messages_read','message_read',
      'message_error','reaction_updated','message_edited','message_deleted',
      'typing_started','typing_stopped',
      ..._incomingEventNames()
    ]) { socket.off(ev); }
  }

  List<String> _incomingEventNames() {
    switch (_params.context) {
      case ChatContext.friend:  return ['friend_message'];
      case ChatContext.trade:   return ['new_trade_message','new_message'];
      case ChatContext.group:   return ['new_group_message'];
      case ChatContext.ticket:  return ['ticket_message'];
    }
  }

  // ── EMIT TYPING ─────────────────────────────────────────────────────────
  void sendTyping(bool isTyping) {
    final socket = SocketService.instance.rawSocket;
    if (socket == null) return;
    socket.emit('typing', {
      'userId': _myUserId,
      'context': _params.context.name,
      'contextId': _params.contextId,
      'isTyping': isTyping,
    });
  }

  // ── MARK AS READ ─────────────────────────────────────────────────────────
  void _markRead() {
    final socket = SocketService.instance.rawSocket;
    if (socket == null) return;
    final latestId = state.messages.firstOrNull?.id ?? '';
    socket.emit('mark_messages_read', {
      'context': _params.context.name,
      'contextId': _params.contextId,
      'userId': _myUserId,
      'upToMessageId': latestId,
    });
  }

  // ── REACT TO MESSAGE ─────────────────────────────────────────────────────
  void reactToMessage(String messageId, String emoji) {
    final socket = SocketService.instance.rawSocket;
    if (socket == null) return;
    socket.emit('react_to_message', {
      'messageId': messageId,
      'emoji': emoji,
      'userId': _myUserId,
      'context': _params.context.name,
      'contextId': _params.contextId,
    });
  }

  // ── EDIT MESSAGE ─────────────────────────────────────────────────────────
  void editMessage(String messageId, String newContent) {
    final socket = SocketService.instance.rawSocket;
    if (socket == null) return;
    socket.emit('edit_message', {
      'messageId': messageId, 'newContent': newContent,
      'userId': _myUserId,
      'context': _params.context.name,
      'contextId': _params.contextId,
    });
  }

  // ── DELETE MESSAGE ───────────────────────────────────────────────────────
  void deleteMessage(String messageId) {
    final socket = SocketService.instance.rawSocket;
    if (socket == null) return;
    socket.emit('delete_message', {
      'messageId': messageId, 'userId': _myUserId,
      'context': _params.context.name,
      'contextId': _params.contextId,
    });
  }


  // ── INTERNAL HELPERS ─────────────────────────────────────────────────────
  void _updateMessage(String localId, ChatMessage Function(ChatMessage) fn) {
    final idx = state.messages.indexWhere((m) => m.localId == localId);
    if (idx == -1) return;
    final list = List<ChatMessage>.from(state.messages);
    list[idx] = fn(list[idx]);
    state = state.copyWith(messages: list);
  }

  void _updateMessageById(String id, ChatMessage Function(ChatMessage) fn) {
    if (id.isEmpty) return;
    final idx = state.messages.indexWhere(
      (m) => m.id == id || m.localId == id);
    if (idx == -1) return;
    final list = List<ChatMessage>.from(state.messages);
    list[idx] = fn(list[idx]);
    state = state.copyWith(messages: list);
  }

  void _markFailed(String localId) {
    _updateMessage(localId, (m) { m.status = MessageStatus.failed; return m; });
  }
}

