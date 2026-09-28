import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/dashboard_screen.dart';
import '../screens/onboarding_choice_screen.dart';
import '../services/auth_service.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';

/// The second gate, downstream of [AuthGate]: a signed-in user still needs a
/// tindahan before the dashboard means anything.
///
/// Same shape as [AuthGate] — it listens rather than being told. Whatever
/// eventually writes `users/{uid}.activeStoreId` (the create or join flow)
/// does not have to report back; the snapshot lands here and the screen swaps.
class StoreGate extends StatelessWidget {
  const StoreGate({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StoreMembership>(
      stream: StoreService.membershipOf(user.uid),
      builder: (context, snapshot) {
        final error = snapshot.error;
        if (error != null) {
          return _StoreErrorScreen(error: error);
        }

        // `unknown` covers the cache-only miss described in [StoreService] —
        // holding the loader here is what stops a returning owner from being
        // shown "Create a New Tindahan" while the server reply is in flight.
        final membership = snapshot.data ?? const StoreMembership.unknown();
        if (!membership.isResolved) {
          return const _CheckingStoreScreen();
        }

        if (!membership.hasStore) {
          return OnboardingChoiceScreen(
            onCreate: () => _notImplemented(context, 'Create a New Tindahan'),
            onJoin: () => _notImplemented(context, 'Join a Tindahan'),
          );
        }

        return DashboardScreen(user: user);
      },
    );
  }

  /// Stand-in until the Create/Join screens are built. Kept here rather than in
  /// [OnboardingChoiceScreen] so the screen stays free of placeholder logic —
  /// swapping these two lines for `Navigator.push` is the whole wiring job.
  void _notImplemented(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label is not built yet.')),
    );
  }
}

/// Shown while the membership answer is still outstanding. Deliberately says
/// what it is waiting for: offline with an empty cache this can sit for a
/// while, and a bare spinner would read as a hang.
class _CheckingStoreScreen extends StatelessWidget {
  const _CheckingStoreScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.stackMd),
              Text(
                'Checking your tindahan…',
                style: AppTypography.bodySm.copyWith(color: AppColors.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Firestore refused or failed the listen — most likely security rules or no
/// connection on a cold cache. Signing out is the honest escape hatch: it is
/// the one recovery this screen can actually perform.
class _StoreErrorScreen extends StatelessWidget {
  const _StoreErrorScreen({required this.error});

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
                      Icons.storefront_outlined,
                      size: 48,
                      color: AppColors.error,
                    ),
                    const SizedBox(height: AppSpacing.stackMd),
                    Text(
                      'Could not load your tindahan',
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
                      child: OutlinedButton(
                        onPressed: _resetSession,
                        child: const Text('Back to sign in'),
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
