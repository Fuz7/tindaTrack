import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinda_track/screens/analytics_screen.dart';
import 'package:tinda_track/services/product_service.dart';
import 'package:tinda_track/theme/app_theme.dart';

// Thursday 1 October 2026.
final _now = DateTime(2026, 10, 1, 15);

const _products = [
  Product(
    id: 'coke',
    name: 'Coke Mismo',
    stock: 20,
    sellCentavos: 2000,
    buyCentavos: 1500,
  ),
  Product(id: 'canton', name: 'Pancit Canton', stock: 2, sellCentavos: 1800),
];

final _sales = [
  Sale(
    id: 'a',
    receivedCentavos: 10000,
    completedAt: DateTime(2026, 10, 1, 9),
    items: const [
      SaleItem(
        productId: 'coke',
        name: 'Coke Mismo',
        unitCentavos: 2000,
        quantity: 3,
      ),
    ],
  ),
  Sale(
    id: 'b',
    receivedCentavos: 10000,
    completedAt: DateTime(2026, 9, 29, 9),
    items: const [
      SaleItem(
        productId: 'canton',
        name: 'Pancit Canton',
        unitCentavos: 1800,
        quantity: 1,
      ),
    ],
  ),
];

Widget _host({List<Sale>? sales, VoidCallback? onRestock}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: AnalyticsScreen(
      sales: Stream.value(sales ?? _sales),
      products: Stream.value(_products),
      lowStockThreshold: Stream.value(5),
      onRestock: onRestock ?? () {},
      clock: () => _now,
    ),
  ),
);

void _smallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('shows totals, best sellers and low stock', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('Last Month'), findsOneWidget);
    expect(find.text('Sep 2 – Oct 1'), findsOneWidget);
    expect(find.text('₱78.00'), findsOneWidget); // total sales
    expect(find.text('₱15.00'), findsOneWidget); // coke's profit only
    expect(find.text('Items with a buy price'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Best Sellers (Top 5)'), 200);
    expect(find.text('3 Units Sold'), findsOneWidget);
    expect(find.text('1 Unit Sold'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('2 Left'), 200);
    expect(find.text('Low Stock Alert (1 item)'), findsOneWidget);
  });

  Finder inSheet(String text) =>
      find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

  testWidgets('the period picker lists each option with its dates', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Last Month'));
    await tester.pumpAndSettle();

    expect(inSheet('Show sales for'), findsOneWidget);
    expect(inSheet('Today'), findsOneWidget);
    expect(inSheet('Oct 1'), findsOneWidget);
    expect(inSheet('Last 7 Days'), findsOneWidget);
    expect(inSheet('Sep 25 – Oct 1'), findsOneWidget);
    expect(inSheet('Custom Range'), findsOneWidget);
  });

  testWidgets('picking Today narrows the totals', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Last Month'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet('Today'));
    await tester.pumpAndSettle();

    expect(find.text('₱60.00'), findsWidgets); // today's coke sale
    expect(find.text('1 sale'), findsOneWidget);
  });

  testWidgets('a custom range from the date picker', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Last Month'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet('Custom Range'));
    await tester.pumpAndSettle();

    // Type the dates rather than tap a calendar.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '09/28/2026');
    await tester.enterText(fields.at(1), '09/30/2026');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Custom Range'), findsOneWidget);
    expect(find.text('Sep 28 – Sep 30'), findsOneWidget);
    // Only Tuesday 29 Sep's canton sale falls in it.
    expect(find.text('1 sale'), findsOneWidget);
    expect(find.text('₱18.00'), findsWidgets);
  });

  Future<void> pick(WidgetTester tester, String option) async {
    await tester.tap(find.byType(InkWell).first); // the period button
    await tester.pumpAndSettle();
    await tester.tap(inSheet(option));
    await tester.pumpAndSettle();
  }

  testWidgets('Last Month is charted by week', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('Sep 2 – Oct 1 · by week'), findsOneWidget);
    // The week holding today starts selected.
    expect(find.text('Sep 30 – Oct 1 (2 days)'), findsOneWidget);

    // Its total and title sit flush against the card's right edge.
    final title = tester.getTopRight(find.text('Sep 30 – Oct 1 (2 days)'));
    final card = tester.getTopRight(
      find
          .ancestor(
            of: find.text('Sales Trends'),
            matching: find.byType(Container),
          )
          .last,
    );
    final amount = tester.getTopRight(find.text('₱60.00').first);
    expect(
      title.dx,
      moreOrLessEquals(card.dx - AppSpacing.gutter - 1, epsilon: 1),
    );
    expect(amount.dx, moreOrLessEquals(title.dx, epsilon: 1));
    expect(find.bySemanticsLabel('Sep 23 – 29: ₱18.00'), findsOneWidget);
  });

  testWidgets('Last 7 Days is charted by day; tap a bar for its total', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await pick(tester, 'Last 7 Days');

    expect(find.text('Sep 25 – Oct 1 · by day'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Tuesday, Sep 29: ₱18.00'));
    await tester.pumpAndSettle();
    expect(find.text('Tuesday, Sep 29'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
  });

  testWidgets('bars show their amounts, and a ₱ scale runs alongside', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await pick(tester, 'Last 7 Days');

    // Over the bars: today's ₱60 and Tuesday's ₱18.
    expect(find.text('₱60.00'), findsWidgets);
    expect(find.text('₱18.00'), findsWidgets);
    // The scale: ₱60 peak → ₱20 steps.
    for (final tick in ['₱0', '₱20', '₱40', '₱60']) {
      expect(find.text(tick), findsOneWidget);
    }
  });

  testWidgets('every chart fits a small phone', (tester) async {
    _smallPhone(tester);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    for (final option in ['Today', 'Last 7 Days', 'Last Month']) {
      await tester.ensureVisible(find.byType(InkWell).first);
      await pick(tester, option);
      expect(tester.takeException(), isNull, reason: option);
    }
  });

  testWidgets('Today is charted by hour', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await pick(tester, 'Today');

    expect(find.text('Oct 1 · by hour'), findsOneWidget);
    // 3 PM now: that hour starts selected.
    expect(find.text('3 PM – 4 PM'), findsOneWidget);
    expect(find.bySemanticsLabel('9 AM – 10 AM: ₱60.00'), findsOneWidget);
    // Too many bars for amounts on each; the scale carries them.
    expect(find.text('₱60'), findsOneWidget);
  });

  testWidgets('Restock Now', (tester) async {
    var restocked = false;
    await tester.pumpWidget(_host(onRestock: () => restocked = true));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('RESTOCK NOW'), 200);
    await tester.ensureVisible(find.text('RESTOCK NOW'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RESTOCK NOW'));
    expect(restocked, isTrue);
  });

  testWidgets('no sales yet', (tester) async {
    await tester.pumpWidget(_host(sales: const []));
    await tester.pumpAndSettle();

    expect(find.text('₱0.00'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('No products sold in this period yet.'),
      200,
    );
  });

  testWidgets('fits a small phone', (tester) async {
    _smallPhone(tester);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
