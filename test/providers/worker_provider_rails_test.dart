// =============================================================================
// Worker Sub-Portal rail contracts (URL construction + envelope shape)
// =============================================================================
// The worker screens previously hardcoded '/api/...' into endpoint strings,
// which ApiClient resolves against a baseUrl already ending in '/api' —
// every call probed /api/api/business-os/... and 404'd.
//
// This suite pins the EXACT request path each worker provider constructs,
// against a recording ApiClient, so a regression back to the double-prefixed
// (or otherwise wrong) rail fails the contract test — not a silent 404 at
// runtime. The canned envelopes mirror the verified backend `main` contracts
// (routes/businessOSRoutes.js), and each parse assertion locks the envelope
// KEY the provider reads, so a backend shape change surfaces here too.
// =============================================================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:azaman/providers/worker_provider.dart';
import 'package:azaman/screens/worker/worker_swaps_screen.dart';
import 'package:azaman/services/api_client.dart';

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

class _RailRecordingClient extends ApiClient {
  final List<String> getPaths = [];
  final Map<String, http.Response> responses;

  _RailRecordingClient(this.responses);

  @override
  Future<http.Response> get(String endpoint,
      {Map<String, String>? headers, bool requireAuth = true}) async {
    getPaths.add(endpoint);
    return responses[endpoint] ?? _json(404, {'success': false});
  }
}

void main() {
  late _RailRecordingClient client;
  late ProviderContainer container;

  setUp(() {
    client = _RailRecordingClient({
      // GET /api/business-os/employees/my-dashboard → {success, dashboard}
      '/business-os/employees/my-dashboard':
          _json(200, {'success': true, 'dashboard': null}),
      // GET /api/business-os/employees/me → {success, employee}
      '/business-os/employees/me':
          _json(200, {'success': true, 'employee': null}),
      // GET /api/business-os/employees/my-shifts → {success, shifts:[]}
      '/business-os/employees/my-shifts': _json(200, {
        'success': true,
        'shifts': [
          {
            'id': 'shift-1',
            'businessProfileId': 'bp-1',
            'employeeId': 'emp-1',
            'shiftDate': '2026-10-20T08:00:00Z',
            'startTime': '2026-10-20T08:00:00Z',
            'endTime': '2026-10-20T16:00:00Z',
            'status': 'SCHEDULED',
          }
        ]
      }),
      // GET /api/business-os/employees/my-payroll → {success, records:[]}
      '/business-os/employees/my-payroll': _json(200, {
        'success': true,
        'records': [
          {
            'id': 'pr-1',
            'employeeId': 'emp-1',
            'period': '2026-10',
            'grossAmount': 100,
            'netAmount': 92,
            'status': 'PAID',
            'createdAt': '2026-10-01T00:00:00Z',
          }
        ]
      }),
      // GET /api/business-os/employees/my-earnings → flat EWA summary
      '/business-os/employees/my-earnings': _json(200, {
        'success': true,
        'ewaAvailable': 30,
        'accruedWages': 100,
        'withdrawnEarly': 0,
        'ewaEligible': true,
        'ewaHistory': [],
      }),
      // GET /api/business-os/employees/my-feedback → {success, feedback:[]}
      '/business-os/employees/my-feedback': _json(200, {
        'success': true,
        'feedback': [
          {'id': 'fb-1', 'rating': 5, 'createdAt': '2026-10-01T00:00:00Z'}
        ]
      }),
      // GET /api/business-os/employees/shifts/open → {success, swaps:[]}
      '/business-os/employees/shifts/open': _json(200, {
        'success': true,
        'swaps': [
          {'id': 'swap-1', 'status': 'OPEN'}
        ]
      }),
      // GET /api/business-os/time-off/my-requests → {success, requests:[]}
      '/business-os/time-off/my-requests': _json(200, {
        'success': true,
        'requests': [
          {
            'id': 'to-1',
            'employeeId': 'emp-1',
            'type': 'VACATION',
            'startDate': '2026-11-01T00:00:00Z',
            'endDate': '2026-11-03T00:00:00Z',
            'status': 'PENDING',
            'createdAt': '2026-10-01T00:00:00Z',
          }
        ]
      }),
    });
    container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
  });

  test('workerDashboardProvider reads the my-dashboard rail exactly once', () async {
    final dash = await container.read(workerDashboardProvider.future);
    expect(client.getPaths, ['/business-os/employees/my-dashboard']);
    // backend contract: {success:true, dashboard:<obj|null>} — null dashboard
    // resolves to null, never throws.
    expect(dash, isNull);
  });

  test('myEmployeeProvider reads the employee-identity rail', () async {
    final emp = await container.read(myEmployeeProvider.future);
    expect(client.getPaths, ['/business-os/employees/me']);
    expect(emp, isNull); // {success:true, employee:null} contract
  });

  test('myShiftsProvider reads my-shifts and parses the shifts envelope', () async {
    final shifts = await container.read(myShiftsProvider.future);
    expect(client.getPaths, ['/business-os/employees/my-shifts']);
    expect(shifts, hasLength(1));
    expect(shifts.first.id, 'shift-1');
  });

  test('myPayrollProvider reads my-payroll and parses the records envelope', () async {
    final records = await container.read(myPayrollProvider.future);
    expect(client.getPaths, ['/business-os/employees/my-payroll']);
    expect(records, hasLength(1));
    expect(records.first.period, '2026-10');
  });

  test('myEwaProvider reads my-earnings and parses the flat EWA summary keys', () async {
    final ewa = await container.read(myEwaProvider.future);
    expect(client.getPaths, ['/business-os/employees/my-earnings']);
    expect(ewa['ewaAvailable'], 30);
    expect(ewa['accruedWages'], 100);
    expect(ewa['ewaEligible'], true);
  });

  test('myFeedbackProvider reads my-feedback and parses the feedback envelope', () async {
    final feedback = await container.read(myFeedbackProvider.future);
    expect(client.getPaths, ['/business-os/employees/my-feedback']);
    expect(feedback, hasLength(1));
    expect(feedback.first.rating, 5);
  });

  test('myTimeOffProvider reads the time-off my-requests rail (employees prefix NOT included)', () async {
    final requests = await container.read(myTimeOffProvider.future);
    // backend route is GET /api/business-os/time-off/my-requests
    // (businessOSRoutes.js line 644 — NOT under /employees).
    expect(client.getPaths, ['/business-os/time-off/my-requests']);
    expect(requests, hasLength(1));
    expect(requests.first.id, 'to-1');
  });

  test('openSwapsProvider reads the open-shift-swaps rail and parses swaps', () async {
    final swaps = await container.read(openSwapsProvider.future);
    // backend route: GET /api/business-os/employees/shifts/open
    // → {success:true, swaps:[...]} (businessOSRoutes.js line 313).
    expect(client.getPaths, ['/business-os/employees/shifts/open']);
    expect(swaps, hasLength(1));
    expect(swaps.first['id'], 'swap-1');
  });

  test('no worker rail ever constructs a double /api prefix', () async {
    await container.read(workerDashboardProvider.future);
    await container.read(myEmployeeProvider.future);
    await container.read(myShiftsProvider.future);
    await container.read(myPayrollProvider.future);
    await container.read(myEwaProvider.future);
    await container.read(myFeedbackProvider.future);
    await container.read(myTimeOffProvider.future);
    expect(client.getPaths, isNotEmpty);
    for (final path in client.getPaths) {
      expect(path.startsWith('/api/'), isFalse,
          reason: 'ApiClient already pins baseUrl ending in /api — a leading '
              '/api/ produces /api/api/... (404). Saw: $path');
    }
  });
}
