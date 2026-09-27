import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/google_g_logo.dart';

/// Entry screen — a faithful Flutter build of the Stitch "Sign In (Google)"
/// design (project 14772063175572299152, screen 980d26d1…).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.onSignIn});

  /// Invoked when the user taps "Sign in with Google". While the returned
  /// future is in flight the button shows a spinner and is disabled.
  ///
  /// Required and non-nullable so a screen with a dead button cannot be built
  /// by accident. The screen never learns whether sign-in succeeded — the app
  /// shell reacts to `AuthService.authState` instead.
  final Future<void> Function() onSignIn;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.12),
    end: Offset.zero,
  ).animate(_fade);

  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (_busy) return;

    setState(() => _busy = true);
    try {
      await widget.onSignIn();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Couldn't sign in. Please try again."),
          backgroundColor: AppColors.error,
        ),
      );
      debugPrint('Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                // Bounds the height so the Spacer below can distribute the
                // leftover space (a Column with flex children cannot live
                // directly inside an unbounded scroll view).
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      // Tailwind `max-w-md`
                      constraints: const BoxConstraints(maxWidth: 448),
                      child: Padding(
                        padding: const EdgeInsets.all(
                          AppSpacing.containerMargin,
                        ),
                        child: FadeTransition(
                          opacity: _fade,
                          child: SlideTransition(
                            position: _slide,
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 40),
                                _buildBrand(theme),
                                const SizedBox(height: 48),
                                _buildTagline(theme, colors),
                                const Spacer(),
                                _buildGoogleButton(theme, colors),
                                const SizedBox(height: AppSpacing.stackMd),
                                _buildTerms(theme, colors),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBrand(ThemeData theme) {
    return Column(
      children: [
        // 96×96 white tile, 12px radius, 1px outline — no shadow-heavy card.
        Container(
          width: 96,
          height: 96,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.base),
            child: Image.asset(
              'assets/images/tindatrack_logo.jpg',
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.stackMd),
        Text(
          'TindaTrack',
          textAlign: TextAlign.center,
          style: AppTypography.headlineLg.copyWith(
            color: AppColors.primary,
            letterSpacing: -0.5, // tracking-tight
          ),
        ),
      ],
    );
  }

  Widget _buildTagline(ThemeData theme, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Column(
        children: [
          Text(
            'Track your store, grow your business',
            textAlign: TextAlign.center,
            style: AppTypography.headlineMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.stackSm),
          Text(
            'The professional tool for sari-sari store owners.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(color: AppColors.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleButton(ThemeData theme, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: SizedBox(
        height: AppSpacing.touchTarget,
        child: OutlinedButton(
          onPressed: _busy ? null : _handleSignIn,
          style:
              OutlinedButton.styleFrom(
                backgroundColor: AppColors.surfaceContainerLowest,
                disabledBackgroundColor: AppColors.surfaceContainerLow,
                foregroundColor: AppColors.onSurface,
                side: const BorderSide(color: AppColors.outlineVariant),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.gutter,
                ),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(AppRadius.base),
                  ),
                ),
              ).copyWith(
                // active:bg-surface-container-high / hover:bg-surface-container-low
                overlayColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.pressed)) {
                    return AppColors.surfaceContainerHigh;
                  }
                  if (states.contains(WidgetState.hovered)) {
                    return AppColors.surfaceContainerLow;
                  }
                  return null;
                }),
              ),
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const GoogleGLogo(size: 20),
                    const SizedBox(width: 12), // gap-3
                    Flexible(
                      child: Text(
                        'Sign in with Google',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyLg.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildTerms(ThemeData theme, ColorScheme colors) {
    final base = AppTypography.bodySm.copyWith(color: AppColors.outline);
    final link = AppTypography.bodySm.copyWith(color: AppColors.primary);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            const TextSpan(text: 'By signing in, you agree to our\n'),
            TextSpan(text: 'Terms of Service', style: link),
            const TextSpan(text: ' and '),
            TextSpan(text: 'Privacy Policy', style: link),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
