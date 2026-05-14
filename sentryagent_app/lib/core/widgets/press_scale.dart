import 'package:flutter/material.dart';

import '../haptics.dart';

/// A tap target that scales down briefly while pressed and fires a haptic
/// when activated. Used everywhere we want a tactile, "premium" press feel
/// (quick action tiles, arm card, sensor tiles).
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 0.96,
    this.duration = const Duration(milliseconds: 140),
    this.haptic = HapticLevel.tap,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback onTap;
  final double scale;
  final Duration duration;
  final HapticLevel haptic;
  final BorderRadius? borderRadius;

  @override
  State<PressScale> createState() => _PressScaleState();
}

enum HapticLevel { tap, select, confirm, alert, none }

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  void _fireHaptic() {
    switch (widget.haptic) {
      case HapticLevel.tap:
        Haptics.tap();
      case HapticLevel.select:
        Haptics.select();
      case HapticLevel.confirm:
        Haptics.confirm();
      case HapticLevel.alert:
        Haptics.alert();
      case HapticLevel.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final inner = AnimatedScale(
      scale: _pressed ? widget.scale : 1.0,
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      child: widget.child,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: () {
        _fireHaptic();
        widget.onTap();
      },
      child: widget.borderRadius != null
          ? ClipRRect(borderRadius: widget.borderRadius!, child: inner)
          : inner,
    );
  }
}
