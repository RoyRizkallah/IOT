import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/format.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/sensor_meta.dart';
import '../../../data/models/security_state.dart';
import '../../history/widgets/event_detail_sheet.dart';

/// Compact preview of the 3 most recent events. Each row taps into the
/// shared event-detail sheet, so the home screen feels connected to History
/// without making the user navigate.
class RecentEventsCard extends StatelessWidget {
  const RecentEventsCard({
    super.key,
    required this.events,
    required this.onSeeAll,
  });

  final List<SecurityEvent> events;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final sorted = [...events]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final top = sorted.take(3).toList();

    if (top.isEmpty) return _EmptyCard();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header row inside the card
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm + 2,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Text(
                  'LATEST ACTIVITY',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Haptics.tap();
                    onSeeAll();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'See all',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.accent,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < top.length; i++) ...[
            if (i > 0) const _InsetDivider(),
            _EventRow(event: top[i]),
          ],
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final SecurityEvent event;

  @override
  Widget build(BuildContext context) {
    final severityColor = switch (event.severity) {
      ThreatLevel.safe => AppColors.threatSafe,
      ThreatLevel.warning => AppColors.threatWarning,
      ThreatLevel.alert => AppColors.threatAlert,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashColor: AppColors.accentSoft,
        highlightColor: AppColors.accentSoft.withValues(alpha: 0.5),
        onTap: () {
          Haptics.tap();
          showEventDetailSheet(context, event);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs + 2,
            AppSpacing.md,
            AppSpacing.xs + 2,
          ),
          child: Row(
            children: [
              SensorIconChip(type: event.sensor, size: 32),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: severityColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          event.severity.label,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: severityColor,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '·',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          relativeTime(event.timestamp),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                DateFormat('HH:mm').format(event.timestamp),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsetDivider extends StatelessWidget {
  const _InsetDivider();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 60),
      child: Divider(height: 1, thickness: 1, color: AppColors.divider),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.bgMuted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.event_note_rounded,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No activity yet',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  'Events will appear here as they happen.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
