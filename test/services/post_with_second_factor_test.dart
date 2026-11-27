// ApiClient.postWithSecondFactor: a route that requires require2FA answers
// 2FA_REQUIRED / PASSWORD_REQUIRED; the client prompts ONCE and re-sends the
// same body plus the proof. A dismissed prompt sends nothing more, and a
// refusal that is not a second-factor challenge is never prompted for.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/financial_step_up.dart';

http.Response _json(Map<String, dynamic> body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(FinancialStepUp.uninstall);

  test('answers the challenge once and re-sends the body with the proof', () async {
    final seen = <Map<String, dynamic>>[];
    final mock = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      seen.add(body);
      expect(request.url.path, '/api/smart-routes');
      if (!body.containsKey('password')) {
        return _json({'success': false, 'code': 'PASSWORD_REQUIRED', 'message': 'Confirm with your password.'}, 401);
      }
      return _json({'success': true, 'route': {'id': 'r1'}}, 201);
    });
    var prompts = 0;
    FinancialStepUp.install((c) async {
      prompts++;
      expect(c.factor, StepUpFactor.password);
      return StepUpCredential(StepUpFactor.password, 'pw');
    });

    final res = await ApiClient(client: mock)
        .postWithSecondFactor('/smart-routes', {'action': 'WITHDRAW_MOMO', 'amountUsdc': '10'}, requireAuth: false);

    expect(res.statusCode, 201);
    expect(prompts, 1);
    expect(seen, hasLength(2));
    expect(seen.first.containsKey('password'), isFalse);
    expect(seen.last, {'action': 'WITHDRAW_MOMO', 'amountUsdc': '10', 'password': 'pw'});
  });

  test('a dismissed prompt rethrows and sends nothing more', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      return _json({'success': false, 'code': '2FA_REQUIRED', 'message': 'Enter your code.'}, 401);
    });
    FinancialStepUp.install((c) async => null);

    await expectLater(
      ApiClient(client: mock).postWithSecondFactor('/smart-routes/r1/run-now', {}, requireAuth: false),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', '2FA_REQUIRED')),
    );
    expect(calls, 1);
  });

  test('a refusal that is not a second-factor challenge is not prompted for', () async {
    var prompts = 0;
    final mock = MockClient((request) async =>
        _json({'success': false, 'code': 'KYC_REQUIRED', 'message': 'Verify your identity.'}, 403));
    FinancialStepUp.install((c) async {
      prompts++;
      return StepUpCredential(StepUpFactor.totp, '123456');
    });

    await expectLater(
      ApiClient(client: mock).postWithSecondFactor('/smart-routes', {}, requireAuth: false),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'KYC_REQUIRED')),
    );
    expect(prompts, 0);
  });
}
