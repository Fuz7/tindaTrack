import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinda_track/screens/onboarding_choice_screen.dart';
import 'package:tinda_track/theme/app_theme.dart';

void main() {
  Widget host({VoidCallback? onCreate, VoidCallback? onJoin}) {
    return MaterialApp(
      theme: AppTheme.light,
      home: OnboardingChoiceScreen(
        onCreate: onCreate ?? () {},
        onJoin: onJoin ?? () {},
      ),
    );
  }

  testWidgets('renders both choices', (tester) async {
    await tester.pumpWidget(host());

    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Create a New Tindahan'), findsOneWidget);
    expect(find.text('Join a Tindahan'), findsOneWidget);
  });

  testWidgets('reports each choice upward', (tester) async {
    var created = 0;
    var joined = 0;
    await tester.pumpWidget(
      host(onCreate: () => created++, onJoin: () => joined++),
    );

    await tester.tap(find.text('Create a New Tindahan'));
    await tester.tap(find.text('Join a Tindahan'));

    expect(created, 1);
    expect(joined, 1);
  });

  testWidgets('fits a small phone without overflowing', (tester) async {
    // 360×640 is the narrow end of the Android range the design targets.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
