/// Service-vertical seam (Overhaul 03 §6).
///
/// Brief §6.5: do not fake. There is no backend for request → slot →
/// estimate → confirm → live flows today, so the default binding supports
/// nothing and the UI keeps rendering the existing
/// `service_experience_stage.dart` fallback. The contract exists so a future
/// service vertical composes with the same store grammar without inventing a
/// second one.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/experience/gateways/az_gateway_result.dart';

enum ServiceFlowStage { request, slot, location, estimate, confirm, live, complete }

class ServiceSlot {
  final DateTime start;
  final DateTime end;
  final bool available;
  const ServiceSlot({required this.start, required this.end, required this.available});
}

class ServiceEstimate {
  final double amountUsdc;
  final String? note;
  const ServiceEstimate({required this.amountUsdc, this.note});
}

class ServiceRequestDraft {
  final String bizId;
  final String? serviceId;
  final ServiceSlot? slot;
  final String? locationId;
  final String? notes;
  const ServiceRequestDraft({
    required this.bizId,
    this.serviceId,
    this.slot,
    this.locationId,
    this.notes,
  });
}

abstract interface class ServiceFlowGateway {
  /// Stages the bound backend can actually serve. Empty today.
  Set<ServiceFlowStage> get supportedStages;

  Future<AzGatewayResult<List<ServiceSlot>>> slots(String bizId, DateTime day);
  Future<AzGatewayResult<ServiceEstimate>> estimate(ServiceRequestDraft draft);
  Future<AzGatewayResult<String>> confirm(
    ServiceRequestDraft draft, {
    required String idempotencyKey,
  });
  Stream<ServiceFlowStage> liveStatus(String requestId);
}

class UnsupportedServiceFlowGateway implements ServiceFlowGateway {
  const UnsupportedServiceFlowGateway();

  static const _reason = 'Service flows are not available for this business yet.';

  @override
  Set<ServiceFlowStage> get supportedStages => const {};

  @override
  Future<AzGatewayResult<List<ServiceSlot>>> slots(String bizId, DateTime day) async =>
      const AzUnsupported(_reason);

  @override
  Future<AzGatewayResult<ServiceEstimate>> estimate(ServiceRequestDraft draft) async =>
      const AzUnsupported(_reason);

  @override
  Future<AzGatewayResult<String>> confirm(
    ServiceRequestDraft draft, {
    required String idempotencyKey,
  }) async =>
      const AzUnsupported(_reason);

  @override
  Stream<ServiceFlowStage> liveStatus(String requestId) => const Stream.empty();
}

final serviceFlowGatewayProvider =
    Provider<ServiceFlowGateway>((_) => const UnsupportedServiceFlowGateway());