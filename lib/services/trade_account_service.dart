// lib/services/trade_account_service.dart
// =============================================================================
// AZAMAN V2 — TRADE ACCOUNT SERVICE (Phase F2-FE)
//
// HTTP client for the /api/trade-accounts/* backend endpoints.
// Handles CRUD for vendor trade accounts (the typed payment method accounts
// that get linked to P2P ads) and the supported-methods discovery endpoint.
//
// Backend endpoints consumed:
//   POST   /api/trade-accounts              — add new account
//   GET    /api/trade-accounts              — list all user accounts
//   GET    /api/trade-accounts/approved     — list only APPROVED accounts
//   GET    /api/trade-accounts/supported-methods — get 11 supported types
//   DELETE /api/trade-accounts/:id          — delete an account
// =============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:azaman/services/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

/// Represents a single vendor trade account (e.g., their Zelle, CashApp, etc.)
class TradeAccount {
  final String id;
  final String userId;
  final String methodType;
  final Map<String, dynamic> accountDetails;
  final String adminVerificationStatus; // PENDING | APPROVED | REJECTED
  final String? verificationScreenshot;
  final String riskLevel;
  final DateTime createdAt;

  const TradeAccount({
    required this.id,
    required this.userId,
    required this.methodType,
    required this.accountDetails,
    required this.adminVerificationStatus,
    this.verificationScreenshot,
    required this.riskLevel,
    required this.createdAt,
  });

  bool get isApproved => adminVerificationStatus == 'APPROVED';
  bool get isPending => adminVerificationStatus == 'PENDING';
  bool get isRejected => adminVerificationStatus == 'REJECTED';

  /// Human-friendly display label (masked for privacy)
  String get displayLabel {
    switch (methodType.toUpperCase()) {
      case 'ZELLE':
        return accountDetails['email'] ?? accountDetails['phone'] ?? 'Zelle';
      case 'CASHAPP':
        return accountDetails['cashtag'] ?? 'CashApp';
      case 'VENMO':
        return accountDetails['username'] ?? accountDetails['phone'] ?? 'Venmo';
      case 'PAYPAL':
        return accountDetails['email'] ?? 'PayPal';
      case 'APPLE_PAY':
        return accountDetails['phone'] ?? 'Apple Pay';
      case 'GOOGLE_PAY':
        return accountDetails['email'] ?? accountDetails['phone'] ?? 'Google Pay';
      case 'WISE':
        return accountDetails['email'] ?? 'Wise';
      case 'REVOLUT':
        return accountDetails['username'] ?? accountDetails['phone'] ?? 'Revolut';
      case 'GIFT_CARD':
        final cardType = accountDetails['cardType'] ?? 'Gift Card';
        final denom = accountDetails['denomination'];
        return denom != null ? '$cardType (\$$denom)' : cardType;
      case 'WESTERN_UNION':
        return accountDetails['fullName'] ?? 'Western Union';
      case 'WIRE_TRANSFER':
        final bank = accountDetails['bankName'] ?? '';
        final acct = accountDetails['accountNumber'] ?? '';
        return '$bank ****${acct.length > 4 ? acct.substring(acct.length - 4) : acct}';
      default:
        return methodType;
    }
  }

  factory TradeAccount.fromJson(Map<String, dynamic> json) {
    return TradeAccount(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      methodType: json['methodType']?.toString() ?? '',
      accountDetails: json['accountDetails'] is Map
          ? Map<String, dynamic>.from(json['accountDetails'] as Map)
          : {},
      adminVerificationStatus:
          json['adminVerificationStatus']?.toString() ?? 'PENDING',
      verificationScreenshot: json['verificationScreenshot'] as String?,
      riskLevel: json['riskLevel']?.toString() ?? 'MEDIUM',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Describes a supported payment method type and its required fields
class SupportedMethod {
  final String type;
  final List<String> requiredFields;
  final List<String> optionalFields;
  final String description;

  const SupportedMethod({
    required this.type,
    this.requiredFields = const [],
    this.optionalFields = const [],
    this.description = '',
  });

  factory SupportedMethod.fromType(String type) {
    // Client-side schema definitions matching backend tradeAccountValidation.js
    switch (type.toUpperCase()) {
      case 'ZELLE':
        return SupportedMethod(
          type: 'ZELLE',
          requiredFields: ['email OR phone'],
          optionalFields: [],
          description: 'Email or phone linked to your Zelle account',
        );
      case 'CASHAPP':
        return SupportedMethod(
          type: 'CASHAPP',
          requiredFields: ['cashtag'],
          optionalFields: [],
          description: '\$Cashtag (e.g., \$YourName)',
        );
      case 'VENMO':
        return SupportedMethod(
          type: 'VENMO',
          requiredFields: ['username OR phone'],
          optionalFields: [],
          description: '@username or phone linked to Venmo',
        );
      case 'PAYPAL':
        return SupportedMethod(
          type: 'PAYPAL',
          requiredFields: ['email'],
          optionalFields: [],
          description: 'Email linked to your PayPal account',
        );
      case 'APPLE_PAY':
        return SupportedMethod(
          type: 'APPLE_PAY',
          requiredFields: ['phone'],
          optionalFields: [],
          description: 'Phone number linked to Apple Pay',
        );
      case 'GOOGLE_PAY':
        return SupportedMethod(
          type: 'GOOGLE_PAY',
          requiredFields: ['email OR phone'],
          optionalFields: [],
          description: 'Email or phone linked to Google Pay',
        );
      case 'WISE':
        return SupportedMethod(
          type: 'WISE',
          requiredFields: ['email'],
          optionalFields: [],
          description: 'Email linked to your Wise account',
        );
      case 'REVOLUT':
        return SupportedMethod(
          type: 'REVOLUT',
          requiredFields: ['username OR phone'],
          optionalFields: [],
          description: '@username or phone linked to Revolut',
        );
      case 'GIFT_CARD':
        return SupportedMethod(
          type: 'GIFT_CARD',
          requiredFields: ['cardType'],
          optionalFields: ['denomination'],
          description: 'Card type (Amazon, iTunes, Steam, etc.)',
        );
      case 'WESTERN_UNION':
        return SupportedMethod(
          type: 'WESTERN_UNION',
          requiredFields: ['fullName', 'country'],
          optionalFields: ['city'],
          description: 'Recipient full name and country',
        );
      case 'WIRE_TRANSFER':
        return SupportedMethod(
          type: 'WIRE_TRANSFER',
          requiredFields: ['bankName', 'accountNumber'],
          optionalFields: ['routingNumber', 'swift'],
          description: 'Bank name, account number, and routing/SWIFT',
        );
      default:
        return SupportedMethod(type: type, description: 'Unknown method');
    }
  }

  /// All 11 supported types
  static const List<String> allTypes = [
    'ZELLE',
    'CASHAPP',
    'VENMO',
    'PAYPAL',
    'APPLE_PAY',
    'GOOGLE_PAY',
    'WISE',
    'REVOLUT',
    'GIFT_CARD',
    'WESTERN_UNION',
    'WIRE_TRANSFER',
  ];

  /// Human-readable display name for a method type
  static String displayName(String type) {
    switch (type.toUpperCase()) {
      case 'ZELLE':
        return 'Zelle';
      case 'CASHAPP':
        return 'CashApp';
      case 'VENMO':
        return 'Venmo';
      case 'PAYPAL':
        return 'PayPal';
      case 'APPLE_PAY':
        return 'Apple Pay';
      case 'GOOGLE_PAY':
        return 'Google Pay';
      case 'WISE':
        return 'Wise';
      case 'REVOLUT':
        return 'Revolut';
      case 'GIFT_CARD':
        return 'Gift Card';
      case 'WESTERN_UNION':
        return 'Western Union';
      case 'WIRE_TRANSFER':
        return 'Wire Transfer';
      default:
        return type;
    }
  }

  /// Icon for each method type
  static String iconForType(String type) {
    switch (type.toUpperCase()) {
      case 'ZELLE':
        return 'zelle';
      case 'CASHAPP':
        return 'cashapp';
      case 'VENMO':
        return 'venmo';
      case 'PAYPAL':
        return 'paypal';
      case 'APPLE_PAY':
        return 'apple_pay';
      case 'GOOGLE_PAY':
        return 'google_pay';
      case 'WISE':
        return 'wise';
      case 'REVOLUT':
        return 'revolut';
      case 'GIFT_CARD':
        return 'gift_card';
      case 'WESTERN_UNION':
        return 'western_union';
      case 'WIRE_TRANSFER':
        return 'wire_transfer';
      default:
        return 'unknown';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class TradeAccountService {
  /// POST /api/trade-accounts — add a new trade account
  static Future<TradeAccount> addTradeAccount({
    required String methodType,
    required Map<String, dynamic> accountDetails,
    required String verificationScreenshot,
    String riskLevel = 'MEDIUM',
  }) async {
    final response = await apiClient.post('/trade-accounts', {
      'methodType': methodType.toUpperCase(),
      'accountDetails': accountDetails,
      'verificationScreenshot': verificationScreenshot,
      'riskLevel': riskLevel,
    });

    if (response.statusCode == 201) {
      final body = jsonDecode(response.body);
      return TradeAccount.fromJson(body['tradeAccount']);
    }

    final error = _parseError(response);
    throw Exception(error);
  }

  /// GET /api/trade-accounts — list all user's trade accounts
  static Future<List<TradeAccount>> getTradeAccounts() async {
    final response = await apiClient.get('/trade-accounts');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final List<dynamic> raw = body['accounts'] ?? [];
      return raw.map((e) => TradeAccount.fromJson(e as Map<String, dynamic>)).toList();
    }

    throw Exception(_parseError(response));
  }

  /// GET /api/trade-accounts/approved — list only APPROVED accounts
  static Future<List<TradeAccount>> getApprovedAccounts() async {
    final response = await apiClient.get('/trade-accounts/approved');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final List<dynamic> raw = body['accounts'] ?? [];
      return raw.map((e) => TradeAccount.fromJson(e as Map<String, dynamic>)).toList();
    }

    throw Exception(_parseError(response));
  }

  /// GET /api/trade-accounts/supported-methods — get supported payment types
  static Future<List<String>> getSupportedMethods() async {
    final response = await apiClient.get('/trade-accounts/supported-methods');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final List<dynamic> raw = body['methods'] ?? [];
      return raw.map((e) => e.toString()).toList();
    }

    throw Exception(_parseError(response));
  }

  /// DELETE /api/trade-accounts/:id — delete a trade account
  static Future<void> deleteTradeAccount(String id) async {
    final response = await apiClient.delete('/trade-accounts/$id');

    if (response.statusCode == 200) return;
    throw Exception(_parseError(response));
  }

  static String _parseError(dynamic response) {
    try {
      final body = jsonDecode(response.body);
      return body['message']?.toString() ?? 'Request failed (${response.statusCode})';
    } catch (_) {
      return 'Request failed (${response.statusCode})';
    }
  }
}
