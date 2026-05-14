import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/security_state.dart';

/// One-line context-aware status pill that lives just under the threat ring.
///
/// Reads the current security state + recent events and renders a single
/// "smart" line, e.g.:
///
///   • Stable for 2h 14m · all sensors quiet
///   • 3 events today · last 6m ago
///   • Investigating · agent reasoning
///   • Alert active — reviewing now
class SmartInsightChip extends StatelessWidget {
  const SmartInsightChip({
    super.key,
    required this.state,
    required this.events,
  });

  final SecurityState state;
  final List<SecurityEvent> events;

  _Insight _compute() {
    final now = DateTime.now();
    final todayCount = events
        .where(
          (e) =>
              e.timestamp.year == now.year &&
              e.timestamp.month == now.month &&
              e.timestamp.day == now.day,
        )
        .length;
    final mostRecent = events.isEmpty
        ? null
        : events.reduce(
            (a, b) => a.timestamp.isAfter(b.timestamp) ? a : b,
          );

    switch (state.level) {
      case ThreatLevel.alert:
        return _Insight(
          icon: Icons.priority_high_rounded,
          label: 'ALERT ACTIVE',
          detail: 'Reviewing siren trigger',
          fg: AppColors.threatAlert,
          bg: AppColors.threatAlertSoft,
          pulse: true,
        );
      case ThreatLevel.warning:
        return _Insight(
          icon: Icons.bolt_rounded,
          label: 'INVESTIGATING',
          detail: 'Agent reasoning · $todayCount today',
          fg: AppColors.threatWarning,
          bg: AppColors.threatWarningSoft,
          pulse: true,
        );
      case ThreatLevel.safe:
        if (mostRecent == null) {
          return _Insight(
            icon: Icons.check_circle_rounded,
            label: 'ALL CLEAR',
            detail: 'No events recorded',
            fg: AppColors.threatSafe,
            bg: AppColors.threatSafeSoft,
          );
        }
        final since = now.difference(mostRecent.timestamp);
        if (since.inMinutes < 30) {
          return _Insight(
            icon: Icons.history_rounded,
            label: '$todayCount TODAY',
            detail: 'Last ${_short(since)} ago',
            fg: AppColors.accent,
            bg: AppColors.accentSoft,
          );
        }
        return _Insight(
          icon: Icons.shield_rounded,
          label: 'STABLE',
          detail: 'Quiet for ${_short(since)}',
          fg: AppColors.threatSafe,
          bg: AppColors.threatSafeSoft,
        );
    }
  }

  String _short(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) {
      final m = d.inMinutes % 60;
      return m == 0 ? '${d.inHours}h' : '${d.inHours}h ${m}m';
    }
    return '${d.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final i = _compute();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SizeTransition(
          sizeFactor: anim,
          axisAlignment: -1,
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey('${i.label}-${i.detail}'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: i.bg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: i.fg.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i.pulse)
              _PulsingDot(color: i.fg)
            else
              Icon(i.icon, size: 14, color: i.fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                i.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: i.fg,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
              ),
            ),
            Container(
              width: 3,
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: i.fg.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
            Flexible(
              child: Text(
                i.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Insight {
  const _Insight({
    required this.icon,
    required this.label,
    required this.detail,
    required this.fg,
    required this.bg,
    this.pulse = false,
  });
  final IconData icon;
  final String label;
  final String detail;
  final Color fg;
  final Color bg;
  final bool pulse;
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return SizedBox(
          width: 14,
          height: 14,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.18 * (1 - t)),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
