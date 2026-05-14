import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/format.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/sensor_meta.dart';
import '../../../core/widgets/severity_pill.dart';
import '../../../data/models/security_state.dart';

/// Premium bottom sheet for inspecting a single security event.
///
///  - Severity-tinted hero strip
///  - Large sensor avatar + severity badge
///  - Detail KV grid
///  - Primary "Acknowledge" + secondary "Mute sensor" actions
///
/// Open via [showEventDetailSheet].
class EventDetailSheet extends StatelessWidget {
  const EventDetailSheet({super.key, required this.event});

  final SecurityEvent event;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final sensorColor = SensorMeta.color(event.sensor);

    final (heroFrom, heroTo) = switch (event.severity) {
      ThreatLevel.safe => (
          AppColors.threatSafeSoft,
          AppColors.bgSurface,
        ),
      ThreatLevel.warning => (
          AppColors.threatWarningSoft,
          AppColors.bgSurface,
        ),
      ThreatLevel.alert => (
          AppColors.threatAlertSoft,
          AppColors.bgSurface,
        ),
    };

    return SafeArea(
      top: false,
      child: Container(
        margin: EdgeInsets.only(top: media.padding.top + 60),
        decoration: const BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(28),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Hero strip ──────────────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [heroFrom, heroTo],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.bgSurface,
                                  shape: BoxShape.circle,
                                  boxShadow: AppShadows.card,
                                ),
                                child: Icon(
                                  SensorMeta.icon(event.sensor),
                                  color: sensorColor,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      event.sensor.displayName.toUpperCase(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: sensorColor,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.4,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Sensor event',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              SeverityPill(level: event.severity),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            event.message,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(height: 1.3),
                          ),
                        ],
                      ),
                    ),

                    // ── Detail rows ─────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.md,
                      ),
                      child: Column(
                        children: [
                          _DetailRow(
                            icon: Icons.schedule_rounded,
                            label: 'When',
                            value: '${absoluteFull(event.timestamp)}\n'
                                '${relativeTime(event.timestamp)}',
                          ),
                          const _SoftDivider(),
                          _DetailRow(
                            icon: Icons.fingerprint_rounded,
                            label: 'Event ID',
                            value: event.id,
                            mono: true,
                            copyable: true,
                          ),
                          const _SoftDivider(),
                          _DetailRow(
                            icon: Icons.bolt_rounded,
                            label: 'Severity',
                            value: event.severity.label,
                          ),
                          const _SoftDivider(),
                          _DetailRow(
                            icon: Icons.check_circle_outline_rounded,
                            label: 'Status',
                            value: 'Logged',
                            valueColor: AppColors.threatSafe,
                          ),
                        ],
                      ),
                    ),

                    // ── Action buttons ──────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _SecondaryButton(
                              icon: Icons.notifications_off_outlined,
                              label: 'Mute 1h',
                              onTap: () {
                                Haptics.tap();
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(SnackBar(
                                    content: Text(
                                      '${event.sensor.displayName} muted for 1h',
                                    ),
                                  ));
                              },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            flex: 2,
                            child: _PrimaryButton(
                              icon: Icons.check_rounded,
                              label: 'Acknowledge',
                              onTap: () {
                                Haptics.confirm();
                                Navigator.of(context).pop();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showEventDetailSheet(
  BuildContext context,
  SecurityEvent event,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.overlayScrim,
    builder: (_) => EventDetailSheet(event: event),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.mono = false,
    this.copyable = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool mono;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.bgMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                        letterSpacing: 1.2,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: valueColor ?? AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontFamily: mono ? 'monospace' : null,
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
          if (copyable)
            IconButton(
              icon: const Icon(
                Icons.copy_rounded,
                size: 16,
                color: AppColors.textTertiary,
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                Haptics.tap();
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(
                    content: Text('Copied to clipboard'),
                  ));
              },
            ),
        ],
      ),
    );
  }
}

class _SoftDivider extends StatelessWidget {
  const _SoftDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: AppColors.divider,
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgMuted,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.textSecondary, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
