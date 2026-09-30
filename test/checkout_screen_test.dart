import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinda_track/screens/checkout_screen.dart';
import 'package:tinda_track/services/product_service.dart';
import 'package:tinda_track/theme/app_theme.dart';

const _items = [
  SaleItem(
    productId: 'canton',
    name: 'Pancit Canton',
    unitCentavos: 1850,
    quantity: 2,
  ),
  SaleItem(
    productId: 'coke',
    name: 'Coke 500ml',
    unitCentavos: 2500,
    quantity: 1,
  ),
  SaleItem(name: 'Manual Entry', unitCentavos: 6500, quantity: 1),
]; // total ₱127.00

Future<List<int>> _open(WidgetTester tester) async {
  final received = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CheckoutScreen(
                  items: _items,
                  onComplete: (items, r) async {
                    received.add(r);
                    return Sale(
                      id: 's',
                      items: items,
                      receivedCentavos: r,
                      completedAt: DateTime(2026),
                    );
                  },
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return received;
}

Finder get _amount => find.byType(TextField);
String _amountText(WidgetTester tester) =>
    tester.widget<TextField>(_amount).controller!.text;

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pump();
}

bool _canComplete(WidgetTester tester) =>
    tester
        .widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text('COMPLETE SALE'),
            matching: find.bySubtype<ButtonStyleButton>(),
          ),
        )
        .onPressed !=
    null;

void main() {
  testWidgets('shows the order and total, with no discount row', (
    tester,
  ) async {
    await _open(tester);

    // Collapsed: a count and a preview of the names, total in view.
    expect(find.text('ORDER SUMMARY · 4 ITEMS'), findsOneWidget);
    expect(
      find.text('Pancit Canton, Coke 500ml, Manual Entry'),
      findsOneWidget,
    );
    expect(find.text('Qty: 2 × ₱18.50'), findsNothing);
    expect(find.text('₱127.00'), findsOneWidget);

    // Open: every line.
    await tester.tap(find.text('ORDER SUMMARY · 4 ITEMS'));
    await tester.pumpAndSettle();
    expect(find.text('Qty: 2 × ₱18.50'), findsOneWidget);
    expect(find.text('₱37.00'), findsOneWidget);

    // And closed again.
    await tester.tap(find.text('ORDER SUMMARY · 4 ITEMS'));
    await tester.pumpAndSettle();
    expect(find.text('Qty: 2 × ₱18.50'), findsNothing);
    expect(find.text('CASH'), findsOneWidget);
    expect(find.textContaining('Discount'), findsNothing);
    expect(find.textContaining('Promo'), findsNothing);
    expect(_canComplete(tester), isFalse);
  });

  testWidgets('EXACT fills in the total, with no change', (tester) async {
    final received = await _open(tester);

    await _tap(tester, 'EXACT ₱127.00');
    expect(_amountText(tester), '127.00');
    expect(find.text('CHANGE DUE'), findsOneWidget);
    expect(_canComplete(tester), isTrue);

    await _tap(tester, 'COMPLETE SALE');
    await tester.pumpAndSettle();
    expect(received, [12700]);
    expect(find.text('Sale completed.'), findsOneWidget);
  });

  testWidgets('quick cash adds up and shows the change', (tester) async {
    await _open(tester);

    await _tap(tester, '₱100');
    expect(find.text('SHORT BY'), findsOneWidget);
    expect(find.text('₱27.00'), findsOneWidget);
    expect(_canComplete(tester), isFalse);

    await _tap(tester, '₱50');
    expect(_amountText(tester), '150.00');
    expect(find.text('CHANGE DUE'), findsOneWidget);
    expect(find.text('₱23.00'), findsOneWidget);
    expect(_canComplete(tester), isTrue);

    await _tap(tester, 'CLEAR');
    expect(_amountText(tester), isEmpty);
    expect(_canComplete(tester), isFalse);
  });

  testWidgets('a typed amount works too', (tester) async {
    final received = await _open(tester);

    await tester.enterText(_amount, '200');
    await tester.pump();
    expect(find.text('₱73.00'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(received, [20000]);
  });

  testWidgets('fits a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester);
    expect(tester.takeException(), isNull);
  });
}
