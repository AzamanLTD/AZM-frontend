import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/marketplace/experiences/restaurant/restaurant_experience.dart';
import 'package:azaman/marketplace/experiences/restaurant/restaurant_order.dart';

class _Gateway implements RestaurantOrderGateway {
  RestaurantTray? received;
  @override
  Future<RestaurantOrderResult> placeOrder(RestaurantTray tray) async {
    received = tray;
    return const RestaurantOrderSuccess(orderId: 'o1', status: RestaurantOrderStatus.preparing);
  }
}

void main() {
  const dish = RestaurantDish(id: 'd1', name: 'Jollof', price: 50);

  test('empty tray is rejected before gateway', () async {
    final gateway = _Gateway();
    final result = await RestaurantOrderController(gateway).submit(const RestaurantTray());
    expect(result, isA<RestaurantOrderFailure>());
    expect(gateway.received, isNull);
  });

  test('unavailable dish is rejected', () async {
    final gateway = _Gateway();
    const unavailable = RestaurantDish(id: 'd2', name: 'Sold out', available: false);
    final result = await RestaurantOrderController(gateway).submit(const RestaurantTray().add(unavailable));
    expect(result, isA<RestaurantOrderFailure>());
  });

  test('valid tray is handed to gateway', () async {
    final gateway = _Gateway();
    final result = await RestaurantOrderController(gateway).submit(const RestaurantTray().add(dish));
    expect(result, isA<RestaurantOrderSuccess>());
    expect(gateway.received?.itemCount, 1);
  });

  test('status labels remain stable', () {
    expect(RestaurantOrderStatus.label(RestaurantOrderStatus.received), 'Order received');
    expect(RestaurantOrderStatus.label(RestaurantOrderStatus.preparing), 'Preparing');
    expect(RestaurantOrderStatus.label(RestaurantOrderStatus.ready), 'Ready for pickup');
    expect(RestaurantOrderStatus.label(RestaurantOrderStatus.completed), 'Completed');
  });
}
