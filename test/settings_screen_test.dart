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
  ownerUid: 'owner-uid',
);

class _Harness {
  final profile = StreamController<StoreProfile?>.broadcast();
  final saved = <StoreProfile>[];
  final staff = StreamController<StoreStaff>.broadcast();

  /// The helpers as the fake server holds them, after each write.
  var members = <StaffMember>[];
  final savedStaff = <List<StaffMember>>[];
  var upgrades = 0;

  /// Like Firestore, echoes a local write straight back to the listeners.
  Future<void> _write(List<StaffMember> next) async {
    members = next;
    savedStaff.add(next);
    staff.add(StoreStaff(isPro: true, members: next));
  }

  Widget build({
    SyncStatus sync = const SyncStatus(pending: 0),
    String userId = 'owner-uid',
  }) => MaterialApp(
    theme: AppTheme.light,
    home: SettingsScreen(
      userId: userId,
      profile: profile.stream,
      onSave: (p) async => saved.add(p),
      syncStatus: Stream.value(sync),
      staff: staff.stream,
      staffActions: StaffActions(
        add: (member) => _write([
          for (final m in members)
            if (m.email != member.email) m,
          member,
        ]),
        rename: (member, name) => _write([
          for (final m in members)
            m.email == member.email ? m.copyWith(name: name) : m,
        ]),
        remove: (member) => _write([
          for (final m in members)
            if (m.email != member.email) m,
        ]),
      ),
      onUpgradePro: () async {
        upgrades++;
        // Like Firestore, the store reads as Pro straight away.
        staff.add(StoreStaff(isPro: true, members: members));
      },
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
  h.members = [...members];
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

  group('low stock alert', () {
    Finder field() => find.widgetWithText(TextFormField, '5');

    testWidgets('shows the store threshold and saves a new one', (
      tester,
    ) async {
      _smallPhone(tester);
      final h = _Harness();
      await tester.pumpWidget(h.build());
      h.profile.add(_profile);
      await tester.pump();

      expect(find.text('LOW STOCK ALERT'), findsOneWidget);
      expect(field(), findsOneWidget);

      await tester.enterText(field(), '12');
      await tester.pump();
      await tester.tap(find.text('Save Changes'));
      await tester.pump();

      expect(h.saved.single.lowStockThreshold, 12);
      expect(h.saved.single.name, "Aling Nena's");
    });

    testWidgets('only 1–100 can be saved', (tester) async {
      _smallPhone(tester);
      final h = _Harness();
      await tester.pumpWidget(h.build());
      h.profile.add(_profile);
      await tester.pump();

      for (final bad in ['0', '101', '']) {
        await tester.enterText(find.byType(TextFormField).at(2), bad);
        await tester.pump();
        await tester.tap(find.text('Save Changes'));
        await tester.pump();
        expect(find.text('1–100'), findsOneWidget, reason: bad);
      }
      expect(h.saved, isEmpty);
    });

    testWidgets('only digits can be typed', (tester) async {
      _smallPhone(tester);
      final h = _Harness();
      await tester.pumpWidget(h.build());
      h.profile.add(_profile);
      await tester.pump();

      await tester.enterText(field(), '1a2.5');
      await tester.pump();
      expect(find.widgetWithText(TextFormField, '125'), findsOneWidget);
    });
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
    expect(find.text('Enter helper email address'), findsOneWidget);
    // Name, owner and low-stock alert only: no helper email box.
    expect(find.byType(TextField), findsNWidgets(3));
    expect(h.upgrades, 0);
  });

  testWidgets('upgrading asks first; Cancel changes nothing', (tester) async {
    _smallPhone(tester);
    final h = _Harness();
    await tester.pumpWidget(h.build());
    h.profile.add(_profile);
    await tester.pump();

    await _tapUnlock(tester);
    expect(find.text('Upgrade to Pro?'), findsOneWidget);
    expect(find.textContaining("Aling Nena's"), findsWidgets);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.upgrades, 0);
    expect(find.text('Unlock Pro & Add Helpers'), findsOneWidget);
  });

  testWidgets('confirming makes the store Pro and unlocks helpers', (
    tester,
  ) async {
    _smallPhone(tester);
    final h = _Harness();
    await tester.pumpWidget(h.build());
    h.profile.add(_profile);
    await tester.pump();

    await _tapUnlock(tester);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(h.upgrades, 1);
    expect(find.text('Pro is on. You can now add helpers.'), findsOneWidget);
    expect(find.text('Unlock Pro & Add Helpers'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Add'), findsOneWidget);
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

  group('as a helper', () {
    Future<_Harness> asHelper(WidgetTester tester) async {
      _smallPhone(tester);
      final h = _Harness();
      await tester.pumpWidget(h.build(userId: 'helper-uid'));
      h.profile.add(_profile);
      await tester.pump();
      // Even on a Pro store with helpers, the list stays hidden.
      h.staff.add(
        const StoreStaff(
          isPro: true,
          members: [StaffMember(email: 'maria@gmail.com', name: 'Maria')],
        ),
      );
      await tester.pump();
      return h;
    }

    testWidgets('store details show but cannot be changed', (tester) async {
      await asHelper(tester);

      expect(find.textContaining('signed in as a helper'), findsOneWidget);
      expect(find.text("Aling Nena's"), findsOneWidget);
      expect(find.text('Nena Cruz'), findsOneWidget);
      expect(find.text('₱ PHP (Philippine Peso)'), findsOneWidget);
      // The low-stock alert shows the store's value but is locked too.
      expect(find.text('LOW STOCK ALERT'), findsOneWidget);
      expect(find.widgetWithText(TextField, '5'), findsOneWidget);
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields, hasLength(3));
      for (final field in fields) {
        expect(field.enabled, isFalse);
      }
      final currency = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      expect(currency.onChanged, isNull);
      expect(find.text('Save Changes'), findsNothing);
      expect(find.text('Discard Changes'), findsNothing);
    });

    testWidgets('the allowed emails section is hidden', (tester) async {
      await asHelper(tester);

      expect(find.text('ALLOWED EMAILS (STAFF ACCESS)'), findsNothing);
      expect(find.text('maria@gmail.com'), findsNothing);
      expect(find.text('Unlock Pro & Add Helpers'), findsNothing);
      expect(find.text('SYNC STATUS'), findsOneWidget);
    });
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

    testWidgets('removes a helper; undo keeps them joined', (tester) async {
      const maria = StaffMember(
        email: 'maria@gmail.com',
        name: 'Maria',
        userId: 'maria-uid',
      );
      final h = await _proStore(tester, const [maria]);

      await tester.ensureVisible(find.byTooltip('Remove helper'));
      await tester.tap(find.byTooltip('Remove helper'));
      await tester.pumpAndSettle();
      expect(h.savedStaff.last, isEmpty);
      expect(find.text('maria@gmail.com'), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(h.savedStaff.last, [maria]);
    });

    testWidgets('shows who has joined', (tester) async {
      await _proStore(tester, const [
        StaffMember(email: 'jun@gmail.com', name: 'Jun', userId: 'jun-uid'),
        StaffMember(email: 'maria@gmail.com', name: 'Maria'),
      ]);

      expect(find.text('Joined'), findsOneWidget);
      expect(find.text('Waiting to join'), findsOneWidget);
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

/// Taps "Unlock Pro & Add Helpers", below the fold on a small phone.
Future<void> _tapUnlock(WidgetTester tester) async {
  final unlock = find.text('Unlock Pro & Add Helpers');
  await tester.ensureVisible(unlock);
  await tester.pumpAndSettle();
  await tester.tap(unlock);
  await tester.pumpAndSettle();
}
