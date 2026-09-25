// =============================================================================
// WORKER PROVIDER — Riverpod state for the Worker Sub-Portal
// API pattern: jsonDecode(res.body) — matches BusinessService
// =============================================================================

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/models/employee_models.dart';

final workerDashboardProvider = FutureProvider<WorkerDashboard?>((ref) async {
  final client = ref.read(apiClientProvider);
  try {
    final res = await client.get('/api/business-os/employees/my-dashboard');
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) return null;
    final dash = body['dashboard'];
    if (dash == null) return null;
    return WorkerDashboard.fromJson(dash as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});

final myEmployeeProvider = FutureProvider<BusinessEmployee?>((ref) async {
  final client = ref.read(apiClientProvider);
  try {
    final res = await client.get('/api/business-os/employees/me');
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) return null;
    final emp = body['employee'];
    if (emp == null) return null;
    return BusinessEmployee.fromJson(emp as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});

final myShiftsProvider = FutureProvider<List<Shift>>((ref) async {
  final client = ref.read(apiClientProvider);
  try {
    final res = await client.get('/api/business-os/employees/my-shifts');
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['shifts'] as List<dynamic>? ?? [];
    return list.map((s) => Shift.fromJson(s as Map<String, dynamic>)).toList();
  } catch (_) {
    return [];
  }
});

final myPayrollProvider = FutureProvider<List<PayrollRecord>>((ref) async {
  final client = ref.read(apiClientProvider);
  try {
    final res = await client.get('/api/business-os/employees/my-payroll');
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['records'] as List<dynamic>? ?? [];
    return list.map((r) => PayrollRecord.fromJson(r as Map<String, dynamic>)).toList();
  } catch (_) {
    return [];
  }
});

final myEwaProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.read(apiClientProvider);
  try {
    final res = await client.get('/api/business-os/employees/my-earnings');
    if (res.statusCode != 200) return {};
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return {
      'ewaAvailable': (body['ewaAvailable'] as num?)?.toDouble() ?? 0,
      'accruedWages': (body['accruedWages'] as num?)?.toDouble() ?? 0,
      'withdrawnEarly': (body['withdrawnEarly'] as num?)?.toDouble() ?? 0,
      'ewaEligible': body['ewaEligible'] ?? false,
      'ewaHistory': body['ewaHistory'] ?? [],
    };
  } catch (_) {
    return {};
  }
});

final myFeedbackProvider = FutureProvider<List<EmployeeFeedback>>((ref) async {
  final client = ref.read(apiClientProvider);
  try {
    final res = await client.get('/api/business-os/employees/my-feedback');
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['feedback'] as List<dynamic>? ?? [];
    return list.map((f) => EmployeeFeedback.fromJson(f as Map<String, dynamic>)).toList();
  } catch (_) {
    return [];
  }
});

final myTimeOffProvider = FutureProvider<List<TimeOffRequest>>((ref) async {
  final client = ref.read(apiClientProvider);
  try {
    final res = await client.get('/api/business-os/time-off/my-requests');
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['requests'] as List<dynamic>? ?? [];
    return list.map((t) => TimeOffRequest.fromJson(t as Map<String, dynamic>)).toList();
  } catch (_) {
    return [];
  }
});
