import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinda_track/screens/product_form_screen.dart';
import 'package:tinda_track/services/product_service.dart';
import 'package:tinda_track/theme/app_theme.dart';

/// Opens [ProductFormScreen] from a launcher page, so saving has somewhere to
/// pop back to.
Future<List<ProductDraft>> _open(
  WidgetTester tester, {
  Future<void> Function(ProductDraft)? onSave,
  List<String> existingCategories = const [],
  Set<String> existingSkus = const {},
}) async {
  final saved = <ProductDraft>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ProductFormScreen(
                  existingCategories: existingCategories,
                  existingSkus: existingSkus,
                  onSave: (draft) {
                    saved.add(draft);
                    return onSave?.call(draft) ?? Future.value();
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

Finder _field(String hint) => find.widgetWithText(TextFormField, hint);

/// The field under the label [label], e.g. 'SKU'.
Finder _labelled(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextFormField),
);

String _textOf(WidgetTester tester, Finder field) =>
    tester.widget<TextFormField>(field).controller!.text;

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save Product'));
  await tester.tap(find.text('Save Product'));
  await tester.pumpAndSettle();
}

void main() {
  group('parseCentavos', () {
    test('reads whole and fractional pesos exactly', () {
      expect(parseCentavos('12'), 1200);
      expect(parseCentavos('12.5'), 1250);
      expect(parseCentavos('12.05'), 1205);
      expect(parseCentavos('0.1'), 10);
      expect(parseCentavos('12.'), 1200);
    });

    test('rejects blank and malformed input', () {
      expect(parseCentavos(''), isNull);
      expect(parseCentavos('.'), isNull);
      expect(parseCentavos('1.234'), isNull);
      expect(parseCentavos('abc'), isNull);
    });
  });

  testWidgets('requires a name and a sell price', (tester) async {
    final saved = await _open(tester);

    await _save(tester);

    expect(find.text('Enter a product name.'), findsOneWidget);
    expect(find.text('Enter a price.'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('saves the draft and closes', (tester) async {
    final saved = await _open(tester);

    await tester.enterText(
      _field('e.g., San Miguel Pale Pilsen'),
      '  Coke 1L ',
    );
    await tester.enterText(_field('0.00').first, '45');
    await tester.enterText(_field('0.00').last, '60.50');
    await tester.enterText(_field('0'), '12');
    await tester.ensureVisible(find.text('Drinks'));
    await tester.tap(find.text('Drinks'));
    await _save(tester);

    expect(saved, hasLength(1));
    final draft = saved.single;
    expect(draft.name, 'Coke 1L');
    expect(draft.buyCentavos, 4500);
    expect(draft.sellCentavos, 6050);
    expect(draft.stock, 12);
    expect(draft.categories, ['Drinks']);

    expect(find.text('open'), findsOneWidget);
    expect(find.text('“Coke 1L” added.'), findsOneWidget);
  });

  testWidgets('buy price, stock and category are optional', (tester) async {
    final saved = await _open(tester);

    await tester.enterText(_field('e.g., San Miguel Pale Pilsen'), 'Candy');
    await tester.enterText(_field('0.00').last, '1');
    await _save(tester);

    final draft = saved.single;
    expect(draft.buyCentavos, isNull);
    expect(draft.stock, 0);
    expect(draft.categories, isEmpty);
    expect(draft.size, isNull);
  });

  testWidgets('a custom category is added and selected once', (tester) async {
    final saved = await _open(tester, existingCategories: ['Frozen']);

    expect(find.text('Frozen'), findsOneWidget);

    await tester.ensureVisible(find.text('+ ADD CUSTOM'));
    await tester.tap(find.text('+ ADD CUSTOM'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Ice Candy');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // Same name in another case reuses the existing tag.
    await tester.tap(find.text('+ ADD CUSTOM'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'ice candy');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Ice Candy'), findsOneWidget);

    await tester.enterText(_field('e.g., San Miguel Pale Pilsen'), 'Buko');
    await tester.enterText(_field('0.00').last, '10');
    await _save(tester);

    expect(saved.single.categories, ['Ice Candy']);
  });

  testWidgets('categories are multi-select; the first picked is main', (
    tester,
  ) async {
    final saved = await _open(tester);
    await tester.enterText(_field('e.g., San Miguel Pale Pilsen'), 'Coke');
    await tester.enterText(_field('0.00').last, '20');

    for (final c in ['Drinks', 'Snacks', 'Pantry']) {
      await tester.ensureVisible(find.text(c));
      await tester.tap(find.text(c));
      await tester.pump();
    }
    expect(find.text('MAIN'), findsOneWidget);

    // Dropping the main one promotes the next.
    await tester.tap(find.text('Drinks'));
    await tester.pump();
    await _save(tester);

    expect(saved.single.categories, ['Snacks', 'Pantry']);
  });

  testWidgets('the SKU fills itself in from name, size and main category', (
    tester,
  ) async {
    final saved = await _open(tester);
    final sku = _labelled('SKU');

    await tester.enterText(
      _field('e.g., San Miguel Pale Pilsen'),
      'San Miguel Pale Pilsen',
    );
    await tester.enterText(_field('e.g., 330ml, 40g, Large'), '330ml');
    await tester.ensureVisible(find.text('Drinks'));
    await tester.tap(find.text('Drinks'));
    await tester.pump();

    expect(_textOf(tester, sku), matches(RegExp(r'^DRK-SMP330-[A-Z2-9]{2}$')));
    final tag = _textOf(tester, sku).split('-').last;

    // Changing the size keeps the same random ending.
    await tester.enterText(_field('330ml'), '1.5L');
    await tester.pump();
    expect(_textOf(tester, sku), 'DRK-SMP1.5L-$tag');

    await tester.enterText(_field('0.00').last, '60');
    await _save(tester);
    expect(saved.single.sku, 'DRK-SMP1.5L-$tag');
    expect(saved.single.size, '1.5L');
  });

  testWidgets('a typed SKU is kept, and must be unused', (tester) async {
    final saved = await _open(tester, existingSkus: {'MINE-1'});
    final sku = _labelled('SKU');

    await tester.enterText(_field('e.g., San Miguel Pale Pilsen'), 'Coke');
    await tester.enterText(_field('0.00').last, '20');
    await tester.enterText(sku, 'mine-1');
    await tester.pump();

    // Later edits to the name no longer touch it.
    await tester.enterText(_field('Coke'), 'Coke Mismo');
    await tester.pump();
    expect(_textOf(tester, sku), 'mine-1');

    await _save(tester);
    expect(find.text('Another product already uses this SKU.'), findsOneWidget);
    expect(saved, isEmpty);

    await tester.enterText(sku, 'mine 2');
    await _save(tester);
    expect(saved.single.sku, 'MINE2');
  });

  testWidgets('low-stock alerts are on unless unticked', (tester) async {
    var saved = await _open(tester);
    await tester.enterText(_field('e.g., San Miguel Pale Pilsen'), 'Coke');
    await tester.enterText(_field('0.00').last, '20');
    await _save(tester);
    expect(saved.single.stockAlerts, isTrue);

    saved = await _open(tester);
    await tester.enterText(_field('e.g., San Miguel Pale Pilsen'), 'Tawas');
    await tester.enterText(_field('0.00').last, '5');
    await tester.ensureVisible(find.text('Low-stock alerts'));
    await tester.tap(find.text('Low-stock alerts'));
    await tester.pump();
    await _save(tester);
    expect(saved.single.stockAlerts, isFalse);
  });

  testWidgets('a failed write is reported after closing', (tester) async {
    final write = Completer<void>();
    await _open(tester, onSave: (_) => write.future);

    await tester.enterText(_field('e.g., San Miguel Pale Pilsen'), 'Coke');
    await tester.enterText(_field('0.00').last, '20');
    await _save(tester);
    expect(find.text('open'), findsOneWidget);

    write.completeError(Exception('permission-denied'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save “Coke”. Try again.'), findsOneWidget);
  });

  testWidgets('adding has no Delete button', (tester) async {
    await _open(tester);
    expect(find.text('Delete Product'), findsNothing);
    expect(find.text('Add New Product'), findsOneWidget);
  });

  test('centavosToInput writes what parseCentavos reads', () {
    for (final c in [0, 5, 1850, 100000]) {
      expect(parseCentavos(centavosToInput(c)), c);
    }
    expect(centavosToInput(1850), '18.50');
  });

  testWidgets('fits a small phone without overflowing', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _open(tester);
    await _save(tester);

    expect(tester.takeException(), isNull);
  });
}
