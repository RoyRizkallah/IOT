import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';

/// A white card with the canonical layered shadows. Used everywhere lists or
/// tiles need a "lifted" surface against the pale background.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.borderRadius,
    this.color,
    this.onTap,
    this.shadows,
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final Color? color;
  final VoidCallback? onTap;
  final List<BoxShadow>? shadows;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.lg);
    final card = Container(
      decoration: BoxDecoration(
        color: color ?? AppColors.bgSurface,
        borderRadius: radius,
        boxShadow: shadows ?? AppShadows.card,
        border: border,
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        splashColor: AppColors.accentSoft,
        highlightColor: AppColors.accentSoft.withValues(alpha: 0.5),
        onTap: onTap,
        child: card,
      ),
    );
  }
}
