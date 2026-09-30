import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tinda_track/services/product_service.dart';
import 'package:tinda_track/services/sku.dart';

String? _sku(String name, {String? size, String? category}) =>
    generateSku(name: name, size: size, mainCategory: category, tag: 'XY');

void main() {
  group('generateSku', () {
    test('category, name initials and size', () {
      expect(
        _sku('San Miguel Pale Pilsen', size: '330ml', category: 'Drinks'),
        'DRK-SMP330-XY',
      );
      expect(
        _sku('Piattos Cheese', size: 'Large', category: 'Snacks'),
        'SNK-PCL-XY',
      );
      expect(_sku('Coke', size: '1.5L', category: 'Drinks'), 'DRK-COK1.5L-XY');
      expect(_sku('Rice', size: '2 kg', category: 'Pantry'), 'PNT-RIC2KG-XY');
      expect(
        _sku('Chippy', size: '110 g', category: 'Snacks'),
        'SNK-CHI110-XY',
      );
    });

    test('custom categories and sizes use their first letters', () {
      expect(_sku('Ice Candy', category: 'Frozen'), 'FRO-IC-XY');
      expect(_sku('Tang', size: 'Sweet Orange'), 'GEN-TANSWE-XY');
    });

    test('no size, no category', () {
      expect(_sku('Lucky Me Pancit Canton'), 'GEN-LMP-XY');
    });

    test('nothing to build from', () {
      expect(_sku(''), isNull);
      expect(_sku('  ...  '), isNull);
    });

    test('re-rolls the tag when the SKU is taken', () {
      final sku = generateSku(
        name: 'Coke',
        mainCategory: 'Drinks',
        tag: 'XY',
        taken: {'drk-cok-xy'},
        random: math.Random(1),
      );
      expect(sku, startsWith('DRK-COK-'));
      expect(sku, isNot('DRK-COK-XY'));
    });

    test('tags avoid look-alike characters', () {
      final rng = math.Random(7);
      for (var i = 0; i < 200; i++) {
        expect(randomSkuTag(rng), matches(RegExp(r'^[A-HJ-NP-Z2-9]{2}$')));
      }
    });
  });

  test('normalizeSku uppercases and drops spaces', () {
    expect(normalizeSku(' smb 330 '), 'SMB330');
  });

  group('Product.fromMap', () {
    test('reads a pre-multi-category product as one category', () {
      final p = Product.fromMap('a', {'name': 'Coke', 'category': 'Drinks'});
      expect(p.categories, ['Drinks']);
      expect(p.mainCategory, 'Drinks');
    });

    test('round-trips size and categories', () {
      const p = Product(
        id: 'a',
        name: 'Coke',
        stock: 1,
        sellCentavos: 100,
        size: '1.5L',
        categories: ['Drinks', 'Softdrinks'],
      );
      final back = Product.fromMap('a', p.toMap());
      expect(back.size, '1.5L');
      expect(back.categories, ['Drinks', 'Softdrinks']);
      expect(back.displayName, 'Coke · 1.5L');
    });
  });

  group('stock alerts', () {
    Product p({required int stock, bool alerts = true}) => Product(
      id: 'a',
      name: 'X',
      stock: stock,
      sellCentavos: 100,
      stockAlerts: alerts,
    );

    test('off: never low stock, but out of stock still shows', () {
      expect(p(stock: 2, alerts: false).statusFor(5), StockStatus.inStock);
      expect(p(stock: 0, alerts: false).statusFor(5), StockStatus.outOfStock);
      expect(p(stock: 2).statusFor(5), StockStatus.lowStock);
    });

    test('off: never counted in the alerts', () {
      expect(p(stock: 0, alerts: false).needsAlert(5), isFalse);
      expect(p(stock: 2, alerts: false).needsAlert(5), isFalse);
      expect(p(stock: 0).needsAlert(5), isTrue);
      expect(p(stock: 9).needsAlert(5), isFalse);
    });

    test('defaults to on, including for older saved products', () {
      expect(Product.fromMap('a', {'name': 'X'}).stockAlerts, isTrue);
      final off = p(stock: 1, alerts: false);
      expect(Product.fromMap('a', off.toMap()).stockAlerts, isFalse);
    });
  });
}
