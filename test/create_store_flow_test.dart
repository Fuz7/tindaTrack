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
    Widget starter(
      Future<void> Function({
        required bool isPro,
        required bool withStarterPack,
        required List<StaffMember> helpers,
      })
      onCreate,
    ) => _host(
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
      await tester.pumpWidget(
        starter(
          ({
            required isPro,
            required withStarterPack,
            required helpers,
          }) async => created++,
        ),
      );

      await tester.tap(find.text('Create Store & Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Create Aling Nena?'), findsOneWidget);
      expect(created, 0);

      await confirm(tester, 'Create Store');
      expect(created, 1);
    });

    testWidgets('cancelling the dialog creates nothing', (tester) async {
      var created = 0;
      await tester.pumpWidget(
        starter(
          ({
            required isPro,
            required withStarterPack,
            required helpers,
          }) async => created++,
        ),
      );

      await tester.tap(find.text('Create Store & Continue'));
      await confirm(tester, 'Cancel');

      expect(find.text('Create Aling Nena?'), findsNothing);
      expect(created, 0);
    });

    testWidgets('skip link confirms before creating', (tester) async {
      var created = 0;
      await tester.pumpWidget(
        starter(
          ({
            required isPro,
            required withStarterPack,
            required helpers,
          }) async => created++,
        ),
      );

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
        starter(({
          required isPro,
          required withStarterPack,
          required helpers,
        }) async {
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

    testWidgets('one Pro unlock opens the pack and helpers together', (
      tester,
    ) async {
      await tester.pumpWidget(
        starter(
          ({
            required isPro,
            required withStarterPack,
            required helpers,
          }) async {},
        ),
      );

      // Taking Pro from the helpers side must unlock the pack too: it is
      // one flag on the store, not one per feature.
      await tester.ensureVisible(find.text('Upgrade'));
      await tester.tap(find.text('Upgrade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock Pro'));
      await tester.pumpAndSettle();

      expect(find.text('Upgrade'), findsNothing);
      expect(find.text('Unlock'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Pro is carried to the create even with no pack', (
      tester,
    ) async {
      bool? pro;
      bool? seeded;
      await tester.pumpWidget(
        starter(({
          required isPro,
          required withStarterPack,
          required helpers,
        }) async {
          pro = isPro;
          seeded = withStarterPack;
        }),
      );

      await tester.ensureVisible(find.text('Upgrade'));
      await tester.tap(find.text('Upgrade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock Pro'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create Store & Continue'));
      await confirm(tester, 'Create Store');

      expect(pro, isTrue);
      expect(seeded, isFalse);
    });

    testWidgets('invited helpers are carried to the create', (tester) async {
      List<StaffMember>? invited;
      await tester.pumpWidget(
        starter(
          ({
            required isPro,
            required withStarterPack,
            required helpers,
          }) async => invited = helpers,
        ),
      );

      await tester.ensureVisible(find.text('Upgrade'));
      await tester.tap(find.text('Upgrade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock Pro'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Tindahan.Jun@Gmail.com');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('tindahan.jun@gmail.com'), findsOneWidget);

      await tester.tap(find.text('Create Store & Continue'));
      await confirm(tester, 'Create Store');

      expect(invited, hasLength(1));
      expect(invited!.single.email, 'tindahan.jun@gmail.com');
      expect(invited!.single.name, 'Tindahan Jun');
    });

    testWidgets('a bad or repeated helper email is refused', (tester) async {
      await tester.pumpWidget(
        starter(
          ({
            required isPro,
            required withStarterPack,
            required helpers,
          }) async {},
        ),
      );

      await tester.ensureVisible(find.text('Upgrade'));
      await tester.tap(find.text('Upgrade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock Pro'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'not-an-email');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('That is not an email address.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'maria@gmail.com');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'maria@gmail.com');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('That helper is already invited.'), findsOneWidget);
      // By the remove button, not the text: the field still holds the
      // rejected address, so the email itself appears twice.
      expect(find.byTooltip('Remove maria@gmail.com'), findsOneWidget);
    });

    testWidgets('the starter pack is off until Pro is taken', (tester) async {
      bool? seeded;
      await tester.pumpWidget(
        starter(
          ({
            required isPro,
            required withStarterPack,
            required helpers,
          }) async => seeded = withStarterPack,
        ),
      );

      await tester.tap(find.text('Create Store & Continue'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('starts with an empty catalog'),
        findsOneWidget,
      );

      await confirm(tester, 'Create Store');
      expect(seeded, isFalse);
    });

    testWidgets('unlocking Pro selects the pack and seeds it', (tester) async {
      bool? seeded;
      await tester.pumpWidget(
        starter(
          ({
            required isPro,
            required withStarterPack,
            required helpers,
          }) async => seeded = withStarterPack,
        ),
      );

      await tester.ensureVisible(find.text('Unlock'));
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      // The dialog stands in for the purchase; nothing is chosen until it
      // is confirmed.
      expect(find.text('Unlock TindaTrack Pro?'), findsOneWidget);
      await tester.tap(find.text('Unlock Pro'));
      await tester.pumpAndSettle();

      // The pack now reads as included rather than offering itself.
      expect(find.textContaining('Included'), findsOneWidget);
      expect(find.text('Unlock'), findsNothing);

      await tester.tap(find.text('Create Store & Continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('products, priced'), findsOneWidget);

      await confirm(tester, 'Create Store');
      expect(seeded, isTrue);
    });

    testWidgets('skipping creates an empty store even after Pro', (
      tester,
    ) async {
      bool? seeded;
      await tester.pumpWidget(
        starter(
          ({
            required isPro,
            required withStarterPack,
            required helpers,
          }) async => seeded = withStarterPack,
        ),
      );

      await tester.ensureVisible(find.text('Unlock'));
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock Pro'));
      await tester.pumpAndSettle();

      final skip = find.text('Skip inventory seed & finish later');
      await tester.ensureVisible(skip);
      await tester.tap(skip);
      await confirm(tester, 'Skip & Create');

      expect(seeded, isFalse);
    });

    testWidgets('fits a small phone without overflowing', (tester) async {
      _smallPhone(tester);
      await tester.pumpWidget(
        starter(
          ({
            required isPro,
            required withStarterPack,
            required helpers,
          }) async {},
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('dialog fits a small phone without overflowing', (
      tester,
    ) async {
      _smallPhone(tester);
      await tester.pumpWidget(
        starter(
          ({
            required isPro,
            required withStarterPack,
            required helpers,
          }) async {},
        ),
      );

      await tester.tap(find.text('Create Store & Continue'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
