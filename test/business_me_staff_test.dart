import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/business_service.dart';

// GET /business/me answers for staff too (their employer's business, so the
// business portal works for them). In the app, "my business" stays the one
// the user owns: staff keep the worker hub.
class _MeClient extends ApiClient {
  _MeClient(this.body);
  final Map<String, dynamic> body;
  @override
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async => http.Response(jsonEncode(body), 200);
}

Map<String, dynamic> _biz() => {
  'id': 'bp-1',
  'bizId': 'BIZ-1',
  'userId': 20,
  'businessName': 'Chef Abby',
  'category': 'FOOD_BEVERAGE',
};

void main() {
  test('the owner gets their business', () async {
    final svc = BusinessService(apiClient: _MeClient({'success': true, 'business': _biz(), 'access': {'isOwner': true, 'permissions': ['*']}}));
    expect((await svc.getMyBusiness())?.bizId, 'BIZ-1');
  });

  test("staff do not get their employer's business as their own", () async {
    final svc = BusinessService(apiClient: _MeClient({'success': true, 'business': _biz(), 'access': {'isOwner': false, 'permissions': ['reservations.view']}}));
    expect(await svc.getMyBusiness(), isNull);
  });

  test('an older backend without access still works', () async {
    final svc = BusinessService(apiClient: _MeClient({'success': true, 'business': _biz()}));
    expect((await svc.getMyBusiness())?.bizId, 'BIZ-1');
  });
}
