import 'package:flutter/material.dart';

/// Design tokens for the "TindaTrack Utilitarian Monolith" design system.
///
/// Mirrors the frontmatter of `design.md` (Stitch design system
/// `assets/a5c24acfa1ee49cc87433d1985db15ae`). Keep the two in sync.
abstract final class AppColors {
  // Core surfaces
  static const surface = Color(0xFFF5FBF5);
  static const surfaceDim = Color(0xFFD5DCD6);
  static const surfaceBright = Color(0xFFF5FBF5);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFEFF5EF);
  static const surfaceContainer = Color(0xFFE9EFE9);
  static const surfaceContainerHigh = Color(0xFFE4EAE4);
  static const surfaceContainerHighest = Color(0xFFDEE4DE);
  static const surfaceVariant = Color(0xFFDEE4DE);
  static const onSurface = Color(0xFF171D19);
  static const onSurfaceVariant = Color(0xFF3D4A42);
  static const inverseSurface = Color(0xFF2C322E);
  static const inverseOnSurface = Color(0xFFECF2EC);
  static const surfaceTint = Color(0xFF006C4A);

  static const outline = Color(0xFF6D7A72);
  static const outlineVariant = Color(0xFFBCCAC0);

  static const background = Color(0xFFF5FBF5);
  static const onBackground = Color(0xFF171D19);

  // Primary — emerald, the "go / profit" action colour
  static const primary = Color(0xFF006948);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFF00855D);
  static const onPrimaryContainer = Color(0xFFF5FFF7);
  static const inversePrimary = Color(0xFF68DBA9);
  static const primaryFixed = Color(0xFF85F8C4);
  static const primaryFixedDim = Color(0xFF68DBA9);
  static const onPrimaryFixed = Color(0xFF002114);
  static const onPrimaryFixedVariant = Color(0xFF005137);

  // Secondary — structural navy/slate
  static const secondary = Color(0xFF565E74);
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFFDAE2FD);
  static const onSecondaryContainer = Color(0xFF5C647A);
  static const secondaryFixed = Color(0xFFDAE2FD);
  static const secondaryFixedDim = Color(0xFFBEC6E0);
  static const onSecondaryFixed = Color(0xFF131B2E);
  static const onSecondaryFixedVariant = Color(0xFF3F465C);

  // Tertiary
  static const tertiary = Color(0xFF9B3E3B);
  static const onTertiary = Color(0xFFFFFFFF);
  static const tertiaryContainer = Color(0xFFBA5551);
  static const onTertiaryContainer = Color(0xFFFFFBFF);
  static const tertiaryFixed = Color(0xFFFFDAD7);
  static const tertiaryFixedDim = Color(0xFFFFB3AE);
  static const onTertiaryFixed = Color(0xFF410004);
  static const onTertiaryFixedVariant = Color(0xFF7F2928);

  // Error
  static const error = Color(0xFFBA1A1A);
  static const onError = Color(0xFFFFFFFF);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);

  // Semantic extras (traffic-light inventory status)
  static const statusInStock = Color(0xFF10B981);
  static const statusLowStock = Color(0xFFF59E0B);
  static const statusOutOfStock = Color(0xFFEF4444);
  static const actionDestructive = Color(0xFFB91C1C);
  static const surfaceTonal = Color(0xFFF8FAFC);
  static const surfaceBorder = Color(0xFFE2E8F0);
}

/// `spacing` tokens from design.md.
abstract final class AppSpacing {
  static const touchTarget = 48.0; // 3rem
  static const gutter = 16.0; // 1rem
  static const stackSm = 8.0; // 0.5rem
  static const stackMd = 16.0; // 1rem
  static const containerMargin = 16.0; // 1rem
}

/// `rounded` tokens from design.md.
abstract final class AppRadius {
  static const sm = 4.0; // 0.25rem — keypad buttons
  static const base = 8.0; // 0.5rem — buttons, inputs, cards
  static const md = 12.0; // 0.75rem
  static const lg = 16.0; // 1rem
  static const xl = 24.0; // 1.5rem
  static const full = 9999.0; // status chips
}

/// Named type roles from design.md. Inter is the specified family; it is not
/// bundled as an asset yet, so [AppTypography.fontFamily] is left null and the
/// platform default is used. Drop Inter into `assets/fonts/` and set this to
/// 'Inter' to match the design exactly.
abstract final class AppTypography {
  static const String? fontFamily = null;

  static const displayPrice = TextStyle(
    fontFamily: fontFamily,
    fontSize: 48,
    height: 56 / 48,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.02 * 48,
  );

  static const headlineLg = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w700,
  );

  static const headlineMd = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
  );

  static const bodyLg = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w500,
  );

  static const bodySm = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );

  static const labelCaps = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.05 * 12,
  );

  static const numericKeypad = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    height: 1,
    fontWeight: FontWeight.w500,
  );
}

/// Tokens that have no home in [ColorScheme] — reach them with
/// `Theme.of(context).extension<AppStatusColors>()!`.
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.inStock,
    required this.lowStock,
    required this.outOfStock,
    required this.destructive,
    required this.surfaceTonal,
    required this.surfaceBorder,
  });

  final Color inStock;
  final Color lowStock;
  final Color outOfStock;
  final Color destructive;
  final Color surfaceTonal;
  final Color surfaceBorder;

  static const light = AppStatusColors(
    inStock: AppColors.statusInStock,
    lowStock: AppColors.statusLowStock,
    outOfStock: AppColors.statusOutOfStock,
    destructive: AppColors.actionDestructive,
    surfaceTonal: AppColors.surfaceTonal,
    surfaceBorder: AppColors.surfaceBorder,
  );

  @override
  AppStatusColors copyWith({
    Color? inStock,
    Color? lowStock,
    Color? outOfStock,
    Color? destructive,
    Color? surfaceTonal,
    Color? surfaceBorder,
  }) {
    return AppStatusColors(
      inStock: inStock ?? this.inStock,
      lowStock: lowStock ?? this.lowStock,
      outOfStock: outOfStock ?? this.outOfStock,
      destructive: destructive ?? this.destructive,
      surfaceTonal: surfaceTonal ?? this.surfaceTonal,
      surfaceBorder: surfaceBorder ?? this.surfaceBorder,
    );
  }

  @override
  AppStatusColors lerp(covariant AppStatusColors? other, double t) {
    if (other == null) return this;
    return AppStatusColors(
      inStock: Color.lerp(inStock, other.inStock, t)!,
      lowStock: Color.lerp(lowStock, other.lowStock, t)!,
      outOfStock: Color.lerp(outOfStock, other.outOfStock, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      surfaceTonal: Color.lerp(surfaceTonal, other.surfaceTonal, t)!,
      surfaceBorder: Color.lerp(surfaceBorder, other.surfaceBorder, t)!,
    );
  }
}

abstract final class AppTheme {
  static const _colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.onPrimaryContainer,
    primaryFixed: AppColors.primaryFixed,
    primaryFixedDim: AppColors.primaryFixedDim,
    onPrimaryFixed: AppColors.onPrimaryFixed,
    onPrimaryFixedVariant: AppColors.onPrimaryFixedVariant,
    secondary: AppColors.secondary,
    onSecondary: AppColors.onSecondary,
    secondaryContainer: AppColors.secondaryContainer,
    onSecondaryContainer: AppColors.onSecondaryContainer,
    secondaryFixed: AppColors.secondaryFixed,
    secondaryFixedDim: AppColors.secondaryFixedDim,
    onSecondaryFixed: AppColors.onSecondaryFixed,
    onSecondaryFixedVariant: AppColors.onSecondaryFixedVariant,
    tertiary: AppColors.tertiary,
    onTertiary: AppColors.onTertiary,
    tertiaryContainer: AppColors.tertiaryContainer,
    onTertiaryContainer: AppColors.onTertiaryContainer,
    tertiaryFixed: AppColors.tertiaryFixed,
    tertiaryFixedDim: AppColors.tertiaryFixedDim,
    onTertiaryFixed: AppColors.onTertiaryFixed,
    onTertiaryFixedVariant: AppColors.onTertiaryFixedVariant,
    error: AppColors.error,
    onError: AppColors.onError,
    errorContainer: AppColors.errorContainer,
    onErrorContainer: AppColors.onErrorContainer,
    surface: AppColors.surface,
    onSurface: AppColors.onSurface,
    surfaceDim: AppColors.surfaceDim,
    surfaceBright: AppColors.surfaceBright,
    surfaceContainerLowest: AppColors.surfaceContainerLowest,
    surfaceContainerLow: AppColors.surfaceContainerLow,
    surfaceContainer: AppColors.surfaceContainer,
    surfaceContainerHigh: AppColors.surfaceContainerHigh,
    surfaceContainerHighest: AppColors.surfaceContainerHighest,
    onSurfaceVariant: AppColors.onSurfaceVariant,
    outline: AppColors.outline,
    outlineVariant: AppColors.outlineVariant,
    inverseSurface: AppColors.inverseSurface,
    onInverseSurface: AppColors.inverseOnSurface,
    inversePrimary: AppColors.inversePrimary,
    surfaceTint: AppColors.surfaceTint,
  );

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: _colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: AppTypography.fontFamily,
    extensions: const [AppStatusColors.light],
    textTheme: const TextTheme(
      displayLarge: AppTypography.displayPrice,
      headlineLarge: AppTypography.headlineLg,
      headlineMedium: AppTypography.headlineMd,
      titleMedium: AppTypography.headlineMd,
      bodyLarge: AppTypography.bodyLg,
      bodyMedium: AppTypography.bodySm,
      bodySmall: AppTypography.bodySm,
      labelSmall: AppTypography.labelCaps,
    ).apply(bodyColor: AppColors.onSurface, displayColor: AppColors.onSurface),
    // Design system: no shadows, 1px outlines, 8px radius.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSpacing.touchTarget),
        textStyle: AppTypography.bodyLg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.base)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSpacing.touchTarget),
        textStyle: AppTypography.bodyLg,
        side: const BorderSide(color: AppColors.outlineVariant),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.base)),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.base),
        borderSide: const BorderSide(color: AppColors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.base),
        borderSide: const BorderSide(color: AppColors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.base),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.outlineVariant,
      thickness: 1,
      space: 1,
    ),
  );
}
