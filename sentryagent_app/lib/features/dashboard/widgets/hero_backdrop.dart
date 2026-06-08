import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/security_state.dart';

/// Animated gradient hero region behind the threat ring.
///
/// Three large blurred blobs drift slowly in the threat-color family.
/// A subtle radial vignette at the edges adds depth.
/// The bottom fades smoothly into the app background.
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
      duration: const Duration(seconds: 14),
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
            // ── Animated color blobs ──────────────────────────────────
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 800),
                child: KeyedSubtree(
                  key: ValueKey(widget.level),
                  child: Stack(
                    children: [
                      _Blob(
                        color: colors[0].withValues(alpha: 0.32),
                        alignment: Alignment(
                          -0.55 + 0.18 * _wave(t, 0.0),
                          -0.45 + 0.12 * _wave(t, 0.3),
                        ),
                        size: 380,
                        blur: 90,
                      ),
                      _Blob(
                        color: colors[2].withValues(alpha: 0.26),
                        alignment: Alignment(
                          0.65 + 0.16 * _wave(t, 0.5),
                          -0.50 + 0.10 * _wave(t, 0.7),
                        ),
                        size: 340,
                        blur: 80,
                      ),
                      _Blob(
                        color: colors[1].withValues(alpha: 0.20),
                        alignment: Alignment(
                          0.05 + 0.22 * _wave(t, 0.2),
                          -0.15 + 0.14 * _wave(t, 0.9),
                        ),
                        size: 400,
                        blur: 100,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Radial vignette (edges slightly darker for depth) ──────
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.0, -0.3),
                    radius: 1.2,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.04),
                    ],
                  ),
                ),
              ),
            ),

            // ── Bottom fade into app background ────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      AppColors.bgBase.withValues(alpha: 0.85),
                      AppColors.bgBase,
                    ],
                    stops: const [0.0, 0.7, 1.0],
                  ),
                ),
              ),
            ),

            // ── Content ───────────────────────────────────────────────
            widget.child,
          ],
        );
      },
    );
  }

  double _wave(double t, double phase) {
    final v = (t + phase) * 2 * math.pi;
    return math.sin(v);
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.color,
    required this.alignment,
    required this.size,
    required this.blur,
  });

  final Color color;
  final Alignment alignment;
  final double size;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
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
