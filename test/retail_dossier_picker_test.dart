import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';
import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/widgets/marketplace/retail_dossier_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records every shared-tray mutation the commit path asks for, so the
/// single-commit contract is guarded without touching the network.
class _RecordingCartNotifier extends CartNotifier {
  final List<Map<String, dynamic>> addItemCalls = [];
  int startNewCartCalls = 0;

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
      'unitPrice': unitPrice,
      'experiencePreset': experiencePreset,
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
  }) {
    startNewCartCalls++;
  }
}

RetailProduct _product({
  bool available = true,
  Map<String, dynamic> variants = const {},
}) {
  return RetailProduct(
    id: 'prod-1',
    name: 'Everyday Bag',
    price: 25,
    currency: 'GHS',
    variants: variants,
    available: available,
  );
}

void main() {
  /// Pumps a root route, then pushes the picker as the top route — a
  /// successful commit pops exactly one route.
  Future<void> pumpPicker(
    WidgetTester tester,
    _RecordingCartNotifier cart,
    RetailProduct product,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [cartProvider.overrideWith((ref) => cart)],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: Text('dossier root'))),
        ),
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: Center(
                child: RetailDossierPicker(
                  product: product,
                  businessProfileId: 'biz-1',
                  businessName: 'Azaman Retail',
                ),
              ),
            ),
          ),
        );
    await tester.pumpAndSettle();
  }

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

  testWidgets('unavailable products cannot commit', (tester) async {
    final cart = _RecordingCartNotifier();
    await pumpPicker(tester, cart, _product(available: false));

    expect(find.text('Unavailable'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(cart.addItemCalls, isEmpty);
  });

  testWidgets('each required variant group must have a selection', (
    tester,
  ) async {
    final cart = _RecordingCartNotifier();
    await pumpPicker(
      tester,
      cart,
      _product(
        variants: {
          'Size': ['S', 'M', 'L'],
          'Fit': ['Regular', 'Slim'],
        },
      ),
    );

    FilledButton button() =>
        tester.widget<FilledButton>(find.byType(FilledButton));

    // No selection yet — commit is gated.
    expect(button().onPressed, isNull);

    // Only Size picked — Fit still gates the commit.
    await tester.tap(find.text('M'));
    await tester.pumpAndSettle();
    expect(button().onPressed, isNull);

    // Both groups selected — commit is live.
    await tester.tap(find.text('Regular'));
    await tester.pumpAndSettle();
    expect(button().onPressed, isNotNull);
    expect(cart.addItemCalls, isEmpty);
  });

  testWidgets('quantity starts at one and never decrements below one', (
    tester,
  ) async {
    final cart = _RecordingCartNotifier();
    await pumpPicker(tester, cart, _product());

    expect(find.text('1'), findsOneWidget);
    final decrease = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Decrease quantity',
      ),
    );
    expect(decrease.onPressed, isNull);

    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byTooltip('Decrease quantity'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a valid add calls the shared cart mutation exactly once', (
    tester,
  ) async {
    final cart = _RecordingCartNotifier();
    await pumpPicker(
      tester,
      cart,
      _product(
        variants: {
          'Size': ['S', 'M', 'L'],
          'Fit': ['Regular', 'Slim'],
        },
      ),
    );

    await tester.tap(find.text('M'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Regular'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add to bag'));
    await tester.pumpAndSettle();

    expect(cart.addItemCalls, hasLength(1));
    expect(cart.addItemCalls.single, {
      'businessProfileId': 'biz-1',
      'businessName': 'Azaman Retail',
      'productId': 'prod-1',
      'name': 'Everyday Bag',
      'unitPrice': 25.0,
      'experiencePreset': 'SHOP_FLOOR',
      'quantity': 2,
      'variants': {'Size': 'M', 'Fit': 'Regular'},
    });
    // A successful commit closes the dossier exactly once.
    expect(find.text('dossier root'), findsOneWidget);
    expect(find.text('Add to bag'), findsNothing);
  });
}
