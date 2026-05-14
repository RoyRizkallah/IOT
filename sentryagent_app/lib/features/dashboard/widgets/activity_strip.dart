import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/security_state.dart';

/// 24-hour activity timeline rendered as 24 vertical bars (one per hour).
///
/// Each bar's height is scaled by the number of events in that hour and its
/// color is determined by the most severe event in the bucket. Empty hours
/// render as a tiny dot at the baseline so the rhythm of the day is always
/// readable.
class ActivityStrip extends StatelessWidget {
  const ActivityStrip({
    super.key,
    required this.events,
    this.height = 36,
  });

  final List<SecurityEvent> events;
  final double height;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // 24 hourly buckets ending at "now". Index 23 = current hour.
    final buckets = List<List<SecurityEvent>>.generate(24, (_) => []);
    for (final e in events) {
      final hoursAgo = now.difference(e.timestamp).inMinutes / 60;
      if (hoursAgo < 0 || hoursAgo >= 24) continue;
      final idx = 23 - hoursAgo.floor();
      if (idx >= 0 && idx < 24) buckets[idx].add(e);
    }

    final maxCount = buckets
        .map((b) => b.length)
        .fold<int>(0, (m, c) => c > m ? c : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 2.0;
              final barWidth =
                  (constraints.maxWidth - gap * 23) / 24;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 24; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    SizedBox(
                      width: barWidth,
                      height: height,
                      child: _HourBar(
                        events: buckets[i],
                        maxCount: maxCount,
                        isCurrent: i == 23,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '24h ago',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
            Text(
              'now',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HourBar extends StatelessWidget {
  const _HourBar({
    required this.events,
    required this.maxCount,
    required this.isCurrent,
  });

  final List<SecurityEvent> events;
  final int maxCount;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      // No activity → tiny dot on the baseline.
      return Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 3,
          width: 3,
          decoration: BoxDecoration(
            color: isCurrent
                ? AppColors.accent
                : AppColors.borderStrong,
            shape: BoxShape.circle,
          ),
        ),
      );
    }

    // Most severe wins for color
    final worst = events
        .map((e) => e.severity)
        .reduce((a, b) => a.index >= b.index ? a : b);
    final color = switch (worst) {
      ThreatLevel.safe => AppColors.threatSafe,
      ThreatLevel.warning => AppColors.threatWarning,
      ThreatLevel.alert => AppColors.threatAlert,
    };

    final ratio = maxCount == 0 ? 0.0 : events.length / maxCount;
    final relHeight = (0.18 + 0.82 * ratio).clamp(0.18, 1.0);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: relHeight),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, h, _) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: h,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    color,
                    color.withValues(alpha: 0.55),
                  ],
                ),
                borderRadius: BorderRadius.circular(2),
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Compact "X events today · last Ym ago" caption used alongside the strip.
class ActivitySummaryLine extends StatelessWidget {
  const ActivitySummaryLine({super.key, required this.events});

  final List<SecurityEvent> events;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final last24h =
        events.where((e) => now.difference(e.timestamp).inHours < 24).length;
    final mostRecent = events.isEmpty
        ? null
        : events.reduce(
            (a, b) => a.timestamp.isAfter(b.timestamp) ? a : b,
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Text(
            'Activity',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 7,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$last24h in 24h',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
            ),
          ),
          const Spacer(),
          if (mostRecent != null)
            Text(
              'last ${_compactAgo(mostRecent.timestamp, now)}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
        ],
      ),
    );
  }

  String _compactAgo(DateTime t, DateTime now) {
    final d = now.difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}
