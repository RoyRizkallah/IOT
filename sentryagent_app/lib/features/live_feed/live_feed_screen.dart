import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/sensor_meta.dart';
import '../../core/widgets/soft_card.dart';
import '../../data/models/security_state.dart';

/// Sensor Live Feed — rolling-buffer charts.
///
/// The buffer is held in widget state, populated from the security state
/// stream. We never persist this; the History screen handles long-term data.
class LiveFeedScreen extends ConsumerStatefulWidget {
  const LiveFeedScreen({super.key, this.initialFocus});

  /// Used by the dashboard's tile-tap Hero — scrolls to the relevant chart.
  final SensorType? initialFocus;

  @override
  ConsumerState<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _LiveFeedScreenState extends ConsumerState<LiveFeedScreen> {
  static const int _maxBuffer = 600;
  final List<_Sample> _buffer = [];

  _Window _window = _Window.fiveMinutes;
  ProviderSubscription<AsyncValue<SecurityState>>? _sub;

  @override
  void initState() {
    super.initState();
    // Subscribe imperatively so we keep accumulating samples even when the
    // user scrolls (no rebuild dependency).
    Future.microtask(() {
      _sub = ref.listenManual<AsyncValue<SecurityState>>(
        securityStateProvider,
        (_, next) {
          final s = next.valueOrNull;
          if (s == null) return;
          setState(() {
            _buffer.add(_Sample.fromState(s));
            if (_buffer.length > _maxBuffer) {
              _buffer.removeRange(0, _buffer.length - _maxBuffer);
            }
          });
        },
        fireImmediately: true,
      );
    });
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  List<_Sample> _windowed() {
    if (_buffer.isEmpty) return const [];
    final cutoff =
        DateTime.now().subtract(Duration(seconds: _window.seconds));
    return _buffer.where((s) => s.t.isAfter(cutoff)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final samples = _windowed();
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Live feed',
            style: Theme.of(context).textTheme.titleLarge),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          _WindowPicker(
            current: _window,
            onChange: (w) => setState(() => _window = w),
          ),
          const SizedBox(height: AppSpacing.md),
          _SoundCard(samples: samples, focus: widget.initialFocus),
          const SizedBox(height: AppSpacing.md),
          _TemperatureCard(samples: samples, focus: widget.initialFocus),
          const SizedBox(height: AppSpacing.md),
          _MotionCard(samples: samples, focus: widget.initialFocus),
          const SizedBox(height: AppSpacing.md),
          _DoorCard(samples: samples, focus: widget.initialFocus),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Window picker
// ─────────────────────────────────────────────────────────────────────────

enum _Window {
  oneMinute(60, '1m'),
  fiveMinutes(300, '5m'),
  tenMinutes(600, '10m');

  const _Window(this.seconds, this.label);
  final int seconds;
  final String label;
}

class _WindowPicker extends StatelessWidget {
  const _WindowPicker({required this.current, required this.onChange});
  final _Window current;
  final ValueChanged<_Window> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const _LiveDot(),
            const SizedBox(width: 6),
            Text(
              'Streaming · last ${current.label}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _Window.values.map((w) {
              final selected = w == current;
              return GestureDetector(
                onTap: () => onChange(w),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.accent
                        : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    w.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: selected
                              ? AppColors.textOnAccent
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return SizedBox(
          width: 16,
          height: 16,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color:
                      AppColors.threatSafe.withValues(alpha: 0.25 * (1 - t)),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.threatSafe,
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

// ─────────────────────────────────────────────────────────────────────────
//  Sample model
// ─────────────────────────────────────────────────────────────────────────

class _Sample {
  _Sample({
    required this.t,
    required this.sound,
    required this.temperature,
    required this.motion,
    required this.door,
  });

  final DateTime t;
  final double sound;
  final double temperature;
  final bool motion;
  final bool door;

  static _Sample fromState(SecurityState s) => _Sample(
        t: s.lastUpdate,
        sound: s.reading(SensorType.sound).value,
        temperature: s.reading(SensorType.temperature).value,
        motion: s.reading(SensorType.motion).active,
        door: s.reading(SensorType.door).active,
      );
}

// ─────────────────────────────────────────────────────────────────────────
//  Reusable chart card frame
// ─────────────────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.heroTag,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.colorSoft,
    required this.icon,
    required this.valueLabel,
    required this.chart,
    this.minLabel,
    this.maxLabel,
  });

  final String heroTag;
  final String title;
  final String subtitle;
  final Color color;
  final Color colorSoft;
  final IconData icon;
  final String valueLabel;
  final Widget chart;
  final String? minLabel;
  final String? maxLabel;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: heroTag,
      // The Hero needs Material so InkWells inside don't crash during flight.
      child: Material(
        color: Colors.transparent,
        child: SoftCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colorSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(subtitle,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Text(
                    valueLabel,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(
                          color: color,
                          fontFamily: 'monospace',
                        ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(height: 140, child: chart),
              if (minLabel != null && maxLabel != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('min  ${minLabel!}',
                        style: Theme.of(context).textTheme.labelMedium),
                    Text('max  ${maxLabel!}',
                        style: Theme.of(context).textTheme.labelMedium),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Sound — area chart, the "waveform" feel
// ─────────────────────────────────────────────────────────────────────────

class _SoundCard extends StatelessWidget {
  const _SoundCard({required this.samples, this.focus});
  final List<_Sample> samples;
  final SensorType? focus;

  @override
  Widget build(BuildContext context) {
    final values = samples.map((s) => s.sound).toList();
    final spots = [
      for (var i = 0; i < values.length; i++)
        FlSpot(i.toDouble(), values[i]),
    ];
    final current = values.isEmpty ? 0.0 : values.last;
    final minV = values.isEmpty ? 0.0 : values.reduce(math.min);
    final maxV = values.isEmpty ? 0.0 : values.reduce(math.max);

    return _ChartCard(
      heroTag: 'sensor-${SensorType.sound.name}',
      title: 'Sound',
      subtitle: 'Live amplitude · dB',
      color: AppColors.sensorSound,
      colorSoft: AppColors.sensorSoundSoft,
      icon: SensorMeta.icon(SensorType.sound),
      valueLabel: '${current.toStringAsFixed(0)} dB',
      minLabel: '${minV.toStringAsFixed(0)} dB',
      maxLabel: '${maxV.toStringAsFixed(0)} dB',
      chart: spots.length < 2
          ? const _ChartEmpty()
          : LineChart(
              LineChartData(
                minY: 20,
                maxY: 100,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 20,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: AppColors.divider,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.32,
                    color: AppColors.sensorSound,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.sensorSound.withValues(alpha: 0.30),
                          AppColors.sensorSound.withValues(alpha: 0.04),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              duration: Duration.zero,
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Temperature — smooth line
// ─────────────────────────────────────────────────────────────────────────

class _TemperatureCard extends StatelessWidget {
  const _TemperatureCard({required this.samples, this.focus});
  final List<_Sample> samples;
  final SensorType? focus;

  @override
  Widget build(BuildContext context) {
    final values = samples.map((s) => s.temperature).toList();
    final spots = [
      for (var i = 0; i < values.length; i++)
        FlSpot(i.toDouble(), values[i]),
    ];
    final current = values.isEmpty ? 0.0 : values.last;
    final minV = values.isEmpty ? 0.0 : values.reduce(math.min);
    final maxV = values.isEmpty ? 0.0 : values.reduce(math.max);

    final pad = (maxV - minV).abs() < 0.5 ? 1.0 : (maxV - minV) * 0.3;

    return _ChartCard(
      heroTag: 'sensor-${SensorType.temperature.name}',
      title: 'Temperature',
      subtitle: 'Drift · °C',
      color: AppColors.sensorTemp,
      colorSoft: AppColors.sensorTempSoft,
      icon: SensorMeta.icon(SensorType.temperature),
      valueLabel: '${current.toStringAsFixed(1)} °C',
      minLabel: '${minV.toStringAsFixed(1)} °C',
      maxLabel: '${maxV.toStringAsFixed(1)} °C',
      chart: spots.length < 2
          ? const _ChartEmpty()
          : LineChart(
              LineChartData(
                minY: minV - pad,
                maxY: maxV + pad,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: math.max(0.5, (maxV - minV) / 3),
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: AppColors.divider,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.4,
                    color: AppColors.sensorTemp,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, _) =>
                          spot.x == spots.last.x,
                      getDotPainter: (_, __, ___, ____) =>
                          FlDotCirclePainter(
                        radius: 4,
                        color: AppColors.bgSurface,
                        strokeWidth: 3,
                        strokeColor: AppColors.sensorTemp,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.sensorTemp.withValues(alpha: 0.22),
                          AppColors.sensorTemp.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              duration: Duration.zero,
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Motion — histogram bucketed into ~12 columns over the window
// ─────────────────────────────────────────────────────────────────────────

class _MotionCard extends StatelessWidget {
  const _MotionCard({required this.samples, this.focus});
  final List<_Sample> samples;
  final SensorType? focus;

  static const int _buckets = 12;

  @override
  Widget build(BuildContext context) {
    final counts = List<int>.filled(_buckets, 0);
    if (samples.isNotEmpty) {
      final span = samples.last.t.difference(samples.first.t).inMilliseconds;
      for (final s in samples) {
        if (!s.motion) continue;
        final p =
            span <= 0 ? 0.0 : s.t.difference(samples.first.t).inMilliseconds / span;
        final idx = (p * (_buckets - 1)).clamp(0, _buckets - 1).toInt();
        counts[idx] += 1;
      }
    }
    final total = counts.fold<int>(0, (a, b) => a + b);
    final maxBucket = counts.isEmpty ? 0 : counts.reduce(math.max);

    return _ChartCard(
      heroTag: 'sensor-${SensorType.motion.name}',
      title: 'Motion',
      subtitle: 'Detections in window',
      color: AppColors.sensorMotion,
      colorSoft: AppColors.sensorMotionSoft,
      icon: SensorMeta.icon(SensorType.motion),
      valueLabel: '$total',
      chart: BarChart(
        BarChartData(
          maxY: math.max(1.0, maxBucket.toDouble() + 0.5),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          barTouchData: BarTouchData(enabled: false),
          alignment: BarChartAlignment.spaceAround,
          barGroups: [
            for (var i = 0; i < _buckets; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: counts[i].toDouble(),
                    color: counts[i] == 0
                        ? AppColors.bgMuted
                        : AppColors.sensorMotion,
                    width: 12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Door — a state-strip showing open/closed segments
// ─────────────────────────────────────────────────────────────────────────

class _DoorCard extends StatelessWidget {
  const _DoorCard({required this.samples, this.focus});
  final List<_Sample> samples;
  final SensorType? focus;

  @override
  Widget build(BuildContext context) {
    final openCount = samples.where((s) => s.door).length;
    final lastOpen =
        samples.where((s) => s.door).fold<DateTime?>(null, (a, s) => s.t);

    return _ChartCard(
      heroTag: 'sensor-${SensorType.door.name}',
      title: 'Door',
      subtitle: lastOpen == null
          ? 'No openings in window'
          : 'Last opened — see strip',
      color: AppColors.sensorDoor,
      colorSoft: AppColors.sensorDoorSoft,
      icon: SensorMeta.icon(SensorType.door),
      valueLabel: '$openCount',
      chart: _DoorStrip(samples: samples),
    );
  }
}

class _DoorStrip extends StatelessWidget {
  const _DoorStrip({required this.samples});
  final List<_Sample> samples;

  @override
  Widget build(BuildContext context) {
    if (samples.length < 2) return const _ChartEmpty();
    return CustomPaint(
      painter: _DoorStripPainter(samples: samples),
      size: Size.infinite,
    );
  }
}

class _DoorStripPainter extends CustomPainter {
  _DoorStripPainter({required this.samples});
  final List<_Sample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = const Radius.circular(8);
    final base = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height * 0.35, size.width, size.height * 0.3),
      radius,
    );
    final basePaint = Paint()..color = AppColors.bgMuted;
    canvas.drawRRect(base, basePaint);

    final n = samples.length;
    final stepX = size.width / (n - 1);
    final openPaint = Paint()..color = AppColors.sensorDoor;
    int? runStart;
    for (var i = 0; i < n; i++) {
      if (samples[i].door && runStart == null) runStart = i;
      final endRun = !samples[i].door || i == n - 1;
      if (runStart != null && endRun) {
        final endIdx = samples[i].door ? i : i - 1;
        final left = runStart * stepX;
        final right = endIdx * stepX + stepX * 0.8;
        final rect = Rect.fromLTRB(
          left,
          size.height * 0.35,
          right,
          size.height * 0.65,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, radius),
          openPaint,
        );
        runStart = null;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DoorStripPainter old) =>
      old.samples != samples;
}

// ─────────────────────────────────────────────────────────────────────────
//  Empty placeholder
// ─────────────────────────────────────────────────────────────────────────

class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Collecting data…',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
