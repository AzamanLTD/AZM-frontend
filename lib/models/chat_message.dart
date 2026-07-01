// lib/models/chat_message.dart
// AZAMAN PREMIUM — Unified Chat Message Model
// Used by: FriendChatScreen, TransactionChatScreen, GroupChatScreen, TicketWorkspaceScreen

import 'dart:convert';

enum MessageStatus { sending, sent, delivered, read, failed }

enum MessageKind {
  text, image, video, audio, document, link,
  sticker, system, transaction, timeRequest, timeApproved,
  timeRejected, ticketLink, susuEvent, adminIntervention,
}

class ChatReaction {
  final String emoji;
  final List<int> userIds;
  const ChatReaction({required this.emoji, required this.userIds});
  int get count => userIds.length;
}

class ChatMessage {
  // ── Identity ─────────────────────────────────────────────────────────
  final String id;           // server UUID (empty until ACK'd)
  final String localId;      // client UUID — generated at send time
  final String senderId;
  final String? senderUsername;
  final String? senderAvatar;
  final bool isMe;

  // ── Content ──────────────────────────────────────────────────────────
  final String text;
  final MessageKind kind;
  final DateTime timestamp;
  MessageStatus status;      // mutable — updated by socket events

  // ── Media ─────────────────────────────────────────────────────────────
  final String? mediaUrl;
  final String? mediaType;
  final String? mediaMimeType;
  final int?    mediaSize;
  final int?    mediaDuration;
  final List<int>? waveformPeaks;
  final Map<String, dynamic>? linkPreview;

  // ── Reply / Forward ───────────────────────────────────────────────────
  final String? replyToId;
  final String? replyToText;
  final String? replyToSenderName;
  final String? forwardedFromUser;

  // ── Edit / Delete ─────────────────────────────────────────────────────
  bool isDeleted;
  bool isEdited;
  String? editedContent;     // original content before edit (for history)

  // ── Reactions ─────────────────────────────────────────────────────────
  // Map<emoji, List<userId>>  — server sends {"❤️": [1, 2], "👍": [3]}
  Map<String, List<int>> reactions;

  // ── Context-specific ──────────────────────────────────────────────────
  // For transaction messages (money transfer cards)
  final double?  amount;
  final String?  currency;
  // For stickers
  final String?  stickerAssetPath;
  final bool     isAnimatedSticker;
  // For SUSU_EVENT cards
  final Map<String, dynamic>? metadata;

  ChatMessage({
    required this.id,
    required this.localId,
    required this.senderId,
    this.senderUsername,
    this.senderAvatar,
    required this.isMe,
    required this.text,
    required this.kind,
    required this.timestamp,
    this.status = MessageStatus.sending,
    this.mediaUrl,
    this.mediaType,
    this.mediaMimeType,
    this.mediaSize,
    this.mediaDuration,
    this.waveformPeaks,
    this.linkPreview,
    this.replyToId,
    this.replyToText,
    this.replyToSenderName,
    this.forwardedFromUser,
    this.isDeleted = false,
    this.isEdited = false,
    this.editedContent,
    this.reactions = const {},
    this.amount,
    this.currency,
    this.stickerAssetPath,
    this.isAnimatedSticker = false,
    this.metadata,
  });

  /// Parse a server JSON payload into a ChatMessage.
  /// Works for DirectMessage, Message (trade), GroupMessage, TicketMessage.
  factory ChatMessage.fromJson(Map<String, dynamic> json, {
    required String myUserId,
    MessageStatus initialStatus = MessageStatus.sent,
  }) {
    final rawSenderId = json['senderId']?.toString() ?? json['sender']?['id']?.toString() ?? '';
    final rawType = (json['messageType'] ?? json['type'] ?? 'TEXT').toString().toUpperCase();
    final rawReactions = json['reactions'];
    Map<String, List<int>> parsedReactions = {};
    if (rawReactions is Map) {
      rawReactions.forEach((k, v) {
        if (v is List) parsedReactions[k.toString()] = v.whereType<int>().toList();
      });
    }
    List<int>? waveform;
    final rawWave = json['mediaWaveformPeaks'];
    if (rawWave is List) waveform = rawWave.whereType<int>().toList();
    Map<String, dynamic>? lp;
    final rawLp = json['linkPreview'];
    if (rawLp is Map) lp = Map<String, dynamic>.from(rawLp);
    Map<String, dynamic>? meta;
    final rawMeta = json['metadata'];
    if (rawMeta is Map) meta = Map<String, dynamic>.from(rawMeta);

    return ChatMessage(
      id:               json['id']?.toString() ?? '',
      localId:          json['localId']?.toString() ?? json['id']?.toString() ?? '',
      senderId:         rawSenderId,
      senderUsername:   json['senderUsername']?.toString()
                        ?? json['sender']?['username']?.toString(),
      senderAvatar:     json['senderAvatar']?.toString()
                        ?? json['sender']?['profilePictureUrl']?.toString(),
      isMe:             rawSenderId == myUserId,
      text:             json['content']?.toString() ?? json['text']?.toString() ?? '',
      kind:             _parseKind(rawType),
      timestamp:        _parseDate(json['createdAt']),
      status:           _parseStatus(json['status'], initialStatus),
      mediaUrl:         json['mediaUrl']?.toString(),
      mediaType:        json['mediaType']?.toString(),
      mediaMimeType:    json['mediaMimeType']?.toString(),
      mediaSize:        json['mediaSize'] is int ? json['mediaSize'] as int : null,
      mediaDuration:    json['mediaDuration'] is int ? json['mediaDuration'] as int : null,
      waveformPeaks:    waveform,
      linkPreview:      lp,
      replyToId:        json['replyToId']?.toString(),
      replyToText:      json['replyToText']?.toString(),
      replyToSenderName: json['replyToSenderName']?.toString(),
      isDeleted:        json['deletedAt'] != null,
      isEdited:         json['editedAt'] != null,
      reactions:        parsedReactions,
      amount:           (json['amount'] as num?)?.toDouble(),
      currency:         json['currency']?.toString(),
      metadata:         meta,
    );
  }

  static MessageKind _parseKind(String t) {
    switch (t) {
      case 'IMAGE': case 'IMAGE_PROOF': return MessageKind.image;
      case 'VIDEO': return MessageKind.video;
      case 'AUDIO': return MessageKind.audio;
      case 'DOCUMENT': return MessageKind.document;
      case 'LINK': return MessageKind.link;
      case 'STICKER': return MessageKind.sticker;
      case 'SYSTEM': case 'SYSTEM_URGENCY': return MessageKind.system;
      case 'PAYMENT_TRANSFER': return MessageKind.transaction;
      case 'TICKET_LINK': return MessageKind.ticketLink;
      case 'SUSU_EVENT': return MessageKind.susuEvent;
      case 'ADMIN_INTERVENTION': return MessageKind.adminIntervention;
      default: return MessageKind.text;
    }
  }

  static MessageStatus _parseStatus(dynamic s, MessageStatus fallback) {
    switch (s?.toString()) {
      case 'sending':   return MessageStatus.sending;
      case 'sent':      return MessageStatus.sent;
      case 'delivered': return MessageStatus.delivered;
      case 'read':      return MessageStatus.read;
      case 'failed':    return MessageStatus.failed;
      default:          return fallback;
    }
  }

  static DateTime _parseDate(dynamic raw) {
    if (raw == null) return DateTime.now();
    if (raw is String) return DateTime.tryParse(raw)?.toLocal() ?? DateTime.now();
    return DateTime.now();
  }

  /// Create an optimistic placeholder before the server ACK arrives.
  factory ChatMessage.optimistic({
    required String localId,
    required String senderId,
    String? senderUsername,
    required String text,
    MessageKind kind = MessageKind.text,
    String? mediaUrl,
    String? mediaType,
    int? mediaDuration,
    List<int>? waveformPeaks,
    String? replyToId,
    String? replyToText,
    String? replyToSenderName,
  }) {
    return ChatMessage(
      id: '',
      localId: localId,
      senderId: senderId,
      senderUsername: senderUsername,
      isMe: true,
      text: text,
      kind: kind,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      mediaDuration: mediaDuration,
      waveformPeaks: waveformPeaks,
      replyToId: replyToId,
      replyToText: replyToText,
      replyToSenderName: replyToSenderName,
    );
  }

  /// Swap in server data when message_ack arrives.
  ChatMessage upgradeWithAck(String serverId, DateTime serverTs) {
    return copyWith(
      id: serverId,
      timestamp: serverTs,
      status: MessageStatus.sent,
    );
  }

  ChatMessage copyWith({
    String? id, String? localId, String? senderId, String? senderUsername,
    bool? isMe, String? text, MessageKind? kind, DateTime? timestamp,
    MessageStatus? status, String? mediaUrl, String? mediaType,
    int? mediaDuration, List<int>? waveformPeaks, Map<String,dynamic>? linkPreview,
    String? replyToId, String? replyToText, String? replyToSenderName,
    bool? isDeleted, bool? isEdited, Map<String,List<int>>? reactions,
    Map<String,dynamic>? metadata,
  }) {
    return ChatMessage(
      id:                id ?? this.id,
      localId:           localId ?? this.localId,
      senderId:          senderId ?? this.senderId,
      senderUsername:    senderUsername ?? this.senderUsername,
      isMe:              isMe ?? this.isMe,
      text:              text ?? this.text,
      kind:              kind ?? this.kind,
      timestamp:         timestamp ?? this.timestamp,
      status:            status ?? this.status,
      mediaUrl:          mediaUrl ?? this.mediaUrl,
      mediaType:         mediaType ?? this.mediaType,
      mediaDuration:     mediaDuration ?? this.mediaDuration,
      waveformPeaks:     waveformPeaks ?? this.waveformPeaks,
      linkPreview:       linkPreview ?? this.linkPreview,
      replyToId:         replyToId ?? this.replyToId,
      replyToText:       replyToText ?? this.replyToText,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      isDeleted:         isDeleted ?? this.isDeleted,
      isEdited:          isEdited ?? this.isEdited,
      reactions:         reactions ?? this.reactions,
      metadata:          metadata ?? this.metadata,
      mediaSize:         this.mediaSize,
      mediaMimeType:     this.mediaMimeType,
      senderAvatar:      this.senderAvatar,
      forwardedFromUser: this.forwardedFromUser,
      amount:            this.amount,
      currency:          this.currency,
    );
  }
}

