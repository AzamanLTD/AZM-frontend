import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/product_options.dart';
import 'package:azaman/widgets/marketplace/product_options_sheet.dart';

// The backend (storefrontProductConfigurationService.js) validates and prices
// a configured product; these cases mirror its rules so the app never builds
// a cart line the server refuses or prices differently.
void main() {
  group('parsing', () {
    test('a flat variant list is one required Size group', () {
      final g = parseProductOptions([
        {'label': 'Small', 'priceDelta': 0},
        {'label': 'Large', 'priceDelta': 2.5},
      ], null);
      expect(g, hasLength(1));
      expect(g.single.name, 'Size');
      expect(g.single.required, isTrue);
      expect(g.single.isVariant, isTrue);
      expect(g.single.options.map((o) => '${o.name}:${o.priceDelta}'), [
        'Small:0.0',
        'Large:2.5',
      ]);
    });

    test(
      'variant groups are required unless required:false; a map is required groups',
      () {
        final g = parseProductOptions([
          {
            'name': 'Size',
            'options': [
              {'name': 'M'},
              {'name': 'L', 'priceDelta': '1.25'},
            ],
          },
          {
            'name': 'Crust',
            'required': false,
            'values': ['Thin', 'Deep'],
          },
        ], null);
        expect(g.map((x) => '${x.name}:${x.required}'), [
          'Size:true',
          'Crust:false',
        ]);
        expect(g.first.options.last.priceDelta, 1.25);
        final m = parseProductOptions({
          'Colour': ['Red', 'Blue'],
        }, null);
        expect(m.single.name, 'Colour');
        expect(m.single.required, isTrue);
      },
    );

    test(
      'modifier groups are optional unless required:true, with a maximum',
      () {
        final g = parseProductOptions(null, [
          {
            'name': 'Add-ons',
            'maxSelection': 3,
            'options': [
              {'name': 'Cheese', 'priceDelta': 0.5},
              {'name': 'Bacon', 'priceDelta': 1},
            ],
          },
          {
            'name': 'Sauce',
            'required': true,
            'max': 0,
            'options': [
              {'name': 'Hot'},
            ],
          },
          {'name': 'Empty', 'options': []},
        ]);
        expect(g.map((x) => '${x.name}:${x.required}:${x.maxSelection}'), [
          'Add-ons:false:3',
          'Sauce:true:1',
        ]);
      },
    );

    test('JSON text is read; nothing to choose is no groups', () {
      expect(parseProductOptions('[{"label":"S"}]', '[]'), hasLength(1));
      expect(parseProductOptions(null, null), isEmpty);
      expect(parseProductOptions('not json', null), isEmpty);
    });
  });

  group('choosing and pricing', () {
    final groups = parseProductOptions(
      [
        {'label': 'Small', 'priceDelta': 0},
        {'label': 'Large', 'priceDelta': 2.5},
      ],
      [
        {
          'name': 'Add-ons',
          'maxSelection': 2,
          'options': [
            {'name': 'Cheese', 'priceDelta': 0.5},
            {'name': 'Bacon', 'priceDelta': 1},
          ],
        },
      ],
    );

    test('a required group must be chosen; a maximum is enforced', () {
      expect(optionSelectionProblem(groups, {}), 'Choose Size.');
      expect(
        optionSelectionProblem(groups, {
          'Size': ['Large'],
        }),
        isNull,
      );
      expect(
        optionSelectionProblem(groups, {
          'Size': ['Large'],
          'Add-ons': ['Cheese', 'Bacon', 'Egg'],
        }),
        'Add-ons: at most 2.',
      );
    });

    test('the price is the base plus the chosen deltas', () {
      expect(
        configuredUnitPrice(8, groups, {
          'Size': ['Large'],
          'Add-ons': ['Cheese', 'Bacon'],
        }),
        12.0,
      );
      expect(
        configuredUnitPrice(8, groups, {
          'Size': ['Small'],
        }),
        8.0,
      );
    });

    test('the cart form is {group: names}, sorted and comma-joined', () {
      expect(
        selectionAsVariants({
          'Size': ['Large'],
          'Add-ons': ['Bacon', 'Cheese'],
          'Empty': [],
        }),
        {'Size': 'Large', 'Add-ons': 'Bacon,Cheese'},
      );
    });
  });

  testWidgets(
    'the sheet: Add waits for the required choice, then returns the price and choice',
    (tester) async {
      final product = BusinessProduct.fromJson({
        'id': 'p1',
        'businessProfileId': 'b1',
        'name': 'Jollof',
        'slug': 'jollof',
        'priceUsdc': 8,
        'variants': [
          {'label': 'Small', 'priceDelta': 0},
          {'label': 'Large', 'priceDelta': 2.5},
        ],
        'modifierGroups': [
          {
            'name': 'Add-ons',
            'maxSelection': 2,
            'options': [
              {'name': 'Chicken', 'priceDelta': 1.5},
            ],
          },
        ],
      });
      expect(product.hasOptions, isTrue);
      ProductChoice? choice;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async => choice =
                      await ProductOptionsSheet.show(context, product: product),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final add = find.byKey(const ValueKey('option-add'));
      expect(tester.widget<FilledButton>(add).onPressed, isNull);
      expect(find.text('Choose Size.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('option-Size-Large')));
      await tester.tap(find.byKey(const ValueKey('option-Add-ons-Chicken')));
      await tester.tap(find.byKey(const ValueKey('option-qty-plus')));
      await tester.pump();
      expect(find.text('Add · \$24.00'), findsOneWidget); // (8 + 2.5 + 1.5) × 2
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(choice!.unitPrice, 12.0);
      expect(choice!.quantity, 2);
      expect(choice!.variants, {'Size': 'Large', 'Add-ons': 'Chicken'});
    },
  );
}
