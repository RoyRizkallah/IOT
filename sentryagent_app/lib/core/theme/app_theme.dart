import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Material theme assembled from our design tokens.
///
/// Typography:
///  - Plus Jakarta Sans for UI text (warm, modern, neutral)
///  - JetBrains Mono for numeric displays (the threat score, sensor values)
class AppTheme {
  AppTheme._();

  static SystemUiOverlayStyle get systemUiOverlay =>
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.bgBase,
        systemNavigationBarIconBrightness: Brightness.dark,
      );

  static TextStyle get _ui =>
      GoogleFonts.plusJakartaSans(color: AppColors.textPrimary);

  static TextStyle get _mono =>
      GoogleFonts.jetBrainsMono(color: AppColors.textPrimary);

  /// Display style (the threat score in the ring) — monospace numbers.
  static TextStyle get displayMono => _mono.copyWith(
        fontSize: 88,
        fontWeight: FontWeight.w700,
        letterSpacing: -3,
        height: 1,
      );

  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.light,
    ).copyWith(
      surface: AppColors.bgBase,
      onSurface: AppColors.textPrimary,
      primary: AppColors.accent,
      onPrimary: AppColors.textOnAccent,
      secondary: AppColors.accent,
      error: AppColors.threatAlert,
    );

    final textTheme = TextTheme(
      // Hero numerics.
      displayLarge: _mono.copyWith(
        fontSize: 88,
        fontWeight: FontWeight.w700,
        letterSpacing: -3,
        height: 1,
      ),
      displayMedium: _mono.copyWith(
        fontSize: 56,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.5,
        height: 1,
      ),
      // Section headlines.
      headlineMedium: _ui.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.15,
      ),
      headlineSmall: _ui.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.2,
      ),
      titleLarge: _ui.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.25,
      ),
      titleMedium: _ui.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        height: 1.3,
      ),
      titleSmall: _ui.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 0.2,
        height: 1.3,
      ),
      bodyLarge: _ui.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
        height: 1.5,
      ),
      bodyMedium: _ui.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.5,
      ),
      bodySmall: _ui.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textTertiary,
        height: 1.45,
      ),
      // Tiny uppercase labels (sensor names, status pills).
      labelSmall: _ui.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textTertiary,
        letterSpacing: 1.4,
      ),
      labelMedium: _ui.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 0.4,
      ),
      labelLarge: _ui.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: base,
      scaffoldBackgroundColor: AppColors.bgBase,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      cardTheme: CardThemeData(
        color: AppColors.bgSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.textOnAccent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md + 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      iconTheme: const IconThemeData(
        color: AppColors.textSecondary,
        size: 22,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.bgSurface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.bgSurface,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }
}
