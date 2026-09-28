import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The frame both "Create New Tindahan" steps share in the Stitch designs: a
/// back-button header with a step pill, a scrolling body, and a sticky primary
/// action pinned above the keyboard.
class CreateStoreScaffold extends StatelessWidget {
  const CreateStoreScaffold({
    super.key,
    required this.step,
    required this.stepLabel,
    required this.actionLabel,
    required this.onAction,
    required this.child,
    this.busy = false,
  });

  /// 1-based step number, out of two.
  final int step;

  /// Subtitle after "Step n of 2:", e.g. "Store Setup".
  final String stepLabel;

  final String actionLabel;

  /// Null while [busy], which also disables the back button — leaving mid-write
  /// would strand the user on a screen the gate has already moved past.
  final VoidCallback? onAction;

  final bool busy;
  final Widget child;

  static const totalSteps = 2;

  /// Button (h-14) + padding on both sides + the 1px top border.
  static const _actionBarHeight = 56 + 2 * AppSpacing.containerMargin + 1;

  /// Shows [message] floating just above the sticky action bar. A default
  /// snackbar would sit on top of the bar, hiding the very button a "try
  /// again" message is pointing at.
  static void showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.containerMargin,
          0,
          AppSpacing.containerMargin,
          _actionBarHeight + AppSpacing.stackSm,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              // Tailwind `max-w-md`
              constraints: const BoxConstraints(maxWidth: 448),
              child: Column(
                children: [
                  _Header(step: step, stepLabel: stepLabel, busy: busy),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.containerMargin,
                        24,
                        AppSpacing.containerMargin,
                        24,
                      ),
                      child: child,
                    ),
                  ),
                  _ActionBar(
                    label: actionLabel,
                    onPressed: busy ? null : onAction,
                    busy: busy,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.step,
    required this.stepLabel,
    required this.busy,
  });

  final int step;
  final String stepLabel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    const total = CreateStoreScaffold.totalSteps;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter - 8, // px-gutter, with the -ml-2 button
        vertical: 4,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Go back',
            onPressed: busy ? null : () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            color: AppColors.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Create New Tindahan',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.headlineMd.copyWith(
                    color: AppColors.onSurface,
                    height: 1.25,
                  ),
                ),
                Text(
                  'Step $step of $total: $stepLabel',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 16 / 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.stackSm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(
              'Step $step/$total',
              style: const TextStyle(
                fontSize: 12,
                height: 16 / 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.label,
    required this.onPressed,
    required this.busy,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.containerMargin),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: SizedBox(
        height: 56, // h-14
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            // Keep the emerald while busy; a greyed button reads as "broken".
            disabledBackgroundColor: AppColors.primary,
            disabledForegroundColor: AppColors.onPrimary,
          ),
          child: busy
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.onPrimary,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.headlineMd.copyWith(
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward),
                  ],
                ),
        ),
      ),
    );
  }
}
