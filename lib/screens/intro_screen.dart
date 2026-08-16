import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/intro_illustrations.dart';

/// One onboarding slide.
class IntroPageData {
  const IntroPageData({
    required this.title,
    required this.body,
    required this.illustration,
  });

  final String title;
  final String body;
  final Widget illustration;
}

/// Three-step onboarding carousel — a Flutter build of the Stitch
/// "Introduction 1/2/3 of 3" screens (project 14772063175572299152).
///
/// Swipe or tap Next to advance; Skip (top right) and "Get Started" on the
/// last slide both call [onDone].
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onDone});

  /// Invoked when the user finishes or skips the intro. The caller is
  /// responsible for persisting `seen_intro` and moving on to sign-in.
  final VoidCallback onDone;

  static const pages = <IntroPageData>[
    IntroPageData(
      title: 'Smart Calculation',
      body:
          'Quickly tally sales with our built-in calculator and search '
          'integration.',
      illustration: CalculationIllustration(),
    ),
    IntroPageData(
      title: 'Inventory Control',
      body:
          'Keep your stock organized. Get alerts for low items and update '
          'prices in seconds.',
      illustration: InventoryIllustration(),
    ),
    IntroPageData(
      title: 'Profit Insights',
      body:
          'Track your daily sales and see your profits grow with simple, '
          'visual analytics.',
      illustration: ProfitIllustration(),
    ),
  ];

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == IntroScreen.pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      widget.onDone();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // Tailwind `max-w-md` — the designs are fixed-width on desktop.
            constraints: const BoxConstraints(maxWidth: 448),
            child: Column(
              children: [
                _buildSkip(),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: IntroScreen.pages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _IntroPage(
                      data: IntroScreen.pages[i],
                    ),
                  ),
                ),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkip() {
    return SizedBox(
      height: 56,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.stackSm),
          child: TextButton(
            onPressed: widget.onDone,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onSurfaceVariant,
              minimumSize: const Size(AppSpacing.touchTarget, AppSpacing.touchTarget),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(AppRadius.base)),
              ),
            ),
            child: Text(
              'SKIP',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.gutter,
        AppSpacing.gutter,
        24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < IntroScreen.pages.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.stackSm),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  width: i == _index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _index
                        ? AppColors.primary
                        : AppColors.outlineVariant,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _next,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                minimumSize: const Size.fromHeight(56),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(AppRadius.base),
                  ),
                ),
              ).copyWith(
                // active:bg-primary-container
                overlayColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.pressed)
                      ? AppColors.primaryContainer
                      : null,
                ),
              ),
              child: Text(
                _isLast ? 'Get Started' : 'Next',
                style: AppTypography.bodyLg.copyWith(
                  color: AppColors.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({required this.data});

  final IntroPageData data;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: AppSpacing.gutter),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: data.illustration,
              ),
              const SizedBox(height: 40),
              Text(
                data.title,
                textAlign: TextAlign.center,
                style: AppTypography.headlineLg.copyWith(
                  color: AppColors.onBackground,
                  letterSpacing: -0.5, // tracking-tight
                ),
              ),
              const SizedBox(height: AppSpacing.stackSm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(
                  data.body,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyLg.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.gutter),
            ],
          ),
        ),
      ),
    );
  }
}
