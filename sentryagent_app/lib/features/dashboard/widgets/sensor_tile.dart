import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/press_scale.dart';
import '../../../core/widgets/sensor_meta.dart';
import '../../../data/models/security_state.dart';

/// A single sensor tile in the 2×N grid below the threat ring.
///
///  - White card with layered soft shadow
///  - 6px top stripe with gradient fade from sensor color → transparent
///  - Vivid gradient fill on the card when sensor is active
///  - Larger value display for better at-a-glance reading
class SensorTile extends StatelessWidget {
  const SensorTile({
    super.key,
    required this.reading,
    required this.onTap,
  });

  final SensorReading reading;
  final VoidCallback onTap;

  String get _displayValue {
    switch (reading.type) {
      case SensorType.motion:
        return reading.active ? 'DETECTED' : 'CLEAR';
      case SensorType.sound:
        return '${reading.value.toStringAsFixed(0)}${reading.type.unit}';
      case SensorType.temperature:
        return '${reading.value.toStringAsFixed(1)}${reading.type.unit}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = SensorMeta.color(reading.type);
    final colorSoft = SensorMeta.colorSoft(reading.type);

    return PressScale(
      onTap: onTap,
      haptic: HapticLevel.tap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Hero(
        tag: 'sensor-${reading.type.name}',
        flightShuttleBuilder: _shuttle,
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: reading.active
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.18),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                        spreadRadius: -4,
                      ),
                      ...AppShadows.card,
                    ]
                  : AppShadows.card,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Stack(
                children: [
                  // ── Active gradient fill ───────────────────────────
                  if (reading.active)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              colorSoft.withValues(alpha: 0.9),
                              AppColors.bgSurface,
                            ],
                            stops: const [0.0, 0.75],
                          ),
                        ),
                      ),
                    ),

                  // ── Top accent stripe (gradient) ───────────────────
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color, color.withValues(alpha: 0.2)],
                          stops: const [0.0, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // ── Content ───────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm + 2,
                      AppSpacing.sm + 8,
                      AppSpacing.sm + 2,
                      AppSpacing.sm + 2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            SensorIconChip(type: reading.type, size: 34),
                            const Spacer(),
                            _ActivityDot(active: reading.active, color: color),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              reading.type.displayName.toUpperCase(),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: reading.active
                                        ? color
                                        : AppColors.textTertiary,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _displayValue,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: reading.active
                                      ? color
                                      : AppColors.textPrimary,
                                  letterSpacing: -0.5,
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _shuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
    );
  }
}

class _ActivityDot extends StatefulWidget {
  const _ActivityDot({required this.active, required this.color});
  final bool active;
  final Color color;

  @override
  State<_ActivityDot> createState() => _ActivityDotState();
}

class _ActivityDotState extends State<_ActivityDot>
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
    if (!widget.active) {
      return Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: AppColors.borderStrong,
          shape: BoxShape.circle,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final v = _ctrl.value;
        return SizedBox(
          width: 20,
          height: 20,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.20 * (1 - v)),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.3 + 0.1 * (1 - v)),
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
