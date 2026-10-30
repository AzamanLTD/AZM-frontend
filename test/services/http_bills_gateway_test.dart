// THE SAVED-ACCOUNT HALF OF BILLS, WIRED TO THE CONTRACT THAT EXISTS.
//
// Backend: AzamanLTD/AZM-backend, branch feat/bills-saved-service-accounts,
// routes/billsRoutes.js. That file says in its own header what it does NOT do:
// "Deliberately absent: quote, order, pay, lookup, receipt."
//
// So these contracts check two things at once: that the gateway speaks the
// published shapes exactly, and that it refuses the capabilities the backend
// does not publish — including the temptation to synthesise a holder name from
// the member's own typing.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/bills/bills_gateway.dart';
import 'package:azaman/services/bills/http_bills_gateway.dart';

/// A transport that answers from a table and records what was asked.
class _ScriptedApiClient extends ApiClient {
  _ScriptedApiClient(this.routes);

  final Map<String, http.Response Function()> routes;
  final List<String> calls = <String>[];
  final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];

  http.Response _answer(String key) {
    calls.add(key);
    final handler = routes[key];
    final response = handler == null
        ? http.Response(
            jsonEncode({'success': false, 'code': 'NOT_FOUND'}),
            404,
          )
        : handler();
    // The real ApiClient raises on an error status, so the scripted transport
    // must too: otherwise a test could pass on a path production never takes.
    if (response.statusCode >= 400) {
      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        decoded = null;
      }
      throw ApiException(
        message: decoded is Map
            ? (decoded['message']?.toString() ?? 'Request failed.')
            : 'Request failed.',
        statusCode: response.statusCode,
        code: decoded is Map ? decoded['code']?.toString() : null,
        body: decoded is Map<String, dynamic> ? decoded : null,
      );
    }
    return response;
  }

  @override
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async => _answer('GET $endpoint');

  @override
  Future<http.Response> post(
    String endpoint,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    bool requireAuth = true,
    String? idempotencyKey,
  }) async {
    bodies.add(body);
    return _answer('POST $endpoint');
  }

  @override
  Future<http.Response> delete(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async => _answer('DELETE $endpoint');
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Verbatim shape of `publicTemplates()` in services/bills/serviceRegistry.js.
Map<String, dynamic> _templatesPayload() => {
  'success': true,
  'data': {
    'schemaVersion': '1',
    'categories': [
      {
        'code': 'ELECTRICITY',
        'label': 'Electricity',
        'services': [
          {
            'serviceCode': 'ECG_PREPAID',
            'providerCode': 'ECG',
            'label': 'ECG prepaid',
            'capabilities': {
              'saveAccount': true,
              'lookupAccount': false,
              'quote': false,
              'payment': false,
            },
            'providerAdapter': null,
            'fields': [
              {
                'key': 'meterNumber',
                'label': 'Meter number',
                'type': 'identifier',
                'required': true,
                'pattern': r'^\d{6,20}$',
                'maxLength': 20,
              },
            ],
          },
        ],
      },
      {
        'code': 'AIRTIME_DATA',
        'label': 'Airtime & Data',
        'services': [
          {
            'serviceCode': 'AIRTIME',
            'providerCode': 'MTN',
            'label': 'MTN airtime',
            'capabilities': {
              'saveAccount': true,
              'lookupAccount': false,
              'quote': false,
              'payment': false,
            },
            'providerAdapter': null,
            'fields': [
              {
                'key': 'recipientPhone',
                'label': 'Phone number',
                'type': 'phone',
                'required': true,
                'pattern': r'^(0\d{9}|\+233\d{9})$',
                'maxLength': 13,
              },
            ],
          },
        ],
      },
    ],
    'reservedCategories': <String>[],
    'paymentsEnabled': false,
  },
};

/// Verbatim shape of `toPublicAccount()` — note there is NO holder name and no
/// decryptable field, only `accountMask`.
Map<String, dynamic> _accountPayload({
  String id = 'acct_1',
  String status = 'UNVERIFIED',
}) => {
  'id': id,
  'serviceCode': 'ECG_PREPAID',
  'providerCode': 'ECG',
  'categoryCode': 'ELECTRICITY',
  'label': 'ECG prepaid',
  'nickname': 'My Apartment',
  'accountMask': '•••• 4321',
  'verificationStatus': status,
  'verifiedAt': null,
  'isPrimary': false,
  'lastUsedAt': null,
  'createdAt': '2026-10-30T12:00:00.000Z',
  'updatedAt': '2026-10-30T12:00:00.000Z',
  'capabilities': {
    'saveAccount': true,
    'lookupAccount': false,
    'quote': false,
    'payment': false,
  },
};

void main() {
  test(
    'templates become categories and services, with no invented payment',
    () async {
      final api = _ScriptedApiClient({
        'GET /bills/service-templates': () => _json(_templatesPayload()),
      });
      final catalog = await HttpBillsGateway(api).serviceCatalog();

      expect(catalog.paymentsEnabled, isFalse);
      expect(catalog.categories.map((c) => c.id), [
        'ELECTRICITY',
        'AIRTIME_DATA',
      ]);
      expect(catalog.categories.first.label, 'Electricity');
      expect(catalog.services.length, 2);

      final ecg = catalog.serviceByCode('ECG_PREPAID')!;
      expect(ecg.providerCode, 'ECG');
      expect(ecg.categoryCode, 'ELECTRICITY');
      expect(ecg.capabilities.lookupAccount, isFalse);
      expect(ecg.capabilities.payment, isFalse);
      expect(ecg.isPayable, isFalse, reason: 'no capability path exists');
      expect(ecg.identityField!.key, 'meterNumber');
      expect(ecg.identityField!.label, 'Meter number');
    },
  );

  test(
    'billers are the server templates, never a hardcoded catalogue',
    () async {
      final api = _ScriptedApiClient({
        'GET /bills/service-templates': () => _json(_templatesPayload()),
      });
      final billers = await HttpBillsGateway(api).billers();

      expect(billers.map((b) => b.name), ['ECG prepaid', 'MTN airtime']);
      expect(billers.first.identifierLabel, 'Meter number');
      expect(billers.last.identifierLabel, 'Phone number');
      // The id carries both server codes so the save endpoint receives identity,
      // not a display name.
      expect(billers.first.id, 'ECG_PREPAID:ECG');
    },
  );

  test(
    'a saved account keeps the server mask and admits it has no holder name',
    () async {
      final api = _ScriptedApiClient({
        'GET /bills/saved-accounts': () => _json({
          'success': true,
          'data': {
            'accounts': [_accountPayload()],
          },
        }),
        'GET /bills/service-templates': () => _json(_templatesPayload()),
      });
      final accounts = await HttpBillsGateway(api).savedAccounts();

      expect(accounts.length, 1);
      final account = accounts.single;
      expect(account.identifierMasked, '•••• 4321');
      expect(account.holderName, isNull, reason: 'the contract sends no name');
      expect(account.hasProviderVerifiedHolder, isFalse);
      expect(account.verificationStatus, 'UNVERIFIED');
      expect(account.displayName, 'My Apartment');
      expect(account.billerId, 'ECG_PREPAID:ECG');
    },
  );

  test('saving posts exactly the fields the contract validates', () async {
    final api = _ScriptedApiClient({
      'GET /bills/service-templates': () => _json(_templatesPayload()),
      'POST /bills/saved-accounts': () => _json({
        'success': true,
        'data': {'account': _accountPayload()},
      }, 201),
    });
    final saved = await HttpBillsGateway(api).saveAccount(
      billerId: 'ECG_PREPAID:ECG',
      identifier: '1234567890',
      alias: 'My Apartment',
    );

    final body = api.bodies.single;
    expect(body['serviceCode'], 'ECG_PREPAID');
    expect(body['providerCode'], 'ECG');
    expect(body['nickname'], 'My Apartment');
    expect(body['accountFields'], {'meterNumber': '1234567890'});
    expect(saved.identifierMasked, '•••• 4321');
    expect(saved.holderName, isNull);
  });

  test(
    'lookup refuses and names the reason instead of inventing a holder',
    () async {
      final api = _ScriptedApiClient({
        'GET /bills/service-templates': () => _json(_templatesPayload()),
      });
      await expectLater(
        HttpBillsGateway(
          api,
        ).lookup(billerId: 'ECG_PREPAID:ECG', identifier: '1234567890'),
        throwsA(
          isA<BillsUnavailableException>().having(
            (e) => e.message ?? '',
            'message',
            contains('no provider lookup'),
          ),
        ),
      );
    },
  );

  test(
    'quote, pay and requests refuse: the backend publishes none of them',
    () async {
      final api = _ScriptedApiClient({
        'GET /bills/service-templates': () => _json(_templatesPayload()),
      });
      final gateway = HttpBillsGateway(api);

      await expectLater(
        gateway.quote(accountId: 'acct_1'),
        throwsA(isA<BillsUnavailableException>()),
      );
      await expectLater(
        gateway.pay(quoteId: 'q1'),
        throwsA(isA<BillsUnavailableException>()),
      );
      await expectLater(
        gateway.sendRequest(accountId: 'acct_1', recipientName: 'Kofi'),
        throwsA(isA<BillsUnavailableException>()),
      );
      expect(await gateway.requests(), isEmpty);
      // Nothing above reached the network: a refusal is not a probe.
      expect(
        api.calls.where((c) => !c.startsWith('GET /bills/service-templates')),
        isEmpty,
      );
    },
  );

  test('the hub reports only what the contract can answer', () async {
    final api = _ScriptedApiClient({
      'GET /bills/service-templates': () => _json(_templatesPayload()),
      'GET /bills/saved-accounts': () => _json({
        'success': true,
        'data': {
          'accounts': [_accountPayload()],
        },
      }),
    });
    final hub = await HttpBillsGateway(api).hub();

    expect(hub.savedAccounts.single.verificationStatus, 'UNVERIFIED');
    expect(hub.recentPayments, isEmpty);
    expect(hub.outstanding, isEmpty);
    expect(hub.requests, isEmpty);
  });

  test(
    'a backend without the routes yet is "not configured", not a crash',
    () async {
      final api = _ScriptedApiClient(const {});
      final gateway = HttpBillsGateway(api);

      expect((await gateway.serviceCatalog()).services, isEmpty);
      expect(await gateway.savedAccounts(), isEmpty);
      expect(await gateway.availability(), isA<BillsAvailability>());
      expect((await gateway.availability()).isAvailable, isFalse);
    },
  );

  test(
    'a 503 from the cryptography guard reaches the member as its own words',
    () async {
      final api = _ScriptedApiClient({
        'GET /bills/saved-accounts': () => _json({
          'success': false,
          'code': 'SAVED_ACCOUNT_STORAGE_UNAVAILABLE',
          'message': 'Saved accounts are temporarily unavailable.',
        }, 503),
      });

      await expectLater(
        HttpBillsGateway(api).savedAccounts(),
        throwsA(
          isA<BillsUnavailableException>().having(
            (e) => e.message ?? '',
            'message',
            'Saved accounts are temporarily unavailable.',
          ),
        ),
      );
    },
  );
}
