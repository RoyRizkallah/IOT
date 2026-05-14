import 'package:flutter/material.dart';

import '../../data/models/security_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Compact, pastel-backed severity badge. Used in event lists, decision cards,
/// and detail headers — same look everywhere so severity is instantly readable.
class SeverityPill extends StatelessWidget {
  const SeverityPill({super.key, required this.level, this.dense = false});

  final ThreatLevel level;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (level) {
      ThreatLevel.safe => (AppColors.threatSafe, AppColors.threatSafeSoft),
      ThreatLevel.warning => (AppColors.threatWarning, AppColors.threatWarningSoft),
      ThreatLevel.alert => (AppColors.threatAlert, AppColors.threatAlertSoft),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.xs : AppSpacing.sm,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            level.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg,
                  letterSpacing: 1.2,
                ),
          ),
        ],
      ),
    );
  }
}
