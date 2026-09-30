import 'package:flutter_test/flutter_test.dart';
import 'package:tinda_track/services/product_search.dart';
import 'package:tinda_track/services/product_service.dart';

Product _p(String id, String name, {String? sku}) =>
    Product(id: id, name: name, stock: 1, sellCentavos: 100, sku: sku);

final _catalog = [
  _p('beer', 'San Miguel Pale Pilsen 330ml', sku: 'SMB-330'),
  _p('light', 'San Mig Light'),
  _p('coke', 'Coke Mismo'),
  _p('canton', 'Lucky Me Pancit Canton'),
  _p('piattos', 'Piattos Cheese'),
  _p('tipid', 'Tipid Pi Snack'),
];

List<String> _ids(String query) => [
  for (final m in searchProducts(_catalog, query)) m.product.id,
];

void main() {
  test('finds San Miguel however the cashier types it', () {
    for (final query in [
      'San Miguel',
      'san migz',
      'san mig',
      'san mi',
      'san m',
      'san',
      'sa',
      's',
      'Sanmig',
      'miguel',
      'pilsen',
      'pilsn', // dropped letter
      'mgiuel', // swapped letters
      'pale san', // any word order
      'smb', // SKU
    ]) {
      expect(_ids(query), contains('beer'), reason: query);
    }
  });

  test('every word has to match somewhere', () {
    expect(_ids('san coke'), isEmpty);
    expect(_ids('zzz'), isEmpty);
  });

  test('short words need a real prefix, not a typo', () {
    // One or two letters allow no typos, or everything would match.
    expect(_ids('x'), isEmpty);
    expect(_ids('co'), ['coke']);
  });

  test('exact and prefix hits rank above loose ones', () {
    // "Piattos" starts with "pi"; "Tipid Pi" only has it as a later word.
    expect(_ids('pi').first, 'piattos');
    expect(_ids('san mig light').first, 'light');
  });

  test('highlights the matched parts of the name', () {
    final match = searchProducts(_catalog, 'san migz').first;
    final name = match.product.name;
    expect(
      [for (final (s, e) in match.highlights) name.substring(s, e)],
      ['San', 'Mig'],
    );
  });

  test('a blank query matches nothing', () {
    expect(_ids(''), isEmpty);
    expect(_ids('   '), isEmpty);
  });
}
