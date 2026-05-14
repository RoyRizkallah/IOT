import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Layered, soft elevation tokens for the light theme.
///
/// Two shadows per level: a tight near-shadow for crispness + a wide soft
/// shadow for depth. This is what gives white cards their "lifted" feel
/// without using harsh borders.
class AppShadows {
  AppShadows._();

  /// Resting cards (sensor tiles, list rows).
  static const List<BoxShadow> card = [
    BoxShadow(
      color: AppColors.shadowTight,
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: AppColors.shadowSoft,
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -8,
    ),
  ];

  /// Floating elements (FABs, nav bar, sheets).
  static const List<BoxShadow> floating = [
    BoxShadow(
      color: AppColors.shadowTight,
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: AppColors.shadowSoft,
      blurRadius: 40,
      offset: Offset(0, 16),
      spreadRadius: -12,
    ),
  ];

  /// The hero region — strongest depth, used behind/under the threat ring.
  static const List<BoxShadow> hero = [
    BoxShadow(
      color: Color(0x33101828),
      blurRadius: 60,
      offset: Offset(0, 24),
      spreadRadius: -20,
    ),
  ];
}
