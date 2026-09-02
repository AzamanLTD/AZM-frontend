import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/widgets/floating_cart_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CartNotifier notifier;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notifier = CartNotifier();
  });

  Widget buildSubject() {
    return ProviderScope(
      overrides: [cartProvider.overrideWith((ref) => notifier)],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: const SizedBox.shrink(),
          bottomNavigationBar: FloatingCartBar(
            label: 'Order tray',
            onTap: _noop,
          ),
        ),
      ),
    );
  }

  testWidgets('tray appears with the current item and totals', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.text('0'), findsNothing);

    notifier.addItem(
      businessProfileId: 'biz-1',
      businessName: 'Koko House',
      productId: 'dish-1',
      name: 'Chicken & Rice',
      unitPrice: 8,
      quantity: 1,
      experiencePreset: 'DINING_JOURNEY',
    );
    await tester.pump();

    expect(find.text('Order tray'), findsOneWidget);
    expect(find.text('Koko House'), findsOneWidget);
    expect(find.text(r'$8.00'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('adding another item updates count and subtotal with an animated state', (tester) async {
    await tester.pumpWidget(buildSubject());
    notifier.addItem(
      businessProfileId: 'biz-1',
      businessName: 'Koko House',
      productId: 'dish-1',
      name: 'Chicken & Rice',
      unitPrice: 8,
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 700));

    notifier.addItem(
      businessProfileId: 'biz-1',
      businessName: 'Koko House',
      productId: 'dish-2',
      name: 'Plantain',
      unitPrice: 4,
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('2'), findsOneWidget);
    expect(find.text(r'$12.00'), findsOneWidget);
    expect(find.byType(ScaleTransition), findsWidgets);
  });

  testWidgets('an empty cart remains mounted while its tray animates out', (tester) async {
    await tester.pumpWidget(buildSubject());
    notifier.addItem(
      businessProfileId: 'biz-1',
      businessName: 'Koko House',
      productId: 'dish-1',
      name: 'Chicken & Rice',
      unitPrice: 8,
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 700));

    notifier.clearCart();
    await tester.pump(const Duration(milliseconds: 100));

    final slide = tester.widget<AnimatedSlide>(find.byType(AnimatedSlide));
    expect(slide.offset.dy, greaterThan(1));

    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(FloatingCartBar), findsOneWidget);
  });
}

void _noop() {}
