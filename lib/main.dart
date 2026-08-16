import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'screens/intro_screen.dart';
import 'screens/sign_in_screen.dart';
import 'theme/app_theme.dart';

const kSeenIntroKey = 'seen_intro';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final prefs = await SharedPreferences.getInstance();
  final seenIntro = prefs.getBool(kSeenIntroKey) ?? false;

  debugPrint('Firebase connected: ${Firebase.app().options.projectId}');

  runApp(TindaTrackApp(seenIntro: seenIntro));
}

class TindaTrackApp extends StatefulWidget {
  const TindaTrackApp({super.key, this.seenIntro = false});

  /// Whether this device has already been through the onboarding carousel.
  /// When false the app opens on [IntroScreen] instead of [SignInScreen].
  final bool seenIntro;

  @override
  State<TindaTrackApp> createState() => _TindaTrackAppState();
}

class _TindaTrackAppState extends State<TindaTrackApp> {
  late bool _showIntro = !widget.seenIntro;

  /// Remembers that the intro is done, then drops the user on sign-in.
  Future<void> _completeIntro() async {
    if (mounted) setState(() => _showIntro = false);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kSeenIntroKey, true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TindaTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: _showIntro
          ? IntroScreen(onDone: _completeIntro)
          : const SignInScreen(),
    );
  }
}
