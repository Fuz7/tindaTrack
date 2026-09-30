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
    category: 'Drinks',
  ),
  Product(
    id: 'b',
    name: 'Lucky Me! Pancit Canton',
    stock: 4,
    sellCentavos: 1800,
    category: 'Pantry',
  ),
  Product(id: 'c', name: 'Gardenia White Bread', stock: 0, sellCentavos: 7500),
];

Widget _inventory({
  Stream<List<Product>>? products,
  int lowStockThreshold = 5,
}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: InventoryScreen(
      products: products ?? Stream.value(_products),
      lowStockThreshold: Stream.value(lowStockThreshold),
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

    await tester.tap(find.text('UPDATE STOCK'));
    await tester.pumpAndSettle();
    expect(find.text('PRICING DETAILS'), findsNothing);
    expect(find.text('Updating stock is not built yet.'), findsOneWidget);
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
}
