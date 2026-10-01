import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinda_track/screens/settings_screen.dart';
import 'package:tinda_track/services/product_repository.dart';
import 'package:tinda_track/services/store_service.dart';
import 'package:tinda_track/theme/app_theme.dart';

const _profile = StoreProfile(
  name: "Aling Nena's",
  ownerName: 'Nena Cruz',
  currency: 'PHP',
);

class _Harness {
  final profile = StreamController<StoreProfile?>.broadcast();
  final saved = <StoreProfile>[];
  final staff = StreamController<StoreStaff>.broadcast();
  final savedStaff = <List<StaffMember>>[];
  var unlockTapped = false;

  Widget build({SyncStatus sync = const SyncStatus(pending: 0)}) => MaterialApp(
    theme: AppTheme.light,
    home: SettingsScreen(
      profile: profile.stream,
      onSave: (p) async => saved.add(p),
      syncStatus: Stream.value(sync),
      staff: staff.stream,
      onSaveStaff: (members) async {
        savedStaff.add(members);
        // Firestore echoes a local write straight back to its listeners.
        staff.add(StoreStaff(isPro: true, members: members));
      },
      onUnlockPro: () => unlockTapped = true,
    ),
  );
}

Future<_Harness> _proStore(
  WidgetTester tester, [
  List<StaffMember> members = const [],
]) async {
  _smallPhone(tester);
  final h = _Harness();
  await tester.pumpWidget(h.build());
  h.profile.add(_profile);
  await tester.pump();
  h.staff.add(StoreStaff(isPro: true, members: members));
  await tester.pump();
  return h;
}

void _smallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

FilledButton _saveButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.widgetWithText(FilledButton, 'Save Changes'),
);

void main() {
  testWidgets('fills the form from the saved profile', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    h.profile.add(_profile);
    await tester.pump();

    expect(find.text("Aling Nena's"), findsOneWidget);
    expect(find.text('Nena Cruz'), findsOneWidget);
    expect(find.text('₱ PHP (Philippine Peso)'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('saves edits, trimmed, and discards them', (tester) async {
    _smallPhone(tester);
    final h = _Harness();
    await tester.pumpWidget(h.build());
    h.profile.add(_profile);
    await tester.pump();

    await tester.enterText(find.text('Nena Cruz'), '  Juan Dela Cruz ');
    await tester.pump();
    await tester.tap(find.text('Discard Changes'));
    await tester.pump();
    expect(find.text('Nena Cruz'), findsOneWidget);

    await tester.enterText(find.text('Nena Cruz'), '  Juan Dela Cruz ');
    await tester.pump();
    await tester.tap(find.text('Save Changes'));
    await tester.pump();

    expect(h.saved, [
      const StoreProfile(
        name: "Aling Nena's",
        ownerName: 'Juan Dela Cruz',
        currency: 'PHP',
      ),
    ]);
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('refuses to save a blank store name', (tester) async {
    _smallPhone(tester);
    final h = _Harness();
    await tester.pumpWidget(h.build());
    h.profile.add(_profile);
    await tester.pump();

    await tester.enterText(find.text("Aling Nena's"), '   ');
    await tester.pump();
    await tester.tap(find.text('Save Changes'));
    await tester.pump();

    expect(h.saved, isEmpty);
    expect(find.text('Required'), findsOneWidget);
  });

  testWidgets('staff emails are locked behind Pro', (tester) async {
    _smallPhone(tester);
    final h = _Harness();
    await tester.pumpWidget(h.build());
    h.profile.add(_profile);
    await tester.pump();

    expect(find.text('Requires Pro'), findsNWidgets(2));
    await tester.ensureVisible(find.text('Unlock Pro & Add Helpers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock Pro & Add Helpers'));
    expect(h.unlockTapped, isTrue);
  });

  testWidgets('reports changes waiting to sync', (tester) async {
    _smallPhone(tester);
    final h = _Harness();
    await tester.pumpWidget(
      h.build(sync: SyncStatus(pending: 2, lastSyncedAt: DateTime.now())),
    );
    h.profile.add(_profile);
    await tester.pump();
    await tester.pump(); // The sync status stream delivers a frame later.

    expect(find.text('Status: 2 changes waiting'), findsOneWidget);
    expect(find.text('Last synced: just now'), findsOneWidget);
  });

  group('with Pro', () {
    testWidgets('adds a helper under the name given', (tester) async {
      final h = await _proStore(tester);
      expect(find.text('Unlock Pro & Add Helpers'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter helper email address'),
        ' Maria@Gmail.com ',
      );
      await _tapAdd(tester);
      await tester.pumpAndSettle();

      // The name dialog starts from the email's local part.
      expect(find.widgetWithText(TextField, 'maria'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'maria'), 'Maria');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(h.savedStaff.last, [
        const StaffMember(email: 'maria@gmail.com', name: 'Maria'),
      ]);
      expect(find.text('Maria'), findsOneWidget);
      expect(find.text('maria@gmail.com'), findsOneWidget);
    });

    testWidgets('refuses a bad or duplicate email', (tester) async {
      final h = await _proStore(tester, const [
        StaffMember(email: 'maria@gmail.com', name: 'Maria'),
      ]);
      final field = find.byType(TextField).last;

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter helper email address'),
        'not-an-email',
      );
      await _tapAdd(tester);
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address.'), findsOneWidget);

      await tester.enterText(field, 'MARIA@gmail.com');
      await _tapAdd(tester);
      await tester.pumpAndSettle();
      expect(find.text('That email is already on the list.'), findsOneWidget);
      expect(h.savedStaff, isEmpty);
    });

    testWidgets('the edit icon renames a helper', (tester) async {
      final h = await _proStore(tester, const [
        StaffMember(email: 'maria@gmail.com', name: 'Maria'),
        StaffMember(email: 'jun@gmail.com', name: 'Jun'),
      ]);

      await tester.ensureVisible(find.byTooltip('Edit name').first);
      await tester.tap(find.byTooltip('Edit name').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Maria'),
        'Ate Maria',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(h.savedStaff.last, [
        const StaffMember(email: 'maria@gmail.com', name: 'Ate Maria'),
        const StaffMember(email: 'jun@gmail.com', name: 'Jun'),
      ]);
      expect(find.text('Ate Maria'), findsOneWidget);
    });

    testWidgets('removes a helper, with undo', (tester) async {
      final h = await _proStore(tester, const [
        StaffMember(email: 'maria@gmail.com', name: 'Maria'),
      ]);

      await tester.ensureVisible(find.byTooltip('Remove helper'));
      await tester.tap(find.byTooltip('Remove helper'));
      await tester.pumpAndSettle();
      expect(h.savedStaff.last, isEmpty);
      expect(find.text('maria@gmail.com'), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(h.savedStaff.last, [
        const StaffMember(email: 'maria@gmail.com', name: 'Maria'),
      ]);
    });
  });
}

/// Taps the helper list's Add, which sits below the fold on a small phone.
Future<void> _tapAdd(WidgetTester tester) async {
  final add = find.widgetWithText(FilledButton, 'Add');
  await tester.ensureVisible(add);
  await tester.pumpAndSettle();
  await tester.tap(add);
}
