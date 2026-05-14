import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sources/security_data_source.dart';
import '../providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Small pill that lives in the dashboard header showing the live MQTT
/// connection state. Clicking it pushes the Settings screen so the user can
/// fix a bad host/port without hunting for the tab.
class ConnectionPill extends ConsumerWidget {
  const ConnectionPill({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider).valueOrNull ??
        ConnectionStatus.connecting;

    final spec = _ConnectionSpec.forStatus(status);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: spec.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: spec.foreground.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusDot(color: spec.foreground, pulsing: spec.pulsing),
            const SizedBox(width: 6),
            Text(
              spec.label,
              style: TextStyle(
                color: spec.foreground,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionSpec {
  const _ConnectionSpec({
    required this.label,
    required this.foreground,
    required this.background,
    required this.pulsing,
  });

  final String label;
  final Color foreground;
  final Color background;
  final bool pulsing;

  static _ConnectionSpec forStatus(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return _ConnectionSpec(
          label: 'LIVE',
          foreground: AppColors.threatSafe,
          background: AppColors.threatSafeSoft,
          pulsing: true,
        );
      case ConnectionStatus.connecting:
        return _ConnectionSpec(
          label: 'CONNECTING',
          foreground: AppColors.threatWarning,
          background: AppColors.threatWarningSoft,
          pulsing: true,
        );
      case ConnectionStatus.disconnected:
        return _ConnectionSpec(
          label: 'OFFLINE',
          foreground: AppColors.textSecondary,
          background: AppColors.bgMuted,
          pulsing: false,
        );
      case ConnectionStatus.failed:
        return _ConnectionSpec(
          label: 'NO BROKER',
          foreground: AppColors.threatAlert,
          background: AppColors.threatAlertSoft,
          pulsing: false,
        );
    }
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, required this.pulsing});

  final Color color;
  final bool pulsing;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pulsing) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.55 * t),
                blurRadius: 8 + 6 * t,
                spreadRadius: 1.5 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}
