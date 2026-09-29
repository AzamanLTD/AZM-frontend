// =============================================================================
// FLOATING CART BAR — catch / fan regression suite (TASK-012 review hardening)
//
// Guards the retail tray identity introduced with TASK-012:
//   - the squash-and-stretch catch and two-beat haptic fire for SHOP_FLOOR
//     count increases only — every other vertical keeps the pre-TASK-012
//     pulse path and its original toggle haptic;
//   - the tray preview fans at most three thumbnails, newest on top;
//   - reduced motion suppresses the celebration entirely;
//   - the animation controllers are disposed cleanly, even mid-flight.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/floating_cart_bar.dart';

void _noop() {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CartNotifier notifier;
  final hapticCalls = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notifier = CartNotifier();
    hapticCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) {
      if (call.method.startsWith('HapticFeedback')) {
        hapticCalls.add(call.method);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget buildSubject({bool disableAnimations = false, VoidCallback? onTap}) {
    return ProviderScope(
      overrides: [cartProvider.overrideWith((ref) => notifier)],
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: MaterialApp(
          home: Scaffold(
            body: const SizedBox.shrink(),
            bottomNavigationBar: FloatingCartBar(
              label: 'Order tray',
              onTap: onTap ?? _noop,
            ),
          ),
        ),
      ),
    );
  }

  void addItem(
    String id,
    String url, {
    String preset = 'SHOP_FLOOR',
  }) {
    notifier.addItem(
      businessProfileId: 'biz-1',
      businessName: 'Azaman Retail',
      productId: id,
      name: 'Item $id',
      unitPrice: 10,
      imageUrl: url,
      quantity: 1,
      experiencePreset: preset,
    );
  }

  /// The bar-level ScaleTransition is the first one in the tree (the
  /// subtotal pulse sits deeper inside the Material it wraps).
  double barScale(WidgetTester tester) =>
      tester.widget<ScaleTransition>(find.byType(ScaleTransition).first).scale
          .value;

  testWidgets('a retail add plays the catch squash and the two-beat haptic',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    addItem('p1', 'https://example.com/img-1.jpg');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Mid-squash: the catch is under way, scale below 1.0.
    expect(barScale(tester), lessThan(1.0));

    // The two-beat "clack": two haptic events (the platform channel
    // carries every intensity as "HapticFeedback.vibrate", so the beat
    // count is the contract, not the name).
    await tester.pump(const Duration(milliseconds: 60));
    expect(hapticCalls, hasLength(2));
  });

  testWidgets('a non-retail add keeps the pre-TASK-012 pulse and its haptic',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    addItem('d1', 'https://example.com/img-1.jpg', preset: 'DINING_JOURNEY');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The catch never runs for other verticals — the bar stays at 1.0
    // while the pulse plays on the subtotal.
    expect(barScale(tester), 1.0);
    // The original count-increase haptic — one beat, not the retail two.
    expect(hapticCalls, hasLength(1));
  });

  testWidgets('the fan renders at most three thumbnails, newest on top',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    for (var i = 1; i <= 4; i++) {
      addItem('p$i', 'https://example.com/img-$i.jpg');
    }
    await tester.pumpAndSettle();

    final fan = find.byType(AzamanNetworkImage);
    expect(fan, findsNWidgets(3));
    // The fan keeps the newest item last — painted on top at the right.
    expect(
      tester.widget<AzamanNetworkImage>(fan.last).imageUrl,
      'https://example.com/img-4.jpg',
    );
    // And it sits further right than the older thumbnails.
    expect(
      tester.getTopLeft(fan.last).dx,
      greaterThan(tester.getTopLeft(fan.first).dx),
    );
  });

  testWidgets('under reduced motion the tray settles without the catch',
      (tester) async {
    await tester.pumpWidget(buildSubject(disableAnimations: true));
    addItem('p1', 'https://example.com/img-1.jpg');
    await tester.pump();

    // A single frame in: the new state is fully presented, nothing is
    // animating — the celebration never started (no pump through the
    // 340ms catch sequence).
    expect(find.text('1'), findsOneWidget);
    expect(barScale(tester), 1.0);
    expect(tester.binding.transientCallbackCount, 0);

    // The haptic still plays (haptics are not motion) — let its second
    // beat land so no timer is left pending.
    await tester.pump(const Duration(milliseconds: 60));
  });

  testWidgets('the controllers are disposed cleanly mid-animation',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    addItem('p1', 'https://example.com/img-1.jpg');
    await tester.pump(); // catch mid-flight

    // Unmount while the catch is still running — dispose must release
    // both tickers without a leak.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('tapping the tray still opens the cart', (tester) async {
    var opened = false;
    await tester.pumpWidget(buildSubject(onTap: () => opened = true));
    addItem('p1', 'https://example.com/img-1.jpg');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Order tray'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });
}
