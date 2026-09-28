import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Fork shown to a signed-in user who has no tindahan yet — a faithful Flutter
/// build of the Stitch "Onboarding Choice" design (project
/// 14772063175572299152, screen 2f083d2f…).
///
/// Dumb by design, like [SignInScreen]: it renders two options and reports the
/// tap upward. Deciding what "create" and "join" actually do is the shell's
/// job.
class OnboardingChoiceScreen extends StatelessWidget {
  const OnboardingChoiceScreen({
    super.key,
    required this.onCreate,
    required this.onJoin,
  });

  /// "Create a New Tindahan" — register a brand new store.
  final VoidCallback onCreate;

  /// "Join a Tindahan" — attach to a store the user was invited to.
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.containerMargin),
            child: ConstrainedBox(
              // Tailwind `max-w-md`
              constraints: const BoxConstraints(maxWidth: 448),
              child: Container(
                padding: const EdgeInsets.all(24), // p-6
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  // `rounded-xl` is 0.75rem in this design system, not 1.5rem.
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Header(),
                    const SizedBox(height: 32), // gap-8
                    _OptionCard(
                      icon: Icons.add_business,
                      title: 'Create a New Tindahan',
                      body:
                          'Start fresh. Register your store details and begin '
                          'tracking your inventory and sales immediately.',
                      onTap: onCreate,
                      filled: true,
                    ),
                    const SizedBox(height: AppSpacing.stackMd),
                    _OptionCard(
                      icon: Icons.group_add,
                      title: 'Join a Tindahan',
                      body:
                          "Authorized as a collaborator? Sign in with your "
                          "registered email to access a store's inventory and "
                          'start logging sales.',
                      onTap: onJoin,
                      filled: false,
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

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.base),
          ),
          child: const Icon(
            Icons.storefront,
            size: 32,
            color: AppColors.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 8), // mb-2
        Text(
          'Get Started',
          textAlign: TextAlign.center,
          style: AppTypography.headlineLg.copyWith(color: AppColors.onSurface),
        ),
        const SizedBox(height: AppSpacing.stackSm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280), // max-w-[280px]
          child: Text(
            'Set up your own store or join an existing one to collaborate.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// One of the two choices. [filled] picks the emerald primary treatment
/// (create) over the outlined one (join).
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    required this.filled,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final background = filled
        ? AppColors.primary
        : AppColors.surfaceContainerLowest;
    final borderColor = filled ? AppColors.primary : AppColors.outline;
    final titleColor = filled ? AppColors.onPrimary : AppColors.primary;
    final bodyColor = filled
        // text-on-primary/90
        ? AppColors.onPrimary.withValues(alpha: 0.9)
        : AppColors.onSurfaceVariant;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.base),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.base),
        // hover:/active: states from the design, as overlays on the base fill.
        hoverColor: filled
            ? AppColors.primaryContainer
            : AppColors.surfaceContainerLow,
        highlightColor: filled
            ? AppColors.surfaceTint
            : AppColors.surfaceContainerHigh,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.base),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.all(24), // p-6
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 24, color: titleColor),
                  const SizedBox(width: 12), // gap-3
                  Expanded(
                    child: Text(
                      title,
                      style: AppTypography.headlineMd.copyWith(
                        color: titleColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8), // gap-2
              Padding(
                // pl-9 — aligns the copy with the title, past the icon.
                padding: const EdgeInsets.only(left: 36),
                child: Text(
                  body,
                  style: AppTypography.bodySm.copyWith(color: bodyColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
