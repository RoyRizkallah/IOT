import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/security_state.dart';

/// Animated circular threat indicator.
///
///  - Outer glow ring: wide, low-opacity halo that pulses
///  - Track: soft pastel ring (threat color at 12% opacity)
///  - Progress: gradient stroke filling clockwise from 12 o'clock
///  - Dot cap: accent dot at the tip of the progress arc
///  - Center: monospace score + level label
///  - Safe state: slow scan sweep heartbeat
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
  late final AnimationController _glow;

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
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
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
    _glow.dispose();
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
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, animatedProgress, _) {
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: color),
          duration: const Duration(milliseconds: 600),
          builder: (context, animatedColor, _) {
            final c = animatedColor ?? color;
            return AnimatedBuilder(
              animation: Listenable.merge([_scan, _pulse, _glow]),
              builder: (context, _) {
                final p = _pulse.value;
                final g = _glow.value;
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
                        glowPhase: g,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TweenAnimationBuilder<Color?>(
                              tween: ColorTween(end: c),
                              duration: const Duration(milliseconds: 600),
                              builder: (_, col, __) => Text(
                                widget.score.toString(),
                                style: Theme.of(context)
                                    .textTheme
                                    .displayLarge
                                    ?.copyWith(
                                      color: col ?? c,
                                      fontSize: widget.size * 0.35,
                                      height: 1.0,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: c.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                widget.level.label,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: c,
                                      letterSpacing: 3.0,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                    ),
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
    required this.glowPhase,
  });

  final double progress;
  final Color color;
  final double scanPhase;
  final bool showScan;
  final double pulse;
  final double glowPhase;

  static const double _strokeWidth = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // ── Outer glow halo ────────────────────────────────────────────────
    final glowAlpha = 0.06 + 0.04 * glowPhase;
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth * 2.2
      ..color = color.withValues(alpha: glowAlpha);
    canvas.drawCircle(center, radius, glowPaint);

    // ── Track ──────────────────────────────────────────────────────────
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..color = color.withValues(alpha: 0.12);
    canvas.drawCircle(center, radius, track);

    // ── Progress arc ───────────────────────────────────────────────────
    if (progress > 0) {
      final progressPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: 3 * math.pi / 2,
          colors: [
            color.withValues(alpha: 0.45),
            color,
            color,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        progressPaint,
      );

      // ── Dot cap at progress tip ──────────────────────────────────────
      final tipAngle = -math.pi / 2 + 2 * math.pi * progress;
      final tipX = center.dx + radius * math.cos(tipAngle);
      final tipY = center.dy + radius * math.sin(tipAngle);
      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = color;
      canvas.drawCircle(Offset(tipX, tipY), _strokeWidth / 2, dotPaint);

      // Dot inner highlight
      final highlightPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.45);
      canvas.drawCircle(
          Offset(tipX - 1.5, tipY - 1.5), _strokeWidth / 5, highlightPaint);
    }

    // ── Level-change expanding halo ────────────────────────────────────
    if (pulse > 0 && pulse < 1) {
      final haloPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth * 0.8
        ..color = color.withValues(alpha: 0.5 * (1 - pulse));
      canvas.drawCircle(center, radius + 22 * pulse, haloPaint);
    }

    // ── Safe-state scan sweep ──────────────────────────────────────────
    if (showScan) {
      final scanAngle = -math.pi / 2 + (scanPhase * 2 * math.pi);
      final scanPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: scanAngle,
          endAngle: scanAngle + math.pi * 0.6,
          colors: [
            color.withValues(alpha: 0.0),
            color.withValues(alpha: 0.38),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect);
      canvas.drawArc(
        rect,
        scanAngle,
        math.pi * 0.6,
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
      old.pulse != pulse ||
      old.glowPhase != glowPhase;
}
