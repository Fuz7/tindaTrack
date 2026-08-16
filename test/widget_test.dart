import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tinda_track/screens/intro_screen.dart';
import 'package:tinda_track/screens/sign_in_screen.dart';
import 'package:tinda_track/theme/app_theme.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.light, home: child);

void main() {
  testWidgets('sign-in screen renders the brand, tagline and CTA', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const SignInScreen()));
    await tester.pumpAndSettle();

    expect(find.text('TindaTrack'), findsOneWidget);
    expect(find.text('Track your store, grow your business'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('tapping sign in shows a spinner until the callback resolves', (
    tester,
  ) async {
    final completer = Completer<void>();

    await tester.pumpWidget(
      _wrap(SignInScreen(onSignIn: () => completer.future)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Sign in with Google'), findsNothing);

    completer.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('intro advances through the three slides and then finishes', (
    tester,
  ) async {
    var done = 0;

    await tester.pumpWidget(_wrap(IntroScreen(onDone: () => done++)));
    await tester.pumpAndSettle();

    expect(find.text('Smart Calculation'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Inventory Control'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Profit Insights'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(done, 1);
  });

  testWidgets('intro can be swiped and skipped', (tester) async {
    var done = 0;

    await tester.pumpWidget(_wrap(IntroScreen(onDone: () => done++)));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Inventory Control'), findsOneWidget);

    await tester.tap(find.text('SKIP'));
    await tester.pumpAndSettle();
    expect(done, 1);
  });
}
