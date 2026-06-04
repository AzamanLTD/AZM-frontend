import 'dart:convert';

enum NotificationCategory {
  general,
  securityAccount,
  vendorPriority,
  adminSystem,
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
      final normalized = value.toUpperCase().replaceAll('-', '_');
      return NotificationCategory.values.firstWhere(
        (e) => e.name.toUpperCase().replaceAll('-', '_') == normalized,
        orElse: () => NotificationCategory.general,
      );
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
