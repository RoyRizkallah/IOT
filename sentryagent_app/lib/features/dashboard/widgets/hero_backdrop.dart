import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/security_state.dart';

/// Soft animated gradient that sits behind the threat ring.
///
/// Two large blurred blobs in the threat-color family. They drift slowly,
/// giving the hero region a sense of being "alive" without the user noticing.
/// The colour family swaps based on threat level, with a smooth crossfade.
class HeroBackdrop extends StatefulWidget {
  const HeroBackdrop({super.key, required this.level, required this.child});

  final ThreatLevel level;
  final Widget child;

  @override
  State<HeroBackdrop> createState() => _HeroBackdropState();
}

class _HeroBackdropState extends State<HeroBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  List<Color> _colors() => switch (widget.level) {
        ThreatLevel.safe => AppColors.heroGradientSafe,
        ThreatLevel.warning => AppColors.heroGradientWarning,
        ThreatLevel.alert => AppColors.heroGradientAlert,
      };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _drift,
      builder: (_, __) {
        final t = _drift.value;
        final colors = _colors();
        return Stack(
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 700),
                child: KeyedSubtree(
                  key: ValueKey(widget.level),
                  child: Stack(
                    children: [
                      _Blob(
                        color: colors[0].withValues(alpha: 0.22),
                        alignment: Alignment(
                          -0.6 + 0.15 * _wave(t, 0),
                          -0.4 + 0.1 * _wave(t, 0.3),
                        ),
                        size: 360,
                      ),
                      _Blob(
                        color: colors[2].withValues(alpha: 0.18),
                        alignment: Alignment(
                          0.6 + 0.15 * _wave(t, 0.5),
                          -0.55 + 0.1 * _wave(t, 0.7),
                        ),
                        size: 320,
                      ),
                      _Blob(
                        color: colors[1].withValues(alpha: 0.14),
                        alignment: Alignment(
                          0.0 + 0.2 * _wave(t, 0.2),
                          -0.2 + 0.12 * _wave(t, 0.9),
                        ),
                        size: 380,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            widget.child,
          ],
        );
      },
    );
  }

  double _wave(double t, double phase) {
    final v = (t + phase) * 2 * 3.1415926;
    return (v.remainder(2 * 3.1415926).abs() / 3.1415926) - 1;
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.color,
    required this.alignment,
    required this.size,
  });

  final Color color;
  final Alignment alignment;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
