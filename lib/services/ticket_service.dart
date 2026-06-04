// =============================================================================
// TICKET SERVICE — Phase UI-4 (2026-05-26)
//
// REST client for the Tickets Engine. Wraps:
//   • POST   /api/tickets                  — createTicket
//   • GET    /api/tickets                  — listTickets (paginated)
//   • GET    /api/tickets/:id              — getTicket
//   • POST   /api/tickets/:id/messages     — sendMessage
//   • PATCH  /api/tickets/:id/status       — changeStatus
//   • POST   /api/tickets/:id/presence     — pingPresence
//
// All requests authenticated via the shared `apiClient` (JWT bearer).
// =============================================================================

import 'dart:convert';

import 'package:azaman/services/api_client.dart';

enum TicketType { buy, sell, escrow, serviceSwap }
enum TicketStatus { open, closed, cancelled }

extension TicketTypeWire on TicketType {
  String get wire {
    switch (this) {
      case TicketType.buy: return 'BUY';
      case TicketType.sell: return 'SELL';
      case TicketType.escrow: return 'ESCROW';
      case TicketType.serviceSwap: return 'SERVICE_SWAP';
    }
  }

  String get label {
    switch (this) {
      case TicketType.buy: return 'Buy';
      case TicketType.sell: return 'Sell';
      case TicketType.escrow: return 'Escrow';
      case TicketType.serviceSwap: return 'Service Swap';
    }
  }

  static TicketType fromWire(String wire) {
    switch (wire.toUpperCase()) {
      case 'BUY': return TicketType.buy;
      case 'SELL': return TicketType.sell;
      case 'ESCROW': return TicketType.escrow;
      case 'SERVICE_SWAP': return TicketType.serviceSwap;
      default: return TicketType.buy;
    }
  }
}

extension TicketStatusWire on TicketStatus {
  String get wire {
    switch (this) {
      case TicketStatus.open: return 'OPEN';
      case TicketStatus.closed: return 'CLOSED';
      case TicketStatus.cancelled: return 'CANCELLED';
    }
  }

  String get label {
    switch (this) {
      case TicketStatus.open: return 'Open';
      case TicketStatus.closed: return 'Closed';
      case TicketStatus.cancelled: return 'Cancelled';
    }
  }

  static TicketStatus fromWire(String wire) {
    switch (wire.toUpperCase()) {
      case 'OPEN': return TicketStatus.open;
      case 'CLOSED': return TicketStatus.closed;
      case 'CANCELLED': return TicketStatus.cancelled;
      default: return TicketStatus.open;
    }
  }
}

class Ticket {
  final String id;
  final String friendshipId;
  final int creatorId;
  final int counterpartyId;
  final String name;
  final TicketType type;
  final double targetAmount;
  final String targetCurrency;
  final String? memo;
  final TicketStatus status;
  final DateTime createdAt;
  final DateTime lastActivityAt;
  final DateTime? closedAt;
  final DateTime? cancelledAt;

  const Ticket({
    required this.id,
    required this.friendshipId,
    required this.creatorId,
    required this.counterpartyId,
    required this.name,
    required this.type,
    required this.targetAmount,
    required this.targetCurrency,
    required this.status,
    required this.createdAt,
    required this.lastActivityAt,
    this.memo,
    this.closedAt,
    this.cancelledAt,
  });

  factory Ticket.fromJson(Map<String, dynamic> json) {
    final amount = json['targetAmount'];
    return Ticket(
      id: json['id'].toString(),
      friendshipId: json['friendshipId'].toString(),
      creatorId: json['creatorId'] is int
          ? json['creatorId']
          : int.tryParse(json['creatorId'].toString()) ?? 0,
      counterpartyId: json['counterpartyId'] is int
          ? json['counterpartyId']
          : int.tryParse(json['counterpartyId'].toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      type: TicketTypeWire.fromWire((json['type'] ?? 'BUY').toString()),
      targetAmount: amount is num
          ? amount.toDouble()
          : double.tryParse(amount.toString()) ?? 0.0,
      targetCurrency: (json['targetCurrency'] ?? 'USD').toString(),
      memo: json['memo']?.toString(),
      status: TicketStatusWire.fromWire((json['status'] ?? 'OPEN').toString()),
      createdAt: DateTime.parse(json['createdAt'].toString()),
      lastActivityAt: DateTime.parse(
          (json['lastActivityAt'] ?? json['createdAt']).toString()),
      closedAt: json['closedAt'] != null
          ? DateTime.tryParse(json['closedAt'].toString())
          : null,
      cancelledAt: json['cancelledAt'] != null
          ? DateTime.tryParse(json['cancelledAt'].toString())
          : null,
    );
  }
}

class TicketMessageRow {
  final String id;
  final String ticketId;
  final int senderId;
  final String type;
  final String? content;
  final Map<String, dynamic>? metadata;
  final String? mediaUrl;
  final String? mediaType;
  final String? mediaMimeType;
  final int? mediaSize;
  final int? mediaDuration;
  final List<int>? mediaWaveformPeaks;
  final Map<String, dynamic>? linkPreview;
  final DateTime createdAt;
  final Map<String, dynamic>? sender;

  const TicketMessageRow({
    required this.id,
    required this.ticketId,
    required this.senderId,
    required this.type,
    required this.createdAt,
    this.content,
    this.metadata,
    this.mediaUrl,
    this.mediaType,
    this.mediaMimeType,
    this.mediaSize,
    this.mediaDuration,
    this.mediaWaveformPeaks,
    this.linkPreview,
    this.sender,
  });

  factory TicketMessageRow.fromJson(Map<String, dynamic> json) {
    final waveform = json['mediaWaveformPeaks'];
    return TicketMessageRow(
      id: json['id'].toString(),
      ticketId: (json['ticketId'] ?? '').toString(),
      senderId: json['senderId'] is int
          ? json['senderId']
          : int.tryParse(json['senderId'].toString()) ?? 0,
      type: (json['type'] ?? 'TEXT').toString().toUpperCase(),
      content: json['content']?.toString(),
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : null,
      mediaUrl: json['mediaUrl']?.toString(),
      mediaType: json['mediaType']?.toString(),
      mediaMimeType: json['mediaMimeType']?.toString(),
      mediaSize: json['mediaSize'] is int ? json['mediaSize'] as int : null,
      mediaDuration:
          json['mediaDuration'] is int ? json['mediaDuration'] as int : null,
      mediaWaveformPeaks:
          waveform is List ? waveform.whereType<int>().toList() : null,
      linkPreview: json['linkPreview'] is Map<String, dynamic>
          ? json['linkPreview'] as Map<String, dynamic>
          : null,
      createdAt: DateTime.parse(json['createdAt'].toString()),
      sender: json['sender'] is Map<String, dynamic>
          ? json['sender'] as Map<String, dynamic>
          : null,
    );
  }
}

class TicketListResponse {
  final List<Ticket> tickets;
  final bool hasMore;
  final String? nextCursor;
  const TicketListResponse({
    required this.tickets,
    required this.hasMore,
    this.nextCursor,
  });
}

class TicketDetailResponse {
  final Ticket ticket;
  final List<TicketMessageRow> messages;
  const TicketDetailResponse({required this.ticket, required this.messages});
}

class TicketService {
  TicketService._();
  static final TicketService instance = TicketService._();

  Future<Ticket> createTicket({
    required String friendshipId,
    required String name,
    required TicketType type,
    required double targetAmount,
    required String targetCurrency,
    String? memo,
  }) async {
    final res = await apiClient.post('/tickets', {
      'friendshipId': friendshipId,
      'name': name,
      'type': type.wire,
      'targetAmount': targetAmount,
      'targetCurrency': targetCurrency.toUpperCase(),
      if (memo != null && memo.isNotEmpty) 'memo': memo,
    });
    final body = jsonDecode(res.body);
    if (res.statusCode != 201 || body['ticket'] == null) {
      throw TicketServiceException(
        statusCode: res.statusCode,
        message: body['message']?.toString() ?? 'Create failed',
      );
    }
    return Ticket.fromJson(body['ticket'] as Map<String, dynamic>);
  }

  Future<TicketListResponse> listTickets({
    required String friendshipId,
    TicketStatus? status,
    String? cursor,
    int limit = 50,
  }) async {
    final params = <String, String>{
      'friendshipId': friendshipId,
      'limit': '$limit',
      if (status != null) 'status': status.wire,
      if (cursor != null) 'cursor': cursor,
    };
    final query = params.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final res = await apiClient.get('/tickets?$query');
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw TicketServiceException(
        statusCode: res.statusCode,
        message: body['message']?.toString() ?? 'List failed',
      );
    }
    final raw = (body['tickets'] as List? ?? const []);
    final tickets = raw
        .whereType<Map<String, dynamic>>()
        .map(Ticket.fromJson)
        .toList();
    return TicketListResponse(
      tickets: tickets,
      hasMore: body['hasMore'] == true,
      nextCursor: body['nextCursor']?.toString(),
    );
  }

  Future<TicketDetailResponse> getTicket(String id) async {
    final res = await apiClient.get('/tickets/$id');
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw TicketServiceException(
        statusCode: res.statusCode,
        message: body['message']?.toString() ?? 'Detail failed',
      );
    }
    final ticket = Ticket.fromJson(body['ticket'] as Map<String, dynamic>);
    final msgs = (body['messages'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TicketMessageRow.fromJson)
        .toList();
    return TicketDetailResponse(ticket: ticket, messages: msgs);
  }

  Future<TicketMessageRow> sendMessage({
    required String ticketId,
    String? content,
    String? type,
    Map<String, dynamic>? metadata,
    String? mediaUrl,
    String? mediaType,
    String? mediaMimeType,
    int? mediaSize,
    int? mediaDuration,
    List<int>? mediaWaveformPeaks,
    Map<String, dynamic>? linkPreview,
  }) async {
    final res = await apiClient.post('/tickets/$ticketId/messages', {
      if (content != null) 'content': content,
      if (type != null) 'type': type,
      if (metadata != null) 'metadata': metadata,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (mediaType != null) 'mediaType': mediaType,
      if (mediaMimeType != null) 'mediaMimeType': mediaMimeType,
      if (mediaSize != null) 'mediaSize': mediaSize,
      if (mediaDuration != null) 'mediaDuration': mediaDuration,
      if (mediaWaveformPeaks != null) 'mediaWaveformPeaks': mediaWaveformPeaks,
      if (linkPreview != null) 'linkPreview': linkPreview,
    });
    final body = jsonDecode(res.body);
    if (res.statusCode != 201 || body['message'] == null) {
      throw TicketServiceException(
        statusCode: res.statusCode,
        message: body['message']?.toString() ?? 'Send failed',
      );
    }
    return TicketMessageRow.fromJson(body['message'] as Map<String, dynamic>);
  }

  Future<Ticket> changeStatus({
    required String ticketId,
    required TicketStatus status,
  }) async {
    final res = await apiClient.patch(
      '/tickets/$ticketId/status',
      body: {'status': status.wire},
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200 || body['ticket'] == null) {
      throw TicketServiceException(
        statusCode: res.statusCode,
        message: body['message']?.toString() ?? 'Status change failed',
      );
    }
    return Ticket.fromJson(body['ticket'] as Map<String, dynamic>);
  }

  /// Tell the server (and via socket fanout, the counterparty) that the
  /// caller just opened or closed the ticket workspace. Used to render the
  /// "the other party is currently viewing the ticket window" banner.
  Future<void> pingPresence({
    required String ticketId,
    required bool viewing,
  }) async {
    try {
      await apiClient.post('/tickets/$ticketId/presence', {'viewing': viewing});
    } catch (_) {
      // Presence is best-effort. A failed ping should never block UI.
    }
  }
}

class TicketServiceException implements Exception {
  final int statusCode;
  final String message;
  const TicketServiceException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() => 'TicketServiceException($statusCode): $message';
}
