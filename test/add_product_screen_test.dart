import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinda_track/screens/add_product_screen.dart';
import 'package:tinda_track/services/product_service.dart';
import 'package:tinda_track/theme/app_theme.dart';

/// Opens [AddProductScreen] from a launcher page, so saving has somewhere to
/// pop back to.
Future<List<ProductDraft>> _open(
  WidgetTester tester, {
  Future<void> Function(ProductDraft)? onSave,
  List<String> existingCategories = const [],
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
                builder: (_) => AddProductScreen(
                  existingCategories: existingCategories,
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

    await tester.enterText(_field('e.g., San Miguel Beer 330ml'), '  Coke 1L ');
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
    expect(draft.category, 'Drinks');

    expect(find.text('open'), findsOneWidget);
    expect(find.text('“Coke 1L” added.'), findsOneWidget);
  });

  testWidgets('buy price, stock and category are optional', (tester) async {
    final saved = await _open(tester);

    await tester.enterText(_field('e.g., San Miguel Beer 330ml'), 'Candy');
    await tester.enterText(_field('0.00').last, '1');
    await _save(tester);

    final draft = saved.single;
    expect(draft.buyCentavos, isNull);
    expect(draft.stock, 0);
    expect(draft.category, isNull);
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

    await tester.enterText(_field('e.g., San Miguel Beer 330ml'), 'Buko');
    await tester.enterText(_field('0.00').last, '10');
    await _save(tester);

    expect(saved.single.category, 'Ice Candy');
  });

  testWidgets('a failed write is reported after closing', (tester) async {
    final write = Completer<void>();
    await _open(tester, onSave: (_) => write.future);

    await tester.enterText(_field('e.g., San Miguel Beer 330ml'), 'Coke');
    await tester.enterText(_field('0.00').last, '20');
    await _save(tester);
    expect(find.text('open'), findsOneWidget);

    write.completeError(Exception('permission-denied'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save “Coke”. Try again.'), findsOneWidget);
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
