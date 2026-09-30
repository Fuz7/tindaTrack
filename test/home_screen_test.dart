import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinda_track/screens/dashboard_screen.dart';
import 'package:tinda_track/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinda_track/services/product_repository.dart';
import 'package:tinda_track/services/product_service.dart';
import 'package:tinda_track/theme/app_theme.dart';

import 'support/fake_product_remote.dart';

/// Just enough of a Firebase [User] for the shell to render: no photo, so no
/// network image is attempted.
class _FakeUser implements User {
  @override
  String? get displayName => 'Juan Dela Cruz';
  @override
  String? get email => 'juan@example.com';
  @override
  String? get photoURL => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _catalog = [
  Product(
    id: 'coke',
    name: 'Coke Mismo',
    stock: 12,
    sellCentavos: 2000,
    sku: 'CK-290',
  ),
  Product(
    id: 'canton',
    name: 'Lucky Me Pancit Canton',
    stock: 3,
    sellCentavos: 1800,
  ),
  Product(id: 'kopiko', name: 'Kopiko Blanca', stock: 0, sellCentavos: 1000),
  Product(id: 'cokezero', name: 'Zero Coke', stock: 40, sellCentavos: 2500),
];

Widget _home({List<Product> products = _catalog}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: HomeScreen(
      products: Stream.value(products),
      lowStockThreshold: Stream.value(5),
    ),
  ),
);

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

/// Types [digits] on the keypad.
Future<void> _type(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.text(d));
  }
  await tester.pump();
}

Future<void> _addToCart(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add to cart'));
  await tester.pump();
}

void _smallPhone(WidgetTester tester) {
  // 360×640 is the narrow end of the Android range the design targets.
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('formatPeso groups thousands and keeps two decimals', () {
    expect(formatPeso(0), '₱0.00');
    expect(formatPeso(750), '₱7.50');
    expect(formatPeso(123456), '₱1,234.56');
    expect(formatPeso(100000000), '₱1,000,000.00');
  });

  testWidgets('starts at 0.00 with an empty cart and actions disabled', (
    tester,
  ) async {
    await tester.pumpWidget(_home());

    expect(find.text('0.00'), findsOneWidget);
    expect(find.text('0 ITEMS'), findsOneWidget);
    expect(find.textContaining('Cart is empty'), findsOneWidget);

    ButtonStyleButton button(String label) => tester.widget(
      find.ancestor(
        of: find.text(label),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(button('COMPLETE SALE').onPressed, isNull);
    expect(button('CLEAR CART').onPressed, isNull);
  });

  testWidgets('typing builds the entry in pesos; C clears it', (tester) async {
    await tester.pumpWidget(_home());

    await _type(tester, '0150'); // the leading zero is ignored
    expect(find.text('150.00'), findsOneWidget);

    await tester.tap(find.text('C'));
    await tester.pump();
    expect(find.text('0.00'), findsOneWidget);
  });

  testWidgets('entry stops at six digits', (tester) async {
    await tester.pumpWidget(_home());

    await _type(tester, '1234567');

    expect(find.text('123,456.00'), findsOneWidget);
  });

  testWidgets('cart key rings up a manual entry, newest first', (tester) async {
    await tester.pumpWidget(_home());

    await _type(tester, '25');
    await _addToCart(tester);
    await _type(tester, '150');
    await _addToCart(tester);

    expect(find.text('0.00'), findsOneWidget); // entry reset
    expect(find.text('2 ITEMS'), findsOneWidget);
    expect(find.text('₱175.00'), findsOneWidget); // total

    final newest = tester.getTopLeft(find.text('Qty: 1 × ₱150.00'));
    final older = tester.getTopLeft(find.text('Qty: 1 × ₱25.00'));
    expect(newest.dy, lessThan(older.dy));
  });

  testWidgets('cart key does nothing at 0.00', (tester) async {
    await tester.pumpWidget(_home());

    await _addToCart(tester);

    expect(find.text('0 ITEMS'), findsOneWidget);
  });

  testWidgets('a line can be removed', (tester) async {
    await tester.pumpWidget(_home());
    await _type(tester, '25');
    await _addToCart(tester);

    await tester.tap(find.byTooltip('Remove Manual Entry'));
    await tester.pump();

    expect(find.text('0 ITEMS'), findsOneWidget);
  });

  testWidgets('clearing the cart can be undone', (tester) async {
    await tester.pumpWidget(_home());
    await _type(tester, '25');
    await _addToCart(tester);

    await tester.tap(find.text('CLEAR CART'));
    await tester.pumpAndSettle(); // let the snackbar finish sliding in
    expect(find.text('0 ITEMS'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await tester.pump();
    expect(find.text('1 ITEM'), findsOneWidget);
  });

  testWidgets('search floats results over a scrim that blocks the keypad', (
    tester,
  ) async {
    await tester.pumpWidget(_home());

    await tester.enterText(find.byType(TextField), 'piattos');
    await tester.pumpAndSettle();

    expect(find.text('No products match “piattos”'), findsOneWidget);
    // The keypad stays in view behind the scrim but can't be tapped.
    expect(find.text('Active Cart'), findsOneWidget);
    await tester.tap(find.text('5'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('0.00'), findsOneWidget);

    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();

    expect(find.text('No products match “piattos”'), findsNothing);
    await tester.tap(find.text('5'));
    await tester.pump();
    expect(find.text('5.00'), findsOneWidget);
  });

  testWidgets('tapping the scrim leaves search', (tester) async {
    await tester.pumpWidget(_home());

    await tester.enterText(find.byType(TextField), 'piattos');
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.text('Active Cart')));
    await tester.pumpAndSettle();

    expect(find.text('No products match “piattos”'), findsNothing);
    expect(find.byTooltip('Close search'), findsNothing);
  });

  testWidgets('search finds inventory products, name prefixes first', (
    tester,
  ) async {
    await tester.pumpWidget(_home());
    await _search(tester, 'coke');

    final names = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((t) => t.text.toPlainText())
        .where((t) => t.contains('Coke'))
        .toList();
    expect(names, ['Coke Mismo', 'Zero Coke']);
    expect(find.text('CK-290 • 12 in stock'), findsOneWidget);
    expect(find.text('₱20.00'), findsOneWidget);
    expect(find.text('IN STOCK'), findsNWidgets(2));
    expect(find.text('Lucky Me Pancit Canton'), findsNothing);
  });

  testWidgets('search matches by SKU and shows stock status', (tester) async {
    await tester.pumpWidget(_home());

    await _search(tester, 'ck-2');
    expect(find.text('CK-290 • 12 in stock'), findsOneWidget);

    await _search(tester, 'canton');
    expect(find.text('LOW STOCK'), findsOneWidget);

    await _search(tester, 'kopiko');
    expect(find.text('OUT OF STOCK'), findsOneWidget);
  });

  testWidgets('tapping a result rings it up; again adds a unit', (
    tester,
  ) async {
    await tester.pumpWidget(_home());

    for (var i = 0; i < 2; i++) {
      await _search(tester, 'mismo');
      await tester.tap(
        find.bySemanticsLabel(RegExp('^Add Coke Mismo to cart')),
      );
      await tester.pumpAndSettle();
    }

    // Search closed, and one row with a quantity of two.
    expect(find.byTooltip('Close search'), findsNothing);
    expect(find.text('Coke Mismo'), findsOneWidget);
    expect(find.text('Qty: 2 × ₱20.00'), findsOneWidget);
    expect(find.text('2 ITEMS'), findsOneWidget);
  });

  testWidgets('enter rings up the top match', (tester) async {
    await tester.pumpWidget(_home());
    await _search(tester, 'co');

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Coke Mismo'), findsOneWidget);
    expect(find.text('1 ITEM'), findsOneWidget);
  });

  testWidgets('an empty catalog points to the Inventory tab', (tester) async {
    await tester.pumpWidget(_home(products: const []));
    await _search(tester, 'coke');

    expect(find.text('No products yet'), findsOneWidget);
  });

  group('DashboardScreen', () {
    Widget shell() => MaterialApp(
      theme: AppTheme.light,
      home: DashboardScreen(
        user: _FakeUser(),
        storeId: 'store-1',
        createProductRepository: (id) =>
            ProductRepository(storeId: id, remote: FakeProductRemote(_catalog)),
        watchLowStockThreshold: (_) => Stream.value(5),
      ),
    );

    testWidgets('shows the home tab under the app bar and nav', (tester) async {
      await tester.pumpWidget(shell());

      expect(find.text('TindaTrack'), findsOneWidget);
      expect(find.text('Search products...'), findsOneWidget);
      expect(find.text('CURRENT ENTRY'), findsOneWidget);
      expect(find.byTooltip('Inventory'), findsOneWidget);
    });

    testWidgets('unbuilt tabs say so', (tester) async {
      await tester.pumpWidget(shell());

      await tester.tap(find.byTooltip('Transactions'));
      await tester.pump();

      expect(find.text('Transactions is not built yet.'), findsOneWidget);
    });

    testWidgets('fits a small phone with a full entry and cart', (
      tester,
    ) async {
      _smallPhone(tester);
      await tester.pumpWidget(shell());

      for (var i = 0; i < 3; i++) {
        await _type(tester, '999999');
        await _addToCart(tester);
      }
      await _type(tester, '999999');

      expect(tester.takeException(), isNull);
      // Keys stay tappable even when the keypad has to shrink.
      expect(
        tester.getSize(find.text('5').hitTestable()).height,
        greaterThan(0),
      );
      final key = find.ancestor(
        of: find.text('5'),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(key).height, greaterThanOrEqualTo(44));
    });
  });
}
