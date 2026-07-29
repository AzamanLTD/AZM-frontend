// lib/models/chat_message.dart
// AZAMAN PREMIUM — Unified Chat Message Model
// Used by: FriendChatScreen, TransactionChatScreen, GroupChatScreen, TicketWorkspaceScreen


enum MessageStatus { sending, sent, delivered, read, failed }

enum MessageKind {
  text, image, video, audio, document, link,
  sticker, system, transaction, timeRequest, timeApproved,
  timeRejected, ticketLink, susuEvent, adminIntervention,
  // Peer-to-peer money transfers (friend-to-friend chat) — rendered as an
  // animated money card instead of a plain text bubble (2026-07-06).
  peerTransfer, transferRequest,
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
  bool? isStarred;
  bool? isPinned;

  // ── Context-specific ──────────────────────────────────────────────────
  // For transaction messages (money transfer cards)
  final double?  amount;
  final String?  currency;
  // For stickers
  final String?  stickerAssetPath;
  final bool     isAnimatedSticker;
  // For SUSU_EVENT cards
  final Map<String, dynamic>? metadata;

  // ── Disappearing messages (Phase 2) ──────────────────────────────────
  /// If non-null, the message auto-disappears after this many seconds.
  final int? disappearAfterSeconds;
  /// Server-computed expiry timestamp. When this passes, the bubble is
  /// visually removed and the backend hard-deletes the row.
  final DateTime? expiresAt;
  /// True when [expiresAt] has passed — used to hide the bubble locally
  /// before the server sweep catches up.
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);
  /// Remaining seconds until expiry (0 if already expired or no timer).
  int get remainingSeconds {
    if (expiresAt == null) return 0;
    final diff = expiresAt!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

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
    this.isStarred,
    this.isPinned,
    this.amount,
    this.currency,
    this.stickerAssetPath,
    this.isAnimatedSticker = false,
    this.metadata,
    this.disappearAfterSeconds,
    this.expiresAt,
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
      localId:          json['localId']?.toString() ?? json['tempId']?.toString() ?? json['id']?.toString() ?? '',
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
      isStarred:        json['isStarred'] as bool?,
      isPinned:         json['isPinned'] as bool?,
      // Peer-transfer amount/currency live under metadata, not top-level —
      // fall back there so the transfer card always has a number to show.
      amount:           (json['amount'] as num?)?.toDouble()
                        ?? (meta?['amount'] as num?)?.toDouble(),
      currency:         json['currency']?.toString() ?? meta?['currency']?.toString(),
      metadata:         meta,
      disappearAfterSeconds: json['disappearAfterSeconds'] is int
                        ? json['disappearAfterSeconds'] as int
                        : null,
      expiresAt:        json['expiresAt'] != null
                        ? DateTime.tryParse(json['expiresAt'].toString())?.toLocal()
                        : null,
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
      case 'TRANSFER_SENT': case 'TRANSFER_COMPLETED': case 'TRANSFER_DECLINED':
        return MessageKind.peerTransfer;
      case 'TRANSFER_REQUEST': return MessageKind.transferRequest;
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

  /// Serialize to JSON for Socket.IO emission.
  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'localId': localId,
      'senderId': senderId,
      'content': text,
      'createdAt': timestamp.toUtc().toIso8601String(),
      'status': status.name,
    };
    if (mediaUrl != null) m['mediaUrl'] = mediaUrl;
    if (mediaType != null) m['mediaType'] = mediaType;
    if (replyToId != null) m['replyToId'] = replyToId;
    if (replyToText != null) m['replyToText'] = replyToText;
    if (replyToSenderName != null) m['replyToSenderName'] = replyToSenderName;
    if (disappearAfterSeconds != null) m['disappearAfterSeconds'] = disappearAfterSeconds;
    return m;
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
    int? disappearAfterSeconds,
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
      disappearAfterSeconds: disappearAfterSeconds,
      expiresAt: disappearAfterSeconds != null
          ? DateTime.now().add(Duration(seconds: disappearAfterSeconds))
          : null,
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
    bool? isDeleted, bool? isEdited, Map<String,List<int>>? reactions, bool? isStarred, bool? isPinned,
    Map<String,dynamic>? metadata,
    int? disappearAfterSeconds,
    DateTime? expiresAt,
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
      isStarred:        isStarred ?? this.isStarred,
      isPinned:         isPinned ?? this.isPinned,
      metadata:          metadata ?? this.metadata,
      mediaSize:         this.mediaSize,
      mediaMimeType:     this.mediaMimeType,
      senderAvatar:      this.senderAvatar,
      forwardedFromUser: this.forwardedFromUser,
      amount:            this.amount,
      currency:          this.currency,
      disappearAfterSeconds: disappearAfterSeconds ?? this.disappearAfterSeconds,
      expiresAt:         expiresAt ?? this.expiresAt,
    );
  }
}

