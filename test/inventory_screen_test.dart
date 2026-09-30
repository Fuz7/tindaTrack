import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinda_track/screens/inventory_screen.dart';
import 'package:tinda_track/services/product_service.dart';
import 'package:tinda_track/theme/app_theme.dart';

const _products = [
  Product(
    id: 'a',
    name: 'Royal Tru Orange 1.5L',
    stock: 24,
    sellCentavos: 8500,
    buyCentavos: 6500,
    sku: 'RT-001',
    categories: ['Drinks'],
  ),
  Product(
    id: 'b',
    name: 'Lucky Me! Pancit Canton',
    stock: 4,
    sellCentavos: 1800,
    categories: ['Pantry'],
  ),
  Product(id: 'c', name: 'Gardenia White Bread', stock: 0, sellCentavos: 7500),
];

Widget _inventory({
  Stream<List<Product>>? products,
  int lowStockThreshold = 5,
  Future<void> Function(Product, ProductDraft)? onUpdate,
  Future<void> Function(String)? onDelete,
  Future<void> Function(Product, int, {StockReason? reason, String? note})?
  onAdjust,
}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: InventoryScreen(
      products: products ?? Stream.value(_products),
      lowStockThreshold: Stream.value(lowStockThreshold),
      onSaveProduct: (_) async {},
      onUpdateProduct: onUpdate ?? (_, _) async {},
      onDeleteProduct: onDelete ?? (_) async {},
      onAdjustStock: onAdjust ?? (_, _, {reason, note}) async {},
    ),
  ),
);

void main() {
  testWidgets('lists products with counts and stock colors', (tester) async {
    await tester.pumpWidget(_inventory());
    await tester.pumpAndSettle();

    expect(find.text('TOTAL SKU'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // SKUs
    expect(find.text('2'), findsOneWidget); // low + out alerts
    expect(find.text('Royal Tru Orange 1.5L'), findsOneWidget);
    expect(find.text('₱85.00'), findsOneWidget);

    Color colorOf(String text) =>
        tester.widget<Text>(find.text(text)).style!.color!;
    expect(colorOf('Stock: 24 units'), AppColors.statusInStock);
    expect(colorOf('Stock: 4 units'), AppColors.statusLowStock);
    expect(colorOf('Stock: 0 units'), AppColors.statusOutOfStock);
  });

  testWidgets('filters by category chip and by search', (tester) async {
    await tester.pumpWidget(_inventory());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Drinks'));
    await tester.pump();
    expect(find.text('Royal Tru Orange 1.5L'), findsOneWidget);
    expect(find.text('Gardenia White Bread'), findsNothing);

    await tester.tap(find.text('All Items'));
    await tester.enterText(find.byType(TextField), 'canton');
    await tester.pump();
    expect(find.text('Lucky Me! Pancit Canton'), findsOneWidget);
    expect(find.text('Royal Tru Orange 1.5L'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No matching products'), findsOneWidget);
  });

  testWidgets('tapping a product opens its detail drawer', (tester) async {
    await tester.pumpWidget(_inventory());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Royal Tru Orange 1.5L'));
    await tester.pumpAndSettle();

    expect(find.text('IN STOCK'), findsOneWidget);
    expect(find.text('RT-001'), findsOneWidget);
    expect(find.text('PRICING DETAILS'), findsOneWidget);
    expect(find.text('₱65.00'), findsOneWidget);
    expect(find.text('₱20.00 (23.5%)'), findsOneWidget);
  });

  group('Update Stock', () {
    Future<List<(Product, int, StockReason?, String?)>> openUpdater(
      WidgetTester tester,
    ) async {
      final saved = <(Product, int, StockReason?, String?)>[];
      await tester.pumpWidget(
        _inventory(
          onAdjust: (p, n, {reason, note}) async =>
              saved.add((p, n, reason, note)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Royal Tru Orange 1.5L')); // 24 in stock
      await tester.pumpAndSettle();
      await tester.tap(find.text('UPDATE STOCK'));
      await tester.pumpAndSettle();
      return saved;
    }

    Finder field() => find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        )
        .first;

    testWidgets('swaps the buttons for the stock stepper', (tester) async {
      await openUpdater(tester);

      expect(find.text('CURRENT STOCK'), findsOneWidget);
      expect(tester.widget<TextField>(field()).controller!.text, '24');
      expect(find.text('Save Stock'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('EDIT PRODUCT'), findsNothing);
      // Nothing to save until the count changes.
      expect(find.text('No change from 24.'), findsOneWidget);
      await tester.tap(find.text('Save Stock'));
      await tester.pump();
      expect(find.text('CURRENT STOCK'), findsOneWidget);
    });

    testWidgets('steps and saves the new count', (tester) async {
      final saved = await openUpdater(tester);

      await tester.tap(find.byTooltip('Add one'));
      await tester.tap(find.byTooltip('Add one'));
      await tester.pump();
      expect(find.text('+2 from 24'), findsOneWidget);

      await tester.tap(find.text('Save Stock'));
      await tester.pumpAndSettle();

      expect(saved.single.$1.id, 'a');
      expect(saved.single.$2, 26);
      expect(find.text('CURRENT STOCK'), findsNothing); // drawer closed
      expect(
        find.text('“Royal Tru Orange 1.5L” stock: 24 → 26.'),
        findsOneWidget,
      );
    });

    testWidgets('an increase needs no reason', (tester) async {
      final saved = await openUpdater(tester);

      await tester.enterText(field(), '30');
      await tester.pump();
      expect(find.text('REASON FOR DECREASE'), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(saved.single.$2, 30);
      expect(saved.single.$3, isNull);
    });

    testWidgets('a decrease needs a reason before it can be saved', (
      tester,
    ) async {
      final saved = await openUpdater(tester);

      await tester.enterText(field(), '21');
      await tester.pump();
      expect(find.text('−3 from 24'), findsOneWidget);
      expect(find.text('REASON FOR DECREASE'), findsOneWidget);
      expect(find.text('Pick a reason to save a decrease.'), findsOneWidget);

      await tester.ensureVisible(find.text('Save Stock'));
      await tester.tap(find.text('Save Stock'));
      await tester.pump();
      expect(saved, isEmpty);

      await tester.ensureVisible(find.text('Damaged / Broken'));
      await tester.tap(find.text('Damaged / Broken'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Note (optional), e.g. dropped by delivery',
        ),
        ' dropped a case ',
      );
      await tester.ensureVisible(find.text('Save Stock'));
      await tester.tap(find.text('Save Stock'));
      await tester.pumpAndSettle();

      final (product, count, reason, note) = saved.single;
      expect(product.id, 'a');
      expect(count, 21);
      expect(reason, StockReason.damaged);
      expect(note, 'dropped a case');
      expect(
        find.text('“Royal Tru Orange 1.5L” stock: 24 → 21 (Damaged / Broken).'),
        findsOneWidget,
      );
    });

    testWidgets('"Other" needs a note', (tester) async {
      final saved = await openUpdater(tester);

      await tester.enterText(field(), '20');
      await tester.pump();
      await tester.ensureVisible(find.text('Other'));
      await tester.tap(find.text('Other'));
      await tester.pump();
      expect(find.text('Add a note for "Other".'), findsOneWidget);

      await tester.ensureVisible(find.text('Save Stock'));
      await tester.tap(find.text('Save Stock'));
      await tester.pump();
      expect(saved, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextField, 'What happened? (required)'),
        'Given to barangay event',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Save Stock'));
      await tester.tap(find.text('Save Stock'));
      await tester.pumpAndSettle();

      expect(saved.single.$3, StockReason.other);
      expect(saved.single.$4, 'Given to barangay event');
    });

    testWidgets('a blank count cannot be saved', (tester) async {
      final saved = await openUpdater(tester);

      await tester.enterText(field(), '');
      await tester.pump();
      expect(find.text('Enter the count on the shelf.'), findsOneWidget);
      await tester.tap(find.text('Save Stock'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
    });

    testWidgets('Cancel goes back to the drawer buttons', (tester) async {
      final saved = await openUpdater(tester);
      await tester.tap(find.byTooltip('Add one'));
      await tester.pump();

      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('CURRENT STOCK'), findsNothing);
      expect(find.text('EDIT PRODUCT'), findsOneWidget);
      expect(find.text('PRICING DETAILS'), findsOneWidget); // still open
      expect(saved, isEmpty);
    });

    testWidgets('does not go below zero', (tester) async {
      await openUpdater(tester);
      await tester.enterText(field(), '1');
      await tester.pump();

      await tester.tap(find.byTooltip('Remove one'));
      await tester.pump();
      await tester.tap(find.byTooltip('Remove one'));
      await tester.pump();
      expect(tester.widget<TextField>(field()).controller!.text, '0');
    });

    testWidgets('fits a small phone', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await openUpdater(tester);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a product with no buy price shows dashes', (tester) async {
    await tester.pumpWidget(_inventory());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gardenia White Bread'));
    await tester.pumpAndSettle();

    expect(find.text('OUT OF STOCK'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(4)); // SKU, category, buy, margin
  });

  testWidgets('shows loading, then an empty catalog message', (tester) async {
    final products = StreamController<List<Product>>();
    addTearDown(products.close);
    await tester.pumpWidget(_inventory(products: products.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    products.add(const []);
    await tester.pump();
    expect(find.text('No products yet'), findsOneWidget);
  });

  testWidgets('fits a small phone without overflowing', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_inventory());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Royal Tru Orange 1.5L'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('Add New opens the add product page', (tester) async {
    await tester.pumpWidget(_inventory());
    await tester.pumpAndSettle();

    await tester.tap(find.text('ADD NEW'));
    await tester.pumpAndSettle();

    expect(find.text('Add New Product'), findsOneWidget);
    // Categories the store already uses are offered alongside the defaults.
    expect(find.text('Drinks'), findsOneWidget);
  });

  testWidgets('products with alerts off are left out of the alerts', (
    tester,
  ) async {
    await tester.pumpWidget(
      _inventory(
        products: Stream.value(const [
          Product(id: 'a', name: 'Tracked Low', stock: 2, sellCentavos: 100),
          Product(
            id: 'b',
            name: 'Untracked Low',
            stock: 2,
            sellCentavos: 100,
            stockAlerts: false,
          ),
          Product(
            id: 'c',
            name: 'Untracked Out',
            stock: 0,
            sellCentavos: 100,
            stockAlerts: false,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    // Only "Tracked Low" counts.
    final alerts = find.ancestor(
      of: find.text('ALERTS'),
      matching: find.byType(Column),
    );
    expect(
      find.descendant(of: alerts.first, matching: find.text('1')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.notifications_off_outlined), findsNWidgets(2));

    // Untracked stock isn't flagged amber.
    Color colorOf(String text) =>
        tester.widget<Text>(find.textContaining(text).first).style!.color!;
    expect(colorOf('Stock: 2'), AppColors.statusLowStock); // tracked one
    await tester.tap(find.text('Untracked Low'));
    await tester.pumpAndSettle();
    expect(find.text('IN STOCK'), findsOneWidget);
    expect(find.text('Low-stock alerts off'), findsOneWidget);
  });

  testWidgets('Edit Product opens the form filled in, and saves edits', (
    tester,
  ) async {
    final updates = <(Product, ProductDraft)>[];
    await tester.pumpWidget(
      _inventory(onUpdate: (p, d) async => updates.add((p, d))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Royal Tru Orange 1.5L'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EDIT PRODUCT'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Product'), findsOneWidget);
    // Stock is changed through Update Stock, not here.
    expect(find.textContaining('STOCK COUNT'), findsNothing);
    String textOf(String value) => tester
        .widget<TextFormField>(find.widgetWithText(TextFormField, value))
        .controller!
        .text;
    expect(textOf('Royal Tru Orange 1.5L'), 'Royal Tru Orange 1.5L');
    expect(textOf('85.00'), '85.00');
    expect(textOf('65.00'), '65.00');
    expect(textOf('RT-001'), 'RT-001'); // kept, not re-suggested
    expect(find.text('MAIN'), findsOneWidget); // Drinks

    await tester.enterText(find.widgetWithText(TextFormField, '85.00'), '90');
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    final (original, draft) = updates.single;
    expect(original.id, 'a');
    expect(draft.sellCentavos, 9000);
    expect(draft.stock, 24); // untouched, so no stock change is sent
    expect(draft.sku, 'RT-001');
    expect(draft.categories, ['Drinks']);
    expect(find.text('“Royal Tru Orange 1.5L” updated.'), findsOneWidget);
  });

  testWidgets('Delete Product asks first', (tester) async {
    final deleted = <String>[];
    await tester.pumpWidget(
      _inventory(onDelete: (id) async => deleted.add(id)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gardenia White Bread'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EDIT PRODUCT'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Delete Product'));
    await tester.tap(find.text('Delete Product'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);
    expect(find.text('Edit Product'), findsOneWidget);

    await tester.tap(find.text('Delete Product'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, ['c']);
    expect(find.text('“Gardenia White Bread” deleted.'), findsOneWidget);
  });

  group('category filter', () {
    // 10 categories; "Drinks" busiest, then Snacks, Pantry, Frozen…
    final many = [
      for (final (i, spec) in [
        ('Drinks', 5),
        ('Snacks', 4),
        ('Pantry', 3),
        ('Frozen', 2),
        ('Bakery', 1),
        ('Condiments', 1),
        ('Dairy', 1),
        ('Household', 1),
        ('Personal Care', 1),
        ('School Supplies', 1),
      ].indexed)
        for (var n = 0; n < spec.$2; n++)
          Product(
            id: '$i-$n',
            name: '${spec.$1} item $n',
            stock: 10,
            sellCentavos: 100,
            categories: [spec.$1],
          ),
    ];

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(_inventory(products: Stream.value(many)));
      await tester.pumpAndSettle();
    }

    Finder chip(String label) => find.descendant(
      of: find.byType(SingleChildScrollView).first,
      matching: find.text(label),
    );

    testWidgets('shows only the chips that fit, busiest first', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester);

      final row = find.byType(SingleChildScrollView).first;
      final shown = [
        for (final c in [
          'Drinks',
          'Snacks',
          'Pantry',
          'Frozen',
          'Bakery',
          'Condiments',
          'Dairy',
          'Household',
          'Personal Care',
          'School Supplies',
        ])
          if (find
              .descendant(of: row, matching: find.text(c))
              .evaluate()
              .isNotEmpty)
            c,
      ];
      // The badge counts exactly what's left out.
      expect(find.text('+${10 - shown.length}'), findsOneWidget);

      // Nothing sits past the edge, so there is nothing to swipe to.
      final rowRight = tester.getRect(row).right;
      for (final c in shown) {
        expect(tester.getRect(find.text(c)).right, lessThanOrEqualTo(rowRight));
      }
      await tester.drag(row, const Offset(-300, 0));
      await tester.pump();
      expect(tester.getRect(find.text('All Items')).left, greaterThan(0));
    });

    testWidgets('with room, the busiest categories lead', (tester) async {
      await pump(tester); // the default 800px-wide test screen
      final row = find.byType(SingleChildScrollView).first;
      Finder inRow(String c) =>
          find.descendant(of: row, matching: find.text(c));

      expect(inRow('Drinks'), findsOneWidget);
      expect(inRow('Snacks'), findsOneWidget);
      expect(inRow('School Supplies'), findsNothing);
      expect(
        tester.getRect(inRow('Drinks')).left,
        lessThan(tester.getRect(inRow('Snacks')).left),
      );
    });

    testWidgets('the sheet lists every category with counts', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();

      expect(find.text('CATEGORY'), findsOneWidget);
      expect(find.text('Bakery'), findsOneWidget); // not in the quick row
      // More than eight: searchable.
      await tester.enterText(
        find.widgetWithText(TextField, 'Find a category'),
        'sch',
      );
      await tester.pump();
      expect(find.text('School Supplies'), findsOneWidget);
      expect(find.text('Bakery'), findsNothing);

      await tester.tap(find.text('School Supplies'));
      await tester.pumpAndSettle();

      // Filtered, and the pick joins the quick row in place of the 4th.
      expect(find.text('School Supplies item 0'), findsOneWidget);
      expect(find.text('Drinks item 0'), findsNothing);
      expect(chip('School Supplies'), findsOneWidget);
      expect(chip('Frozen'), findsNothing);
    });

    testWidgets('All Items from the sheet clears the filter', (tester) async {
      await pump(tester);
      await tester.tap(chip('Snacks'));
      await tester.pumpAndSettle();
      expect(find.text('Drinks item 0'), findsNothing);

      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Items').last);
      await tester.pumpAndSettle();
      expect(find.text('Drinks item 0'), findsOneWidget);
    });

    testWidgets('closing the sheet keeps the filter', (tester) async {
      await pump(tester);
      await tester.tap(chip('Snacks'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Snacks item 0'), findsOneWidget);
      expect(find.text('Drinks item 0'), findsNothing);
    });
  });

  group('stock filter', () {
    const stocked = [
      Product(id: 'ok', name: 'Plenty', stock: 50, sellCentavos: 100),
      Product(id: 'low', name: 'Running Low', stock: 2, sellCentavos: 100),
      Product(id: 'out', name: 'Sold Out', stock: 0, sellCentavos: 100),
      Product(
        id: 'quiet',
        name: 'Quiet Out',
        stock: 0,
        sellCentavos: 100,
        stockAlerts: false,
      ),
    ];

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(_inventory(products: Stream.value(stocked)));
      await tester.pumpAndSettle();
    }

    List<String> listed(WidgetTester tester) => [
      for (final n in ['Plenty', 'Running Low', 'Sold Out', 'Quiet Out'])
        if (find.text(n).evaluate().isNotEmpty) n,
    ];

    testWidgets('the Alerts tile filters to what it counts', (tester) async {
      await pump(tester);

      await tester.tap(find.text('ALERTS'));
      await tester.pumpAndSettle();
      expect(listed(tester), ['Running Low', 'Sold Out']);
      expect(find.text('Needs attention'), findsOneWidget); // active chip

      // Tapping it again clears it.
      await tester.tap(find.text('ALERTS'));
      await tester.pumpAndSettle();
      expect(listed(tester), hasLength(4));
    });

    testWidgets('the sheet offers low and out of stock, with counts', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();

      expect(find.text('Low stock (1)'), findsOneWidget);
      expect(find.text('Out of stock (2)'), findsOneWidget);
      expect(find.text('Needs attention (2)'), findsOneWidget);

      await tester.tap(find.text('Out of stock (2)'));
      await tester.pumpAndSettle();
      // Applied at once; the sheet stays open for a category too.
      expect(find.text('Filters'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // Out of stock includes products with alerts off.
      expect(listed(tester), ['Sold Out', 'Quiet Out']);

      await tester.tap(find.byTooltip('Clear stock filter'));
      await tester.pumpAndSettle();
      expect(listed(tester), hasLength(4));
    });

    testWidgets('stock and category filters combine', (tester) async {
      await tester.pumpWidget(
        _inventory(
          products: Stream.value(const [
            Product(
              id: 'a',
              name: 'Low Drink',
              stock: 1,
              sellCentavos: 100,
              categories: ['Drinks'],
            ),
            Product(
              id: 'b',
              name: 'Low Snack',
              stock: 1,
              sellCentavos: 100,
              categories: ['Snacks'],
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ALERTS'));
      await tester.tap(find.text('Drinks'));
      await tester.pumpAndSettle();

      expect(find.text('Low Drink'), findsOneWidget);
      expect(find.text('Low Snack'), findsNothing);
    });
  });
}
