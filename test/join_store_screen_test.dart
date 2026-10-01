import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinda_track/screens/join_store_screen.dart';
import 'package:tinda_track/services/store_service.dart';
import 'package:tinda_track/theme/app_theme.dart';

const _nena = StoreInvite(
  storeId: 'store-nena',
  storeName: "Aling Nena's Store",
  ownerName: 'Nena Santos',
);
const _lito = StoreInvite(
  storeId: 'store-lito',
  storeName: "Lito's Mini Mart",
  ownerName: 'Lito Dela Cruz',
);

Widget _host({
  required Future<List<StoreInvite>> Function() loadInvites,
  Future<void> Function(StoreInvite invite)? onAccess,
}) => MaterialApp(
  theme: AppTheme.light,
  home: JoinStoreScreen(
    loadInvites: loadInvites,
    onAccess: onAccess ?? (_) async {},
  ),
);

void main() {
  testWidgets('lists the stores that authorized the email', (tester) async {
    await tester.pumpWidget(_host(loadInvites: () async => [_nena, _lito]));
    await tester.pumpAndSettle();

    expect(find.text("Aling Nena's Store"), findsOneWidget);
    expect(find.text('Nena Santos'), findsOneWidget);
    expect(find.text("Lito's Mini Mart"), findsOneWidget);
    expect(find.text('Access'), findsNWidgets(2));
    expect(find.text("Don't see your store?"), findsOneWidget);
  });

  testWidgets('Access joins that store', (tester) async {
    final joined = <String>[];
    final done = Completer<void>();
    await tester.pumpWidget(
      _host(
        loadInvites: () async => [_nena, _lito],
        onAccess: (invite) {
          joined.add(invite.storeId);
          return done.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Access').last);
    await tester.pump();

    expect(joined, ['store-lito']);
    // Joining: the other store can't be picked meanwhile.
    expect(find.text('Access'), findsOneWidget);
    await tester.tap(find.text('Access'));
    expect(joined, ['store-lito']);

    done.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a failed join is reported and can be retried', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      _host(
        loadInvites: () async => [_nena],
        onAccess: (_) async {
          attempts++;
          throw Exception('permission-denied');
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Access'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not join'), findsOneWidget);

    await tester.tap(find.text('Access'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets('with no invites, only the note shows', (tester) async {
    await tester.pumpWidget(_host(loadInvites: () async => const []));
    await tester.pumpAndSettle();

    expect(find.text('Access'), findsNothing);
    expect(find.text("Don't see your store?"), findsOneWidget);
  });

  testWidgets('offline, offers a retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(
        loadInvites: () async {
          if (calls++ == 0) throw Exception('unavailable');
          return [_nena];
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load your stores'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text("Aling Nena's Store"), findsOneWidget);
  });
}
