import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinda_track/screens/create_store_profile_screen.dart';
import 'package:tinda_track/screens/create_store_starter_screen.dart';
import 'package:tinda_track/services/store_service.dart';
import 'package:tinda_track/theme/app_theme.dart';

Widget _host(Widget screen) => MaterialApp(theme: AppTheme.light, home: screen);

void _smallPhone(WidgetTester tester) {
  // 360×640 is the narrow end of the Android range the design targets.
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('CreateStoreProfileScreen', () {
    testWidgets('blocks Continue until the required fields are filled', (
      tester,
    ) async {
      StoreDraft? draft;
      await tester.pumpWidget(
        _host(CreateStoreProfileScreen(onContinue: (d) => draft = d)),
      );

      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(draft, isNull);
      expect(find.text('Required'), findsNWidgets(2));
    });

    testWidgets('reports a trimmed draft, with blanks as null', (tester) async {
      StoreDraft? draft;
      await tester.pumpWidget(
        _host(
          CreateStoreProfileScreen(
            initialOwnerName: 'Juan Dela Cruz',
            onContinue: (d) => draft = d,
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          "e.g., Aling Nena's Sari-Sari Store",
        ),
        '  Aling Nena  ',
      );
      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(draft, isNotNull);
      expect(draft!.name, 'Aling Nena');
      expect(draft!.ownerName, 'Juan Dela Cruz');
      expect(draft!.phone, isNull);
      expect(draft!.address, isNull);
      expect(draft!.currency, 'PHP');
      expect(draft!.lowStockThreshold, 5);
    });

    testWidgets('rejects a zero threshold', (tester) async {
      StoreDraft? draft;
      await tester.pumpWidget(
        _host(
          CreateStoreProfileScreen(
            initialOwnerName: 'Juan',
            onContinue: (d) => draft = d,
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          "e.g., Aling Nena's Sari-Sari Store",
        ),
        'Store',
      );
      await tester.enterText(find.widgetWithText(TextFormField, '5'), '0');
      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(draft, isNull);
      expect(find.text('1–100'), findsOneWidget);
    });

    testWidgets('fits a small phone without overflowing', (tester) async {
      _smallPhone(tester);
      await tester.pumpWidget(
        _host(CreateStoreProfileScreen(onContinue: (_) {})),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('CreateStoreStarterScreen', () {
    Widget starter(Future<void> Function() onCreate) => _host(
      CreateStoreStarterScreen(storeName: 'Aling Nena', onCreate: onCreate),
    );

    /// Taps a dialog button and lets the dialog close. Not `pumpAndSettle`:
    /// after a successful create the busy spinner animates until the gate
    /// pops the route, which never happens here.
    Future<void> confirm(WidgetTester tester, String label) async {
      await tester.pumpAndSettle(); // let the dialog finish opening
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('bottom action confirms before creating', (tester) async {
      var created = 0;
      await tester.pumpWidget(starter(() async => created++));

      await tester.tap(find.text('Create Store & Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Create Aling Nena?'), findsOneWidget);
      expect(created, 0);

      await confirm(tester, 'Create Store');
      expect(created, 1);
    });

    testWidgets('cancelling the dialog creates nothing', (tester) async {
      var created = 0;
      await tester.pumpWidget(starter(() async => created++));

      await tester.tap(find.text('Create Store & Continue'));
      await confirm(tester, 'Cancel');

      expect(find.text('Create Aling Nena?'), findsNothing);
      expect(created, 0);
    });

    testWidgets('skip link confirms before creating', (tester) async {
      var created = 0;
      await tester.pumpWidget(starter(() async => created++));

      final skip = find.text('Skip inventory seed & finish later');
      await tester.ensureVisible(skip);
      await tester.tap(skip);
      await tester.pumpAndSettle();

      expect(find.text('Skip inventory seed?'), findsOneWidget);
      expect(created, 0);

      await confirm(tester, 'Skip & Create');
      expect(created, 1);
    });

    testWidgets('shows a failed create and allows a retry', (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        starter(() async {
          attempts++;
          throw Exception('permission-denied');
        }),
      );

      await tester.tap(find.text('Create Store & Continue'));
      await confirm(tester, 'Create Store');

      expect(find.textContaining('permission-denied'), findsOneWidget);

      await tester.tap(find.text('Create Store & Continue'));
      await confirm(tester, 'Create Store');

      expect(attempts, 2);
    });

    testWidgets('Pro features say they are not available', (tester) async {
      await tester.pumpWidget(starter(() async {}));

      await tester.ensureVisible(find.text('Unlock'));
      await tester.tap(find.text('Unlock'));
      await tester.pump();

      expect(find.text('TindaTrack Pro is not available yet.'), findsOneWidget);
    });

    testWidgets('fits a small phone without overflowing', (tester) async {
      _smallPhone(tester);
      await tester.pumpWidget(starter(() async {}));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('dialog fits a small phone without overflowing', (
      tester,
    ) async {
      _smallPhone(tester);
      await tester.pumpWidget(starter(() async {}));

      await tester.tap(find.text('Create Store & Continue'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
