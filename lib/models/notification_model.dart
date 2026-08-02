import 'dart:convert';

enum NotificationCategory {
  general,         // catch-all / legacy
  securityAccount, // logins, password changes, 2FA
  vendorPriority,  // vendor-specific alerts
  adminSystem,     // system/admin alerts
  money,           // deposits, withdrawals, transfers
  social,          // stories, follows, reactions
  chat,            // messages, replies
  system,          // system-wide announcements
}

class AppNotification {
  final String id;
  final String title;
  final String body;
  final NotificationCategory category;
  final Map<String, dynamic>? actionPayload;
  final DateTime createdAt;
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    this.actionPayload,
    required this.createdAt,
    this.isRead = false,
  });

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      title: title,
      body: body,
      category: category,
      actionPayload: actionPayload,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      category: _parseCategory(json['category']),
      actionPayload: _parsePayload(json['actionPayload']),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isRead: json['isRead'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'category': category.name,
        'actionPayload': actionPayload,
        'createdAt': createdAt.toIso8601String(),
        'isRead': isRead,
      };

  static NotificationCategory _parseCategory(dynamic value) {
    if (value is String) {
      final v = value.toUpperCase().replaceAll('-', '_');
      // Map backend category strings → Flutter enum values
      switch (v) {
        case 'SECURITY_ACCOUNT':
        case 'SECURITYACCOUNT':
          return NotificationCategory.securityAccount;
        case 'VENDOR_PRIORITY':
        case 'VENDORPRIORITY':
          return NotificationCategory.vendorPriority;
        case 'ADMIN_SYSTEM':
        case 'ADMINSYSTEM':
        case 'SYSTEM':
          return NotificationCategory.system;
        case 'MONEY':
        case 'DEPOSIT':
        case 'WITHDRAWAL':
        case 'TRANSFER':
        case 'VAULT':
        case 'SUSU':
        case 'AUCTION':
          return NotificationCategory.money;
        case 'CHAT':
        case 'MESSAGE':
          return NotificationCategory.chat;
        case 'SOCIAL':
        case 'STORY':
        case 'FOLLOW':
          return NotificationCategory.social;
        default:
          // Try direct enum name match, fall back to general
          return NotificationCategory.values.firstWhere(
            (e) => e.name.toUpperCase() == v,
            orElse: () => NotificationCategory.general,
          );
      }
    }
    return NotificationCategory.general;
  }

  static Map<String, dynamic>? _parsePayload(dynamic payload) {
    if (payload == null) return null;
    if (payload is Map<String, dynamic>) return payload;
    if (payload is String) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return null;
  }
}
