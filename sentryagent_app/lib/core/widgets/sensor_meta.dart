import 'package:flutter/material.dart';

import '../../data/models/security_state.dart';
import '../theme/app_colors.dart';

/// Per-sensor visual identity helpers, used by sensor tiles, history rows,
/// chat message bubbles — anywhere a sensor needs an icon + color.
class SensorMeta {
  SensorMeta._();

  static IconData icon(SensorType t) => switch (t) {
        SensorType.motion => Icons.directions_walk_rounded,
        SensorType.sound => Icons.graphic_eq_rounded,
        SensorType.temperature => Icons.thermostat_rounded,
        SensorType.humidity => Icons.water_drop_rounded,
      };

  static Color color(SensorType t) => switch (t) {
        SensorType.motion => AppColors.sensorMotion,
        SensorType.sound => AppColors.sensorSound,
        SensorType.temperature => AppColors.sensorTemp,
        SensorType.humidity => AppColors.sensorHumidity,
      };

  static Color colorSoft(SensorType t) => switch (t) {
        SensorType.motion => AppColors.sensorMotionSoft,
        SensorType.sound => AppColors.sensorSoundSoft,
        SensorType.temperature => AppColors.sensorTempSoft,
        SensorType.humidity => AppColors.sensorHumiditySoft,
      };
}

/// A circular icon chip with the sensor's pastel background + saturated icon.
class SensorIconChip extends StatelessWidget {
  const SensorIconChip({super.key, required this.type, this.size = 40});

  final SensorType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: SensorMeta.colorSoft(type),
        shape: BoxShape.circle,
      ),
      child: Icon(
        SensorMeta.icon(type),
        color: SensorMeta.color(type),
        size: size * 0.5,
      ),
    );
  }
}
