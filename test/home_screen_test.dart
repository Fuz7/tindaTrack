import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinda_track/screens/dashboard_screen.dart';
import 'package:tinda_track/screens/home_screen.dart';
import 'package:tinda_track/theme/app_theme.dart';

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

Widget _home() => MaterialApp(
  theme: AppTheme.light,
  home: const Scaffold(body: HomeScreen()),
);

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

  testWidgets('search swaps the keypad for results and back', (tester) async {
    await tester.pumpWidget(_home());

    await tester.enterText(find.byType(TextField), 'piattos');
    await tester.pump();

    expect(find.text('No products match “piattos”'), findsOneWidget);
    expect(find.byTooltip('Add to cart'), findsNothing);

    await tester.tap(find.byTooltip('Close search'));
    await tester.pump();

    expect(find.byTooltip('Add to cart'), findsOneWidget);
    expect(find.text('Active Cart'), findsOneWidget);
  });

  group('DashboardScreen', () {
    Widget shell() => MaterialApp(
      theme: AppTheme.light,
      home: DashboardScreen(user: _FakeUser()),
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

      await tester.tap(find.byTooltip('Inventory'));
      await tester.pump();

      expect(find.text('Inventory is not built yet.'), findsOneWidget);
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
