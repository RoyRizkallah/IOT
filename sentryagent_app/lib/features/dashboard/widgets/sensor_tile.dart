import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/press_scale.dart';
import '../../../core/widgets/sensor_meta.dart';
import '../../../data/models/security_state.dart';

/// A single sensor tile in the 2×2 grid below the threat ring.
///
///  - White card with layered soft shadow
///  - Top accent stripe in the sensor's signature color
///  - Pulses gently when the sensor is active
///  - Tap → live feed (Hero-flies into the matching chart card)
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
      case SensorType.door:
        return reading.active ? 'OPEN' : 'CLOSED';
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
              boxShadow: AppShadows.card,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(height: 4, color: color),
                  ),
                  if (reading.active)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [colorSoft, AppColors.bgSurface],
                            stops: const [0, 0.85],
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm + 2,
                      AppSpacing.sm + 6,
                      AppSpacing.sm + 2,
                      AppSpacing.sm + 2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            SensorIconChip(type: reading.type, size: 32),
                            const Spacer(),
                            _ActivityDot(active: reading.active, color: color),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              reading.type.displayName.toUpperCase(),
                              style:
                                  Theme.of(context).textTheme.labelSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _displayValue,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.3,
                                height: 1.1,
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

  /// During the Hero flight, blank out internal text and just show the
  /// shape morphing — prevents text-baseline jitter when source/target have
  /// different layouts.
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
          width: 18,
          height: 18,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.18 * (1 - v)),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 8,
                height: 8,
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
