import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinda_track/screens/edit_transaction_screen.dart';
import 'package:tinda_track/services/product_service.dart';
import 'package:tinda_track/theme/app_theme.dart';

final _sale = Sale(
  id: 'abcdef123',
  items: const [
    SaleItem(productId: 'coke', name: 'Coke', unitCentavos: 2000, quantity: 2),
    SaleItem(name: 'Manual Entry', unitCentavos: 500, quantity: 1),
  ],
  receivedCentavos: 5000,
  completedAt: DateTime(2026, 9, 30, 14, 32),
  cashierUid: 'u',
  cashierName: 'Owner',
);

typedef _Saved = (List<SaleItem>, int, String?);

Future<List<_Saved>> _open(WidgetTester tester, {int cokeStock = 1}) async {
  final products = [
    Product(id: 'coke', name: 'Coke', stock: cokeStock, sellCentavos: 2000),
    const Product(id: 'chips', name: 'Chippy', stock: 0, sellCentavos: 1000),
    const Product(
      id: 'canton',
      name: 'Pancit Canton',
      stock: 8,
      sellCentavos: 250,
      size: '60g',
    ),
  ];
  final saved = <_Saved>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<bool>(
                builder: (_) => EditTransactionScreen(
                  sale: _sale,
                  products: products,
                  onSave:
                      (
                        sale, {
                        required items,
                        required receivedCentavos,
                        required customerName,
                      }) async {
                        saved.add((items, receivedCentavos, customerName));
                        return sale;
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
  return saved;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

bool _canSave(WidgetTester tester) =>
    tester
        .widget<FilledButton>(
          find.ancestor(
            of: find.text('Update Transaction'),
            matching: find.byType(FilledButton),
          ),
        )
        .onPressed !=
    null;

void main() {
  testWidgets('shows the sale, with who rang it up', (tester) async {
    await _open(tester);

    expect(find.text('TX-ABCDEF'), findsOneWidget);
    expect(find.text('Sep 30, 2026 · 14:32'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('3 ITEMS'), findsOneWidget);
    expect(find.textContaining('Discount'), findsNothing);
    // Nothing changed yet.
    expect(_canSave(tester), isFalse);
  });

  testWidgets('a quantity can rise only by what is on the shelf', (
    tester,
  ) async {
    await _open(tester); // 2 sold, 1 left on the shelf → at most 3

    await _tap(tester, find.byTooltip('Add one Coke'));
    expect(find.text('3'), findsOneWidget);
    final add = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.add).first,
    );
    expect(add.onPressed, isNull);
  });

  testWidgets('edits are saved: quantity, removal, name, cash', (tester) async {
    final saved = await _open(tester);

    await _tap(tester, find.byTooltip('Remove one Coke'));
    await _tap(tester, find.byTooltip('Remove Manual Entry'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Optional — e.g. Aling Nena'),
      'Aling Nena',
    );
    await tester.enterText(find.widgetWithText(TextField, '50.00'), '20');
    await tester.pump();

    // The last line can't be removed; a refund does that.
    expect(find.byTooltip('Refund to remove all'), findsOneWidget);
    expect(
      find.text('To undo the whole sale, use Refund instead.'),
      findsOneWidget,
    );

    await _tap(tester, find.text('Update Transaction'));
    await tester.pumpAndSettle();

    final (items, received, name) = saved.single;
    expect([for (final i in items) (i.name, i.quantity)], [('Coke', 1)]);
    expect(received, 2000);
    expect(name, 'Aling Nena');
    expect(find.text('TX-ABCDEF updated.'), findsOneWidget);
  });

  testWidgets('too little cash for the new total cannot be saved', (
    tester,
  ) async {
    await _open(tester, cokeStock: 10);
    await _tap(tester, find.byTooltip('Add one Coke'));
    await _tap(tester, find.byTooltip('Add one Coke')); // ₱85 > ₱50

    expect(find.text('Short by'), findsOneWidget);
    expect(_canSave(tester), isFalse);
  });

  testWidgets('fits a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester);
    expect(tester.takeException(), isNull);
  });

  group('linking a manual entry', () {
    Future<void> openPicker(WidgetTester tester) async {
      await _tap(tester, find.text('Link to product'));
      await tester.pumpAndSettle();
    }

    testWidgets('only manual entries offer it', (tester) async {
      await _open(tester);
      expect(find.text('Link to product'), findsOneWidget);
    });

    testWidgets('picks the product, its price, and a guessed quantity', (
      tester,
    ) async {
      final saved = await _open(tester);
      await openPicker(tester);

      // Out-of-stock products can't be picked.
      expect(find.text('Out of stock'), findsOneWidget);
      await tester.tap(find.text('Chippy'));
      await tester.pumpAndSettle();
      expect(find.text('Link to product'), findsWidgets); // still open

      await tester.tap(find.text('Pancit Canton · 60g'));
      await tester.pumpAndSettle();

      // ₱5.00 typed ÷ ₱2.50 each → 2.
      expect(find.text('Pancit Canton · 60g'), findsOneWidget);
      expect(find.text('Was Manual Entry · ₱5.00'), findsOneWidget);
      expect(find.text('₱2.50'), findsOneWidget);

      await _tap(tester, find.text('Update Transaction'));
      await tester.pumpAndSettle();
      final (items, _, _) = saved.single;
      expect(
        [for (final i in items) (i.productId, i.name, i.quantity)],
        [('coke', 'Coke', 2), ('canton', 'Pancit Canton · 60g', 2)],
      );
    });

    testWidgets('Undo puts the manual entry back', (tester) async {
      await _open(tester);
      await openPicker(tester);
      await tester.tap(find.text('Pancit Canton · 60g'));
      await tester.pumpAndSettle();

      await _tap(tester, find.text('Undo'));
      expect(find.text('Manual Entry'), findsOneWidget);
      expect(find.text('Link to product'), findsOneWidget);
      expect(_canSave(tester), isFalse); // back to how it was
    });

    testWidgets('search narrows the picker', (tester) async {
      await _open(tester);
      await openPicker(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search products...'),
        'cantn',
      );
      await tester.pump();
      Finder inPicker(String text) => find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(text),
      );
      expect(inPicker('Pancit Canton · 60g'), findsOneWidget);
      expect(inPicker('Coke'), findsNothing);
    });
  });
}
