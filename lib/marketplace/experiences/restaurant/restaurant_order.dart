import 'restaurant_experience.dart';

abstract class RestaurantOrderGateway {
  Future<RestaurantOrderResult> placeOrder(RestaurantTray tray);
}

sealed class RestaurantOrderResult { const RestaurantOrderResult(); }

class RestaurantOrderSuccess extends RestaurantOrderResult {
  final String orderId;
  final String status;
  const RestaurantOrderSuccess({required this.orderId, this.status = 'received'});
}

class RestaurantOrderFailure extends RestaurantOrderResult {
  final String message;
  final bool retryable;
  const RestaurantOrderFailure({required this.message, this.retryable = true});
}

class RestaurantOrderController {
  final RestaurantOrderGateway gateway;
  const RestaurantOrderController(this.gateway);

  Future<RestaurantOrderResult> submit(RestaurantTray tray) async {
    if (tray.lines.isEmpty) {
      return const RestaurantOrderFailure(
        message: 'Your tray is empty.',
        retryable: false,
      );
    }
    if (tray.lines.any((line) => !line.dish.available)) {
      return const RestaurantOrderFailure(
        message: 'One or more dishes are no longer available.',
        retryable: false,
      );
    }
    return gateway.placeOrder(tray);
  }
}

class RestaurantOrderStatus {
  static const received = 'received';
  static const preparing = 'preparing';
  static const ready = 'ready';
  static const completed = 'completed';
  static const cancelled = 'cancelled';

  static String label(String status) {
    switch (status) {
      case preparing:
        return 'Preparing';
      case ready:
        return 'Ready for pickup';
      case completed:
        return 'Completed';
      case cancelled:
        return 'Cancelled';
      default:
        return 'Order received';
    }
  }
}
