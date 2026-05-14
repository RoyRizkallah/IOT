import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/security_state.dart';

/// Animated circular threat indicator.
///
///  - Track: a soft pastel ring (matches threat color, 14% opacity)
///  - Progress: a gradient stroke that fills clockwise from 12 o'clock
///  - Center: monospace numeric (the score) and the level label
///  - When SECURE, a slow "scan-line" sweep gives the ring a heartbeat
class ThreatRing extends StatefulWidget {
  const ThreatRing({
    super.key,
    required this.score,
    required this.level,
    this.size = 260,
  });

  final int score;
  final ThreatLevel level;
  final double size;

  @override
  State<ThreatRing> createState() => _ThreatRingState();
}

class _ThreatRingState extends State<ThreatRing>
    with TickerProviderStateMixin {
  late final AnimationController _scan;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void didUpdateWidget(ThreatRing old) {
    super.didUpdateWidget(old);
    if (old.level != widget.level) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.level) {
      ThreatLevel.safe => AppColors.threatSafe,
      ThreatLevel.warning => AppColors.threatWarning,
      ThreatLevel.alert => AppColors.threatAlert,
    };

    final progress = (widget.score / 10).clamp(0.0, 1.0);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, animatedProgress, _) {
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: color),
          duration: const Duration(milliseconds: 500),
          builder: (context, animatedColor, _) {
            final c = animatedColor ?? color;
            return AnimatedBuilder(
              animation: Listenable.merge([_scan, _pulse]),
              builder: (context, _) {
                final p = _pulse.value;
                final pulseScale = p == 0 ? 1.0 : 1.0 + (1 - (p - 0.5).abs() * 2) * 0.04;
                return Transform.scale(
                  scale: pulseScale,
                  child: SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: CustomPaint(
                    painter: _RingPainter(
                      progress: animatedProgress,
                      color: c,
                      scanPhase: _scan.value,
                      showScan: widget.level == ThreatLevel.safe,
                      pulse: p,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.score.toString(),
                            style: Theme.of(context)
                                .textTheme
                                .displayLarge
                                ?.copyWith(
                                  color: c,
                                  fontSize: widget.size * 0.34,
                                  height: 1.0,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.level.label,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: c,
                                  letterSpacing: 4,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.scanPhase,
    required this.showScan,
    required this.pulse,
  });

  final double progress;
  final Color color;
  final double scanPhase;
  final bool showScan;
  final double pulse; // 0..1, runs once on level change

  static const double _strokeWidth = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..color = color.withValues(alpha: 0.14);
    canvas.drawCircle(center, radius, track);

    if (progress > 0) {
      final progressPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: 3 * math.pi / 2,
          colors: [
            color.withValues(alpha: 0.55),
            color,
            color,
          ],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(rect);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        progressPaint,
      );
    }

    if (pulse > 0 && pulse < 1) {
      // Outer halo expanding ring on level change.
      final haloPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth * 0.7
        ..color = color.withValues(alpha: 0.4 * (1 - pulse));
      canvas.drawCircle(center, radius + 16 * pulse, haloPaint);
    }

    if (showScan) {
      // Soft rotating glow — subtle "alive" effect when SECURE.
      final scanAngle = -math.pi / 2 + (scanPhase * 2 * math.pi);
      final scanPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: scanAngle,
          endAngle: scanAngle + math.pi / 2,
          colors: [
            color.withValues(alpha: 0.0),
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect);
      canvas.drawArc(
        rect,
        scanAngle,
        math.pi / 2,
        false,
        scanPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.scanPhase != scanPhase ||
      old.showScan != showScan ||
      old.pulse != pulse;
}
