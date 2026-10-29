/// Sticky purchase tray visibility (Overhaul 03 §2.4).
library;

import 'package:azaman/providers/cart_provider.dart';

/// The tray shows only when the cart holds items for *this* business.
bool retailTrayVisible(CartState cart, {required String businessId}) =>
    cart.items.isNotEmpty && cart.businessProfileId == businessId;