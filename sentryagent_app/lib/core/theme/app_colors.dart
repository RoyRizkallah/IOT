import 'package:flutter/material.dart';

/// SentryAgent color system — light theme, premium security feel.
///
/// Direction:
///  - Pale, calm, trustworthy background (clinical-but-warm)
///  - Pure white surfaces with layered soft shadows (no harsh borders)
///  - One confident security blue as the primary accent
///  - A hero gradient (blue → violet → cyan) used behind the threat ring
///  - Three saturated threat colors with matching pastel "halo" backgrounds
///  - Per-sensor accent colors so each tile is recognizable at a glance
///
/// RULE: do not introduce new colors anywhere in the app. If you need a color
/// that isn't here, add it here first with a name that explains its purpose.
class AppColors {
  AppColors._();

  // ── Surfaces ──────────────────────────────────────────────────────────
  static const Color bgBase = Color(0xFFF6F8FC);     // app background
  static const Color bgSurface = Color(0xFFFFFFFF);  // cards, sheets
  static const Color bgElevated = Color(0xFFFFFFFF); // raised cards (with stronger shadow)
  static const Color bgMuted = Color(0xFFEEF1F7);    // chip backgrounds, subtle fills
  static const Color border = Color(0xFFE3E7EF);     // hairline dividers
  static const Color borderStrong = Color(0xFFD3D9E4);

  // ── Text ──────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF0B1020);   // ink
  static const Color textSecondary = Color(0xFF515A6E);
  static const Color textTertiary = Color(0xFF8A93A6);
  static const Color textOnAccent = Color(0xFFFFFFFF);

  // ── Primary (single confident security blue) ──────────────────────────
  static const Color accent = Color(0xFF2954FF);       // primary action / brand
  static const Color accentSoft = Color(0xFFE8EEFF);   // tinted background for primary
  static const Color accentDeep = Color(0xFF1A38C7);

  // ── Hero gradient (used behind the threat ring) ───────────────────────
  // Blue → violet → cyan. Subtle, never garish.
  static const List<Color> heroGradientSafe = [
    Color(0xFF2954FF),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
  ];
  static const List<Color> heroGradientWarning = [
    Color(0xFFF97316),
    Color(0xFFF59E0B),
    Color(0xFFEAB308),
  ];
  static const List<Color> heroGradientAlert = [
    Color(0xFFEF4444),
    Color(0xFFE11D48),
    Color(0xFFB91C1C),
  ];

  // ── Threat states (the visual core) ───────────────────────────────────
  static const Color threatSafe = Color(0xFF10B981);
  static const Color threatSafeSoft = Color(0xFFE6F8F1);
  static const Color threatWarning = Color(0xFFF59E0B);
  static const Color threatWarningSoft = Color(0xFFFFF4DD);
  static const Color threatAlert = Color(0xFFEF4444);
  static const Color threatAlertSoft = Color(0xFFFFE7E7);

  // ── Per-sensor accents (for the tile stripe + icon halo) ──────────────
  static const Color sensorMotion = Color(0xFF06B6D4);   // cyan
  static const Color sensorMotionSoft = Color(0xFFE0F7FB);
  static const Color sensorSound = Color(0xFF8B5CF6);    // violet
  static const Color sensorSoundSoft = Color(0xFFEFE9FF);
  static const Color sensorDoor = Color(0xFF10B981);     // emerald
  static const Color sensorDoorSoft = Color(0xFFE6F8F1);
  static const Color sensorTemp = Color(0xFFF97316);     // coral
  static const Color sensorTempSoft = Color(0xFFFFEDDF);

  // ── Shadows ───────────────────────────────────────────────────────────
  // Layered shadows: a near-tight one for crispness, a softer wide one for depth.
  static const Color shadowTight = Color(0x14101828);   // ~8% near-black-blue
  static const Color shadowSoft = Color(0x0F2954FF);    // ~6% accent-tinted

  // ── Misc ──────────────────────────────────────────────────────────────
  static const Color divider = Color(0xFFEAEDF3);
  static const Color overlayScrim = Color(0x80101828);  // modal scrims
}
