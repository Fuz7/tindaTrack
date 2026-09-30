import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinda_track/screens/transactions_screen.dart';
import 'package:tinda_track/services/product_service.dart';
import 'package:tinda_track/theme/app_theme.dart';

final _now = DateTime(2026, 9, 30, 15);

Sale _sale(
  String id,
  DateTime at, {
  List<SaleItem> items = const [
    SaleItem(
      productId: 'coke',
      name: 'Coke Mismo',
      unitCentavos: 2000,
      quantity: 2,
    ),
    SaleItem(name: 'Manual Entry', unitCentavos: 500, quantity: 1),
  ],
  DateTime? voidedAt,
  String? customer,
}) => Sale(
  id: id,
  items: items,
  receivedCentavos: 5000,
  completedAt: at,
  voidedAt: voidedAt,
  customerName: customer,
  cashierUid: 'u',
  cashierName: 'Owner',
);

final _history = [
  _sale('abcdef111', DateTime(2026, 9, 30, 14, 32), customer: 'Aling Nena'),
  _sale(
    'voided222',
    DateTime(2026, 9, 30, 14, 10),
    voidedAt: DateTime(2026, 9, 30, 14, 20),
  ),
  _sale(
    'bread3333',
    DateTime(2026, 9, 30, 13, 55),
    items: const [
      SaleItem(
        productId: 'bread',
        name: 'Gardenia',
        unitCentavos: 7500,
        quantity: 1,
      ),
    ],
  ),
  _sale('yday44444', DateTime(2026, 9, 29, 18)),
];

Future<List<Sale>> _pump(WidgetTester tester) async {
  final refunded = <Sale>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: TransactionsScreen(
          sales: Stream.value(_history),
          onRefund: (s) async => refunded.add(s),
          products: Stream.value(const []),
          onEdit:
              (
                s, {
                required items,
                required receivedCentavos,
                required customerName,
              }) async => s,
          now: () => _now,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return refunded;
}

void main() {
  testWidgets('shows the day\'s sales with its totals', (tester) async {
    await _pump(tester);

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('TX-ABCDEF'), findsOneWidget);
    expect(find.text('TX-BREAD3'), findsOneWidget);
    expect(find.text('TX-YDAY44'), findsNothing); // yesterday
    expect(find.text('14:32'), findsOneWidget);
    expect(find.text('3 Items Purchased · by Owner'), findsNWidgets(2));
    // Refunds don't count: ₱45 + ₱75, two orders.
    expect(find.text('₱120.00'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('VOIDED'), findsOneWidget);
  });

  testWidgets('a card opens to its lines and a refund', (tester) async {
    final refunded = await _pump(tester);

    await tester.tap(find.text('TX-ABCDEF'));
    await tester.pumpAndSettle();
    expect(find.text('2x Coke Mismo'), findsOneWidget);
    expect(find.text('₱40.00'), findsOneWidget);
    expect(find.text('Cash received'), findsOneWidget);

    await tester.tap(find.text('REFUND'));
    await tester.pumpAndSettle();
    expect(find.text('Refund TX-ABCDEF?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(refunded, isEmpty);

    await tester.tap(find.text('REFUND'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    expect(refunded.single.id, 'abcdef111');
    expect(find.text('TX-ABCDEF refunded.'), findsOneWidget);
  });

  testWidgets('a voided sale shows when it was refunded, no button', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('TX-VOIDED'));
    await tester.pumpAndSettle();

    expect(
      find.text('Refunded 14:20 — items went back to stock.'),
      findsOneWidget,
    );
    expect(find.text('REFUND'), findsNothing);
  });

  testWidgets('search matches item names and TX codes', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'gardenia');
    await tester.pump();
    expect(find.text('TX-BREAD3'), findsOneWidget);
    expect(find.text('TX-ABCDEF'), findsNothing);
    // The day's totals ignore the search.
    expect(find.text('₱120.00'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'tx-abc');
    await tester.pump();
    expect(find.text('TX-ABCDEF'), findsOneWidget);
    expect(find.text('TX-BREAD3'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No matching sales'), findsOneWidget);
  });

  testWidgets('another day can be picked, and the chip goes back', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byTooltip('Pick a day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('29'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('TX-YDAY44'), findsOneWidget);
    expect(find.text('TX-ABCDEF'), findsNothing);

    await tester.tap(find.byTooltip('Back to today'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('TX-ABCDEF'), findsOneWidget);
  });

  testWidgets('fits a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester);
    await tester.tap(find.text('TX-ABCDEF'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards name the customer and cashier; EDIT opens the editor', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Aling Nena'), findsOneWidget);
    expect(find.text('Walk-in Customer'), findsNWidgets(2));
    expect(find.text('3 Items Purchased · by Owner'), findsNWidgets(2));

    // Searchable by customer, too.
    await tester.enterText(find.byType(TextField), 'nena');
    await tester.pump();
    expect(find.text('TX-BREAD3'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    await tester.tap(find.text('TX-ABCDEF'));
    await tester.pumpAndSettle();
    expect(find.text('EDIT'), findsOneWidget);
    expect(find.text('REFUND'), findsOneWidget);

    await tester.tap(find.text('EDIT'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Transaction'), findsOneWidget);
    expect(find.text('Update Transaction'), findsOneWidget);
  });

  testWidgets('a refunded sale offers no edit', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('TX-VOIDED'));
    await tester.pumpAndSettle();
    expect(find.text('EDIT'), findsNothing);
  });
}
