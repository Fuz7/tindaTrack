import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Placeholder landing screen for a signed-in user.
///
/// Exists so the auth flow has somewhere to go; replace the body with the real
/// dashboard. The sign-out button is the quickest way to exercise the
/// `authStateChanges` round trip back to [SignInScreen].
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName ?? user.email ?? 'there';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.containerMargin),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Signed in as $name',
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineMd.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.stackSm),
                Text(
                  'Dashboard coming soon.',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.outline,
                  ),
                ),
                const SizedBox(height: 32),
                OutlinedButton(
                  onPressed: AuthService.signOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
