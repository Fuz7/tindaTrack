import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/sign_in_screen.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'store_gate.dart';

/// Shows sign-in or the signed-in app purely as a function of Firebase auth
/// state.
///
/// Nothing tells this widget that a sign-in succeeded — `authStateChanges`
/// fires on sign-in, on sign-out from anywhere in the app, and once at startup
/// with the restored session, so returning users skip [SignInScreen] entirely.
///
/// A signed-in user is handed to [StoreGate] rather than straight to the
/// dashboard — having an account and having a tindahan are separate questions.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authState,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // A failed stream also leaves `data` null, which is indistinguishable
        // from "signed out". Check the error first so a real fault surfaces
        // instead of quietly bouncing the user back to sign-in.
        final error = snapshot.error;
        if (error != null) {
          return _AuthErrorScreen(error: error);
        }

        final user = snapshot.data;
        return user == null
            ? SignInScreen(onSignIn: AuthService.signInWithGoogle)
            : StoreGate(user: user);
      },
    );
  }
}

/// Shown when the auth stream itself fails, rather than reporting a signed-out
/// user. Signing out is the one recovery worth offering — it clears whatever
/// local session state is wedged, and the resulting `null` event puts the gate
/// back on [SignInScreen].
class _AuthErrorScreen extends StatelessWidget {
  const _AuthErrorScreen({required this.error});

  final Object error;

  Future<void> _resetSession() async {
    try {
      await AuthService.signOut();
    } catch (_) {
      // Already displaying a failure; a failed sign-out adds nothing.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.containerMargin),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: AppColors.error,
                    ),
                    const SizedBox(height: AppSpacing.stackMd),
                    Text(
                      'Could not check your sign-in',
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineMd.copyWith(
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.stackSm),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.gutter),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer,
                        borderRadius: BorderRadius.circular(AppRadius.base),
                      ),
                      child: Text(
                        '$error',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onErrorContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.stackMd),
                    SizedBox(
                      height: AppSpacing.touchTarget,
                      child: FilledButton(
                        onPressed: _resetSession,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(
                              Radius.circular(AppRadius.base),
                            ),
                          ),
                        ),
                        child: Text(
                          'Back to sign in',
                          style: AppTypography.bodyLg.copyWith(
                            color: AppColors.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
