import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/sign_in_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('Firebase connected: ${Firebase.app().options.projectId}');

  runApp(const TindaTrackApp());
}

class TindaTrackApp extends StatelessWidget {
  const TindaTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TindaTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const SignInScreen(),
    );
  }
}
