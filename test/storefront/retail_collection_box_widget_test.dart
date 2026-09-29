import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/storefront/models/storefront_models.dart';
import 'package:azaman/storefront/widgets/retail_collection_box_widget.dart';
import 'package:azaman/widgets/azaman_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records every shared-tray mutation the widget asks for, so commits are
/// guarded without touching the network.
class _RecordingCartNotifier extends CartNotifier {
  final List<Map<String, dynamic>> addItemCalls = [];

  @override
  bool addItem({
    required String businessProfileId,
    required String businessName,
    required String productId,
    required String name,
    required double unitPrice,
    String? imageUrl,
    String? category,
    String? experiencePreset,
    int quantity = 1,
    String? notes,
    Map<String, String> variants = const {},
  }) {
    addItemCalls.add({
      'businessProfileId': businessProfileId,
      'businessName': businessName,
      'productId': productId,
      'name': name,
      'quantity': quantity,
      'variants': variants,
    });
    return true;
  }

  @override
  void startNewCart({
    required String businessProfileId,
    required String businessName,
    String? experiencePreset,
  }) {}
}

void main() {
  final business = StorefrontBusinessInfo(
    name: 'Demo Retail',
    category: 'RETAIL',
    averageRating: 4.8,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Swatch taps fire AzamanHaptics.selection(); give the platform channel
    // a no-op handler so the haptic future completes in the test runner.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget buildWidget({
    required List<Map<String, dynamic>> products,
    required _RecordingCartNotifier cart,
    String? businessProfileId = 'biz-1',
  }) {
    return ProviderScope(
      overrides: [cartProvider.overrideWith((ref) => cart)],
      child: MaterialApp(
        home: Scaffold(
          body: RetailCollectionBoxWidget(
            business: business,
            businessProfileId: businessProfileId,
            props: {
              'id': 'collection-1',
              'title': 'Staff Picks',
              'products': products,
            },
          ),
        ),
      ),
    );
  }

  Future<void> openQuickLook(WidgetTester tester) async {
    await tester.tap(find.text('Everyday Bag'));
    await tester.pumpAndSettle();
    expect(find.text('Quick look'), findsOneWidget);
  }

  /// The quick look is a Panel that opens at the 45% rest detent, so content
  /// below that fold is genuinely off-screen and `tester.tap` would hit the
  /// sheet surface instead of the widget. A user scrolls to reach a control;
  /// the test has to as well.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final element = finder.evaluate().firstOrNull;
    if (element == null) return;
    await tester.scrollUntilVisible(
      finder,
      80.0,
      scrollable: find
          .descendant(
            of: find.byType(AzSheetSurface),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('quick look commits selections to the shared tray', (
    tester,
  ) async {
    final cart = _RecordingCartNotifier();
    await tester.pumpWidget(
      buildWidget(
        cart: cart,
        products: [
          {
            'id': 'p1',
            'name': 'Everyday Bag',
            'price': 25,
            'currency': 'GHS',
            'variants': {
              'Size': ['Small', 'Large'],
            },
          },
        ],
      ),
    );

    await openQuickLook(tester);

    // Variant groups gate the commit until a swatch is chosen.
    FilledButton addButton() =>
        tester.widget<FilledButton>(find.byType(FilledButton));
    expect(addButton().onPressed, isNull);

    await reveal(tester, find.text('Small'));
    await tester.tap(find.text('Small'));
    await tester.pumpAndSettle();
    expect(addButton().onPressed, isNotNull);

    // Add-to-bag is pinned below the scroll area (§I.8.3) — no reveal needed.
    await tester.tap(find.text('Add to bag'));
    await tester.pumpAndSettle();

    expect(cart.addItemCalls, hasLength(1));
    expect(cart.addItemCalls.single, {
      'businessProfileId': 'biz-1',
      'businessName': 'Demo Retail',
      'productId': 'p1',
      'name': 'Everyday Bag',
      'quantity': 1,
      'variants': {'Size': 'Small'},
    });
    expect(find.text('Everyday Bag added to cart'), findsOneWidget);
    // A successful commit closes the quick look.
    expect(find.text('Quick look'), findsNothing);
  });

  testWidgets('lift commits a variant-less product to the shared tray', (
    tester,
  ) async {
    final cart = _RecordingCartNotifier();
    await tester.pumpWidget(
      buildWidget(
        cart: cart,
        products: [
          {'id': 'p1', 'name': 'Everyday Bag', 'price': 25, 'currency': 'GHS'},
        ],
      ),
    );

    await tester.drag(find.text('Everyday Bag'), const Offset(0, 184));
    await tester.pumpAndSettle();

    expect(cart.addItemCalls, hasLength(1));
    expect(cart.addItemCalls.single['productId'], 'p1');
    // The lift is a commit, not a tap — no quick look opens.
    expect(find.text('Quick look'), findsNothing);
  });

  testWidgets('lift on a variant product opens the quick look instead', (
    tester,
  ) async {
    final cart = _RecordingCartNotifier();
    await tester.pumpWidget(
      buildWidget(
        cart: cart,
        products: [
          {
            'id': 'p1',
            'name': 'Everyday Bag',
            'price': 25,
            'currency': 'GHS',
            'variants': {
              'Size': ['Small', 'Large'],
            },
          },
        ],
      ),
    );

    await tester.drag(find.text('Everyday Bag'), const Offset(0, 184));
    await tester.pumpAndSettle();

    expect(cart.addItemCalls, isEmpty);
    expect(find.text('Quick look'), findsOneWidget);
  });

  testWidgets('without a business profile id the box never commits blind', (
    tester,
  ) async {
    final cart = _RecordingCartNotifier();
    await tester.pumpWidget(
      buildWidget(
        cart: cart,
        businessProfileId: null,
        products: [
          {'id': 'p1', 'name': 'Everyday Bag', 'price': 25, 'currency': 'GHS'},
        ],
      ),
    );

    // No id → no lift gesture.
    await tester.drag(find.text('Everyday Bag'), const Offset(0, 184));
    await tester.pumpAndSettle();
    expect(cart.addItemCalls, isEmpty);

    // Quick look still opens, but the add is gated by the missing id.
    await openQuickLook(tester);
    await tester.tap(find.text('Add to bag'));
    await tester.pumpAndSettle();
    expect(cart.addItemCalls, isEmpty);
    // No confirmation snackbar for a silent no-op.
    expect(find.text('Everyday Bag added to cart'), findsNothing);
  });

  testWidgets('a product without a price is uncommittable everywhere',
      (tester) async {
    final cart = _RecordingCartNotifier();
    await tester.pumpWidget(buildWidget(
      cart: cart,
      products: [
        {
          'id': 'p1',
          'name': 'Everyday Bag',
          'currency': 'GHS',
          // No price key: the server never sent one.
          'variants': {
            'Size': ['Small', 'Large'],
          },
        },
      ],
    ));

    // The lift gesture is fully disabled — dragging does nothing at all.
    await tester.drag(find.text('Everyday Bag'), const Offset(0, 184));
    await tester.pumpAndSettle();
    expect(cart.addItemCalls, isEmpty);
    expect(find.text('Quick look'), findsNothing);

    // The quick look opens, but its add is gated by the unknown price.
    // (The card and the sheet's own price line also read "Price
    // unavailable" — the button is the one that must be disabled.)
    await openQuickLook(tester);
    expect(find.text('Price unavailable'), findsAtLeastNWidgets(1));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(cart.addItemCalls, isEmpty);
    expect(find.text('Everyday Bag added to cart'), findsNothing);
  });

  testWidgets('an unavailable product is uncommittable everywhere',
      (tester) async {
    final cart = _RecordingCartNotifier();
    await tester.pumpWidget(buildWidget(
      cart: cart,
      products: [
        {
          'id': 'p1',
          'name': 'Everyday Bag',
          'price': 25,
          'currency': 'GHS',
          'available': false,
        },
      ],
    ));

    await tester.drag(find.text('Everyday Bag'), const Offset(0, 184));
    await tester.pumpAndSettle();
    expect(cart.addItemCalls, isEmpty);

    // The card's tap is dead too — no quick look for an unavailable item.
    await tester.tap(find.text('Everyday Bag'));
    await tester.pumpAndSettle();
    expect(find.text('Quick look'), findsNothing);
    expect(cart.addItemCalls, isEmpty);
  });

  testWidgets('the shelf count never claims more than it shows',
      (tester) async {
    final cart = _RecordingCartNotifier();
    final products = [
      for (var i = 1; i <= 8; i++)
        {'id': 'p$i', 'name': 'Item $i', 'price': 10, 'currency': 'GHS'},
    ];
    await tester.pumpWidget(buildWidget(cart: cart, products: products));

    // Six shown of eight — the label must say so.
    expect(find.text('6 of 8 items'), findsOneWidget);
    expect(find.text('8 items'), findsNothing);
  });

  testWidgets('the unavailable presentation covers the whole card',
      (tester) async {
    final cart = _RecordingCartNotifier();
    await tester.pumpWidget(buildWidget(
      cart: cart,
      products: [
        {
          'id': 'p1',
          'name': 'Everyday Bag',
          'price': 25,
          'currency': 'GHS',
          'available': false,
        },
      ],
    ));

    // The image/fallback AND the title are desaturated/dimmed — the
    // state is a whole-card presentation, not an image-only one.
    expect(find.byType(ColorFiltered), findsNWidgets(2));
    // The state line stays present and readable.
    expect(find.text('Currently unavailable'), findsOneWidget);
  });
}
