import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/gateways/az_gateway_result.dart';
import 'package:azaman/experience/gateways/service_flow_gateway.dart';

void main() {
  test('default binding supports nothing and answers AzUnsupported', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final gw = container.read(serviceFlowGatewayProvider);

    expect(gw, isA<UnsupportedServiceFlowGateway>());
    expect(gw.supportedStages, isEmpty);
    expect(await gw.slots('biz', DateTime(2026)), isA<AzUnsupported<List<ServiceSlot>>>());
    expect(await gw.estimate(const ServiceRequestDraft(bizId: 'biz')), isA<AzUnsupported<ServiceEstimate>>());
    expect(
      await gw.confirm(const ServiceRequestDraft(bizId: 'biz'), idempotencyKey: 'k'),
      isA<AzUnsupported<String>>(),
    );
    expect(await gw.liveStatus('r').toList(), isEmpty);
  });
}