import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/gateways/az_gateway_result.dart';

void main() {
  test('AzOk exposes its value', () {
    const r = AzOk<int>(3);
    expect(r.isOk, isTrue);
    expect(r.valueOrNull, 3);
    expect(r.errorMessage, isNull);
  });

  test('AzFailed carries message and cause, no value', () {
    final cause = Exception('boom');
    final r = AzFailed<int>('network', cause: cause);
    expect(r.isFailed, isTrue);
    expect(r.isUnsupported, isFalse);
    expect(r.valueOrNull, isNull);
    expect(r.errorMessage, 'network');
    expect(r.cause, same(cause));
  });

  test('AzUnsupported names the missing capability', () {
    const r = AzUnsupported<int>('POST /stories/:id/react');
    expect(r.isUnsupported, isTrue);
    expect(r.valueOrNull, isNull);
    expect(r.errorMessage, 'POST /stories/:id/react');
  });

  test('map transforms ok and preserves failure kinds', () {
    expect(const AzOk<int>(2).map((v) => '$v!').valueOrNull, '2!');
    final f = const AzFailed<int>('x').map((v) => v * 2);
    expect(f, isA<AzFailed<int>>());
    expect(f.errorMessage, 'x');
    final u = const AzUnsupported<int>('y').map((v) => v * 2);
    expect(u, isA<AzUnsupported<int>>());
    expect(u.errorMessage, 'y');
  });

  test('exhaustive switch over the sealed hierarchy', () {
    String describe(AzGatewayResult<int> r) => switch (r) {
          AzOk<int>(:final value) => 'ok:$value',
          AzFailed<int>(:final message) => 'failed:$message',
          AzUnsupported<int>(:final reason) => 'unsupported:$reason',
        };
    expect(describe(const AzOk(1)), 'ok:1');
    expect(describe(const AzFailed('e')), 'failed:e');
    expect(describe(const AzUnsupported('n')), 'unsupported:n');
  });
}