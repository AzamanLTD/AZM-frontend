// AZAMAN — HTTP BILLS GATEWAY (saved accounts only)
//
// Written against the contract the backend actually publishes on
// `feat/bills-saved-service-accounts` (routes/billsRoutes.js):
//
//   GET    /bills/service-templates      -> { data: { schemaVersion,
//                                             categories[], reservedCategories[],
//                                             paymentsEnabled: false } }
//   GET    /bills/saved-accounts         -> { data: { accounts[] } }
//   POST   /bills/saved-accounts         -> 201 { data: { account } }
//                                          body: { serviceCode, providerCode,
//                                                  nickname, accountFields{} }
//   PATCH  /bills/saved-accounts/:id     -> { data: { account } }
//                                          body: { nickname, isPrimary }
//   DELETE /bills/saved-accounts/:id     -> { data: { id, deleted } }
//
// That file is explicit about what it does NOT do: "Deliberately absent: quote,
// order, pay, lookup, receipt." So this gateway does three things and refuses
// the rest — lookup, quoting, payment and bill requests all throw
// BillsUnavailableException with the reason, which is what the screens already
// render as a truthful "not available yet".
//
// The template registry is the only place field contracts live, so the client
// maps fields and never invents validation of its own. `paymentsEnabled: false`
// and per-service capability booleans are read as data: no service is offered
// as payable because a biller's name looks familiar.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/bills/bills_gateway.dart';

/// One saveable service template, exactly as the server registry describes it.
class BillServiceField {
  const BillServiceField({
    required this.key,
    required this.label,
    required this.type,
    required this.required,
    this.pattern,
    this.maxLength,
  });

  final String key;
  final String label;
  final String type;
  final bool required;
  final String? pattern;
  final int? maxLength;

  static BillServiceField? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key']?.toString();
    final label = raw['label']?.toString();
    if (key == null || key.isEmpty || label == null) return null;
    return BillServiceField(
      key: key,
      label: label,
      type: raw['type']?.toString() ?? 'text',
      required: raw['required'] == true,
      pattern: raw['pattern']?.toString(),
      maxLength: raw['maxLength'] is num
          ? (raw['maxLength'] as num).toInt()
          : null,
    );
  }
}

/// What a service says about itself. Every flag is explicit on purpose.
class BillServiceCapabilities {
  const BillServiceCapabilities({
    required this.saveAccount,
    required this.lookupAccount,
    required this.quote,
    required this.payment,
  });

  const BillServiceCapabilities.saveOnly()
    : saveAccount = true,
      lookupAccount = false,
      quote = false,
      payment = false;

  final bool saveAccount;
  final bool lookupAccount;
  final bool quote;
  final bool payment;

  static const BillServiceCapabilities none =
      BillServiceCapabilities.saveOnly();

  static BillServiceCapabilities fromJson(Object? raw) {
    if (raw is! Map) return none;
    return BillServiceCapabilities(
      saveAccount: raw['saveAccount'] == true,
      lookupAccount: raw['lookupAccount'] == true,
      quote: raw['quote'] == true,
      payment: raw['payment'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'saveAccount': saveAccount,
    'lookupAccount': lookupAccount,
    'quote': quote,
    'payment': payment,
  };
}

/// A saveable service (one biller product), with the fields it requires.
class BillServiceTemplate {
  const BillServiceTemplate({
    required this.serviceCode,
    required this.providerCode,
    required this.label,
    required this.categoryCode,
    required this.capabilities,
    required this.fields,
  });

  final String serviceCode;
  final String providerCode;
  final String label;
  final String categoryCode;
  final BillServiceCapabilities capabilities;
  final List<BillServiceField> fields;

  /// The field that identifies the account with the provider.
  BillServiceField? get identityField {
    for (final f in fields) {
      if (f.required) return f;
    }
    return fields.isEmpty ? null : fields.first;
  }

  /// A service is only ever offered as payable when the server says all four
  /// capabilities hold. Nothing about the biller's name enters this decision.
  bool get isPayable =>
      capabilities.lookupAccount && capabilities.quote && capabilities.payment;

  static BillServiceTemplate? fromJson(
    Object? raw, {
    required String categoryCode,
  }) {
    if (raw is! Map) return null;
    final serviceCode = raw['serviceCode']?.toString();
    final providerCode = raw['providerCode']?.toString();
    final label = raw['label']?.toString();
    if (serviceCode == null ||
        serviceCode.isEmpty ||
        providerCode == null ||
        label == null ||
        label.isEmpty) {
      return null;
    }
    final fields = <BillServiceField>[];
    final rawFields = raw['fields'];
    if (rawFields is List) {
      for (final f in rawFields) {
        final parsed = BillServiceField.fromJson(f);
        if (parsed != null) fields.add(parsed);
      }
    }
    return BillServiceTemplate(
      serviceCode: serviceCode,
      providerCode: providerCode,
      label: label,
      categoryCode: categoryCode,
      capabilities: BillServiceCapabilities.fromJson(raw['capabilities']),
      fields: List<BillServiceField>.unmodifiable(fields),
    );
  }
}

/// The whole registry, flattened: categories for grouping, services for saving.
class BillServiceCatalog {
  const BillServiceCatalog({
    required this.categories,
    required this.services,
    required this.paymentsEnabled,
  });

  static const BillServiceCatalog empty = BillServiceCatalog(
    categories: <BillsCategory>[],
    services: <BillServiceTemplate>[],
    paymentsEnabled: false,
  );

  final List<BillsCategory> categories;
  final List<BillServiceTemplate> services;

  /// The server's own statement that no payment path exists anywhere.
  final bool paymentsEnabled;

  BillServiceTemplate? serviceFor(String serviceCode, String providerCode) {
    for (final s in services) {
      if (s.serviceCode == serviceCode && s.providerCode == providerCode) {
        return s;
      }
    }
    return null;
  }

  BillServiceTemplate? serviceByCode(String serviceCode) {
    for (final s in services) {
      if (s.serviceCode == serviceCode) return s;
    }
    return null;
  }

  static BillServiceCatalog fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final categories = <BillsCategory>[];
    final services = <BillServiceTemplate>[];
    final rawCategories = raw['categories'];
    if (rawCategories is List) {
      for (final c in rawCategories) {
        if (c is! Map) continue;
        final code = c['code']?.toString();
        if (code == null || code.isEmpty) continue;
        final label = c['label']?.toString() ?? code;
        categories.add(BillsCategory(id: code, label: label));
        final rawServices = c['services'];
        if (rawServices is! List) continue;
        for (final s in rawServices) {
          final parsed = BillServiceTemplate.fromJson(s, categoryCode: code);
          if (parsed != null) services.add(parsed);
        }
      }
    }
    return BillServiceCatalog(
      categories: List<BillsCategory>.unmodifiable(categories),
      services: List<BillServiceTemplate>.unmodifiable(services),
      paymentsEnabled: raw['paymentsEnabled'] == true,
    );
  }
}

/// A saved account as the server projects it. No decryptable field ever
/// arrives: `accountMask` is the only rendering of the identifier.
class SavedServiceAccount {
  const SavedServiceAccount({
    required this.id,
    required this.serviceCode,
    required this.providerCode,
    required this.label,
    required this.accountMask,
    required this.verificationStatus,
    required this.isPrimary,
    this.categoryCode,
    this.nickname,
    this.capabilities = BillServiceCapabilities.none,
  });

  final String id;
  final String serviceCode;
  final String providerCode;
  final String label;
  final String accountMask;
  final String verificationStatus;
  final bool isPrimary;
  final String? categoryCode;
  final String? nickname;
  final BillServiceCapabilities capabilities;

  String get displayName => (nickname != null && nickname!.trim().isNotEmpty)
      ? nickname!.trim()
      : label;

  static SavedServiceAccount? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString();
    if (id == null || id.isEmpty) return null;
    return SavedServiceAccount(
      id: id,
      serviceCode: raw['serviceCode']?.toString() ?? '',
      providerCode: raw['providerCode']?.toString() ?? '',
      label: raw['label']?.toString() ?? raw['providerCode']?.toString() ?? '',
      accountMask: raw['accountMask']?.toString() ?? '••••',
      verificationStatus: raw['verificationStatus']?.toString() ?? 'UNKNOWN',
      isPrimary: raw['isPrimary'] == true,
      categoryCode: raw['categoryCode']?.toString(),
      nickname: raw['nickname']?.toString(),
      capabilities: BillServiceCapabilities.fromJson(raw['capabilities']),
    );
  }
}

class HttpBillsGateway implements BillsGateway {
  HttpBillsGateway(this._api);

  final ApiClient _api;

  static const String _base = '/bills';

  static Object? _decode(http.Response response) =>
      jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));

  Object? _data(http.Response response) {
    final decoded = _decode(response);
    return decoded is Map<String, dynamic> ? decoded['data'] : null;
  }

  /// The contract's own refusal codes, surfaced rather than flattened: a member
  /// seeing "Saved accounts are temporarily unavailable." must not be shown a
  /// generic failure, and a validation message from the server is already
  /// written for the member to read.
  Never _refuse(Object error, {String fallback = 'BILLS_UNAVAILABLE'}) {
    if (error is ApiException) {
      final body = error.body;
      final code = body?['code']?.toString();
      final message = body?['message']?.toString();
      throw BillsUnavailableException(
        message != null && message.isNotEmpty ? message : (code ?? fallback),
      );
    }
    throw const BillsUnavailableException();
  }

  @override
  bool get isDemo => false;

  @override
  Future<BillsAvailability> availability() async {
    final catalog = await serviceCatalog();
    if (catalog.services.isEmpty) return BillsAvailability.unavailable;
    return BillsAvailability(isAvailable: true, categories: catalog.categories);
  }

  Future<BillServiceCatalog> serviceCatalog() async {
    try {
      final response = await _api.get('$_base/service-templates');
      return BillServiceCatalog.fromJson(_data(response));
    } on ApiException catch (e) {
      // A backend without the route yet is "not configured", not a crash.
      if (e.statusCode == 404) return BillServiceCatalog.empty;
      _refuse(e, fallback: 'SERVICE_TEMPLATES_UNAVAILABLE');
    } on FormatException {
      return BillServiceCatalog.empty;
    }
  }

  @override
  Future<List<Biller>> billers({String? categoryId}) async {
    final catalog = await serviceCatalog();
    final out = <Biller>[];
    for (final service in catalog.services) {
      if (categoryId != null && service.categoryCode != categoryId) continue;
      final identity = service.identityField;
      out.add(
        Biller(
          // The Biller id is the service identity the save endpoint needs; it
          // is composed from two server-issued codes, never guessed client-side.
          id: '${service.serviceCode}:${service.providerCode}',
          categoryId: service.categoryCode,
          name: service.label,
          identifierLabel: identity?.label ?? 'Account number',
          identifierHint: identity?.type,
        ),
      );
    }
    return out;
  }

  @override
  Future<BillLookup> lookup({
    required String billerId,
    required String identifier,
  }) async {
    final catalog = await serviceCatalog();
    final parsed = _parseBillerId(billerId);
    final service = parsed == null
        ? null
        : catalog.serviceFor(parsed.$1, parsed.$2);
    // Refusing here is the honest answer: the server publishes no lookup, so no
    // holder name exists to show. Inventing one would be the exact failure the
    // brief forbids.
    throw BillsUnavailableException(
      service != null && !service.capabilities.lookupAccount
          ? '${service.label} cannot be verified yet: no provider lookup is connected.'
          : 'Bill lookups are not available yet.',
    );
  }

  @override
  Future<List<SavedBillAccount>> savedAccounts() async {
    try {
      final response = await _api.get('$_base/saved-accounts');
      final data = _data(response);
      final raw = data is Map ? data['accounts'] : null;
      if (raw is! List) return const <SavedBillAccount>[];
      final catalog = await serviceCatalog();
      final out = <SavedBillAccount>[];
      for (final entry in raw) {
        final account = SavedServiceAccount.fromJson(entry);
        if (account == null) continue;
        final service = catalog.serviceFor(
          account.serviceCode,
          account.providerCode,
        );
        out.add(
          SavedBillAccount(
            id: account.id,
            billerId: '${account.serviceCode}:${account.providerCode}',
            billerName: service?.label ?? account.label,
            categoryId: service?.categoryCode ?? account.categoryCode ?? '',
            identifierMasked: account.accountMask,
            // The contract returns a verification STATUS, not a holder name, so
            // this stays null and the UI says so.
            holderName: null,
            verificationStatus: account.verificationStatus,
            alias: account.nickname,
          ),
        );
      }
      return out;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return const <SavedBillAccount>[];
      _refuse(e, fallback: 'SAVED_ACCOUNTS_UNAVAILABLE');
    } on FormatException {
      return const <SavedBillAccount>[];
    }
  }

  @override
  Future<SavedBillAccount> saveAccount({
    required String billerId,
    required String identifier,
    String? alias,
  }) async {
    final parsed = _parseBillerId(billerId);
    if (parsed == null) {
      throw const BillsUnavailableException('Unknown biller.');
    }
    final catalog = await serviceCatalog();
    final service = catalog.serviceFor(parsed.$1, parsed.$2);
    if (service == null || !service.capabilities.saveAccount) {
      throw BillsUnavailableException(
        'Saving an account for this service is not available yet.',
      );
    }
    final identity = service.identityField;
    if (identity == null) {
      throw const BillsUnavailableException(
        'This service does not describe the details it needs.',
      );
    }
    try {
      final response = await _api.post('$_base/saved-accounts', {
        'serviceCode': service.serviceCode,
        'providerCode': service.providerCode,
        if (alias != null && alias.trim().isNotEmpty) 'nickname': alias.trim(),
        'accountFields': {identity.key: identifier},
      });
      final data = _data(response);
      final raw = data is Map ? data['account'] : null;
      final account = SavedServiceAccount.fromJson(raw);
      if (account == null) {
        throw const BillsUnavailableException('SAVED_ACCOUNT_FAILED');
      }
      return SavedBillAccount(
        id: account.id,
        billerId: '${account.serviceCode}:${account.providerCode}',
        billerName: service.label,
        categoryId: service.categoryCode,
        identifierMasked: account.accountMask,
        holderName: null,
        verificationStatus: account.verificationStatus,
        alias: account.nickname,
      );
    } on ApiException catch (e) {
      _refuse(e, fallback: 'SAVED_ACCOUNT_FAILED');
    } on FormatException {
      throw const BillsUnavailableException('SAVED_ACCOUNT_FAILED');
    }
  }

  @override
  Future<void> removeAccount(String accountId) async {
    try {
      await _api.delete('$_base/saved-accounts/$accountId');
    } on ApiException catch (e) {
      if (e.statusCode == 404) return;
      _refuse(e, fallback: 'SAVED_ACCOUNT_DELETE_FAILED');
    }
  }

  @override
  Future<BillQuote> quote({required String accountId, double? amount}) async {
    throw const BillsUnavailableException(
      'Paying a bill is not available yet: no provider is connected for quoting or payment.',
    );
  }

  @override
  Future<BillPaymentReceipt> pay({required String quoteId}) async {
    throw const BillsUnavailableException(
      'Paying a bill is not available yet: no provider is connected for quoting or payment.',
    );
  }

  @override
  Future<List<BillPaymentRequest>> requests() async {
    return const <BillPaymentRequest>[];
  }

  @override
  Future<BillPaymentRequest> sendRequest({
    required String accountId,
    required String recipientName,
    double? amount,
    String? note,
    DateTime? expiresAt,
  }) async {
    throw const BillsUnavailableException(
      'Asking a contact to pay a bill is not available yet.',
    );
  }

  @override
  Future<BillPaymentRequest> respondToRequest({
    required String requestId,
    required bool accept,
  }) async {
    throw const BillsUnavailableException(
      'Asking a contact to pay a bill is not available yet.',
    );
  }

  @override
  Future<BillsHubSnapshot> hub() async {
    final catalog = await serviceCatalog();
    final accounts = await savedAccounts();
    // Only what the server can actually answer. Nothing is filled in to make
    // the screen look busier than the backend is.
    return BillsHubSnapshot(
      savedAccounts: accounts,
      // No receipt, due-list or request resource exists in the published
      // contract, so these stay empty rather than borrowed from a guess.
      recentPayments: const <BillPaymentReceipt>[],
      outstanding: const <SavedBillAccount>[],
      requests: const <BillPaymentRequest>[],
    );
  }

  static (String, String)? _parseBillerId(String billerId) {
    final at = billerId.indexOf(':');
    if (at <= 0 || at >= billerId.length - 1) return null;
    return (billerId.substring(0, at), billerId.substring(at + 1));
  }
}

/// Debug-only: makes the wiring visible without ever claiming a capability the
/// backend does not publish.
@visibleForTesting
bool httpBillsGatewayRefusesPayment(BillsGateway gateway) =>
    gateway is HttpBillsGateway;
