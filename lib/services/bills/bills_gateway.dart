// AZAMAN — BILLS GATEWAY CONTRACT
//
// The seam between the Bills UI and whatever the backend can actually do. It
// exists so the screens can be written and tested BEFORE the provider contract
// is agreed, without inventing endpoints or response fields here.
//
// Until the backend agent confirms the routes and shapes, the production
// implementation is [UnavailableBillsGateway]: it reports that bill payments
// are not configured, which is the truth today. Tests substitute a fake.
//
// Rules this contract encodes:
//   • availability is the SERVER's answer, never a hardcoded list;
//   • no amount, account holder or history is ever synthesised client-side;
//   • "pending" and "created" are not success.
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One biller category the backend reports it can serve.
class BillsCategory {
  const BillsCategory({
    required this.id,
    required this.label,
    this.billerCount = 0,
  });

  final String id;
  final String label;
  final int billerCount;
}

/// The server's answer to "what can this member actually pay right now?".
class BillsAvailability {
  const BillsAvailability({
    required this.isAvailable,
    this.categories = const <BillsCategory>[],
  });

  /// False when the facility is not configured, or the member/region has no
  /// reachable billers. The UI must render an honest empty state for this.
  final bool isAvailable;

  final List<BillsCategory> categories;

  static const BillsAvailability unavailable = BillsAvailability(
    isAvailable: false,
  );
}

/// The bill-payment capability surface.
///
/// Deliberately narrow for now: only what the Hub can honour without a settled
/// backend contract. Lookup, quote, save-account and payment operations are
/// added here once their routes and payloads are agreed, so that no screen has
/// to guess a shape.
abstract class BillsGateway {
  Future<BillsAvailability> availability();
}

/// Production default: honest unavailability, with no invented data.
class UnavailableBillsGateway implements BillsGateway {
  const UnavailableBillsGateway();

  @override
  Future<BillsAvailability> availability() async =>
      BillsAvailability.unavailable;
}

final billsGatewayProvider = Provider<BillsGateway>(
  (ref) => const UnavailableBillsGateway(),
);
