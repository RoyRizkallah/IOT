import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/haptics.dart';
import '../../core/notifications.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/transitions.dart';
import '../../core/widgets/connection_pill.dart';
import '../../core/widgets/press_scale.dart';
import '../../data/models/security_state.dart';
import '../live_feed/live_feed_screen.dart';
import 'widgets/activity_strip.dart';
import 'widgets/hero_backdrop.dart';
import 'widgets/recent_events_card.dart';
import 'widgets/sensor_tile.dart';
import 'widgets/smart_insight.dart';
import 'widgets/threat_ring.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  ThreatLevel? _lastLevel;

  @override
  Widget build(BuildContext context) {
    // Haptic + ring pulse when threat level transitions.
    ref.listen(securityStateProvider, (prev, next) {
      final newLvl = next.valueOrNull?.level;
      if (newLvl == null || newLvl == _lastLevel) return;
      if (_lastLevel != null) {
        switch (newLvl) {
          case ThreatLevel.warning:
            Haptics.warning();
            showAlertNotification(
              title: '⚠️ SentryAgent Warning',
              body: 'Threat level elevated — check the dashboard.',
              highPriority: false,
            );
          case ThreatLevel.alert:
            Haptics.alert();
            showAlertNotification(
              title: '🚨 SentryAgent Alert',
              body: 'Security alert detected! Review the dashboard now.',
            );
          case ThreatLevel.safe:
            Haptics.tap();
        }
      }
      _lastLevel = newLvl;
    });

    final stateAsync = ref.watch(securityStateProvider);
    final eventsAsync = ref.watch(eventsProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: stateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text('Connection error: $e'),
          ),
        ),
        data: (state) => _DashboardContent(
          state: state,
          events: eventsAsync.value ?? const [],
        ),
      ),
    );
  }
}

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({required this.state, required this.events});
  final SecurityState state;
  final List<SecurityEvent> events;

  void _openLiveFeed(BuildContext context, [SensorType? focus]) {
    Navigator.of(context).push(
      FadeUpRoute(page: LiveFeedScreen(initialFocus: focus)),
    );
  }

  Future<void> _refresh() async {
    Haptics.tap();
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final ringSize = (media.size.width * 0.55).clamp(170.0, 240.0);

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.accent,
      backgroundColor: AppColors.bgSurface,
      displacement: 40,
      strokeWidth: 2.5,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // ── HERO ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: HeroBackdrop(
              level: state.level,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    children: [
                      _GreetingStrip(armed: state.armed),
                      const SizedBox(height: AppSpacing.sm + 2),
                      _Header(state: state),
                      const SizedBox(height: AppSpacing.md),
                      Center(
                        child: ThreatRing(
                          score: state.threatScore,
                          level: state.level,
                          size: ringSize,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm + 2),
                      Center(
                        child: SmartInsightChip(
                          state: state,
                          events: events,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ActivitySummaryLine(events: events),
                      ActivityStrip(events: events),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── BODY ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(
                    title: 'Sensors',
                    trailing: _LinkRow(
                      label: 'Live feed',
                      onTap: () {
                        Haptics.tap();
                        _openLiveFeed(context);
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _SensorGrid(
                    readings: state.readings,
                    onTap: (t) => _openLiveFeed(context, t),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _BuzzerTile(ref: ref),
                  const SizedBox(height: AppSpacing.lg),
                  const _SectionHeader(title: 'Quick actions'),
                  const SizedBox(height: AppSpacing.md),
                  _ActionsRow(state: state, ref: ref),
                  const SizedBox(height: AppSpacing.lg),
                  RecentEventsCard(
                    events: events,
                    onSeeAll: () {
                      Haptics.tap();
                      ref.read(mainTabIndexProvider.notifier).state = 2;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ArmCard(state: state, ref: ref),
                  SizedBox(height: 110 + media.padding.bottom),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Greeting strip (time-aware)
// ─────────────────────────────────────────────────────────────────────────────

class _GreetingStrip extends ConsumerWidget {
  const _GreetingStrip({required this.armed});
  final bool armed;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'Good morning';
    if (h >= 12 && h < 17) return 'Good afternoon';
    if (h >= 17 && h < 22) return 'Good evening';
    return 'Good night';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
              ),
              const SizedBox(height: 1),
              Text(
                DateFormat('EEEE · MMM d').format(now),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
              ),
            ],
          ),
        ),
        ConnectionPill(
          onTap: () {
            Haptics.tap();
            ref.read(mainTabIndexProvider.notifier).state = 4;
          },
        ),
        const SizedBox(width: AppSpacing.xs + 2),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                armed ? Icons.shield_rounded : Icons.shield_outlined,
                size: 12,
                color: armed ? AppColors.accent : AppColors.textTertiary,
              ),
              const SizedBox(width: 5),
              Text(
                DateFormat('HH:mm').format(now),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.state});
  final SecurityState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: AppShadows.card,
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.shield_rounded,
              color: AppColors.accent, size: 22),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SentryAgent',
                  style: Theme.of(context).textTheme.titleLarge),
              Text(
                state.armed
                    ? 'Watching your home'
                    : 'Standby — system disarmed',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        _ArmedPill(armed: state.armed),
      ],
    );
  }
}

class _ArmedPill extends StatelessWidget {
  const _ArmedPill({required this.armed});
  final bool armed;

  @override
  Widget build(BuildContext context) {
    final fg = armed ? AppColors.accent : AppColors.textTertiary;
    final bg = armed ? AppColors.accentSoft : AppColors.bgMuted;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (armed)
            const _LiveDot(color: AppColors.accent)
          else
            Icon(Icons.shield_outlined, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            armed ? 'ARMED' : 'STANDBY',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.color});
  final Color color;

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
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
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
          width: 14,
          height: 14,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.16 * (1 - t)),
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

// ─────────────────────────────────────────────────────────────────────────────
// Section header + link
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 18,
          margin: const EdgeInsets.only(right: AppSpacing.xs),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.accent, AppColors.accentDeep],
            ),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.accent,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sensor grid
// ─────────────────────────────────────────────────────────────────────────────

class _SensorGrid extends StatelessWidget {
  const _SensorGrid({required this.readings, required this.onTap});
  final List<SensorReading> readings;
  final void Function(SensorType) onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: readings.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisExtent: 142,
      ),
      itemBuilder: (_, i) => SensorTile(
        reading: readings[i],
        onTap: () => onTap(readings[i].type),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick actions
// ─────────────────────────────────────────────────────────────────────────────

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({required this.state, required this.ref});
  final SecurityState state;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.notifications_active_rounded,
            label: 'Trigger siren',
            color: AppColors.threatAlert,
            colorSoft: AppColors.threatAlertSoft,
            haptic: HapticLevel.alert,
            onTap: () {
              ref.read(dataSourceProvider).triggerSiren();
              ref.read(dataSourceProvider).triggerBuzzer();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('🔔 Siren + buzzer triggered'),
                  duration: const Duration(seconds: 3),
                  backgroundColor: AppColors.threatAlert,
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.lg + 70,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _ActionTile(
            icon: Icons.psychology_rounded,
            label: 'Ask agent',
            color: AppColors.sensorSound,
            colorSoft: AppColors.sensorSoundSoft,
            haptic: HapticLevel.select,
            onTap: () =>
                ref.read(mainTabIndexProvider.notifier).state = 3,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _ActionTile(
            icon: Icons.timeline_rounded,
            label: 'View history',
            color: AppColors.sensorMotion,
            colorSoft: AppColors.sensorMotionSoft,
            haptic: HapticLevel.select,
            onTap: () =>
                ref.read(mainTabIndexProvider.notifier).state = 2,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.colorSoft,
    required this.onTap,
    required this.haptic,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color colorSoft;
  final VoidCallback onTap;
  final HapticLevel haptic;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      haptic: haptic,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.md,
          horizontal: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorSoft,
                    colorSoft.withValues(alpha: 0.5),
                  ],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: AppSpacing.xs + 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Arm card
// ─────────────────────────────────────────────────────────────────────────────

class _ArmCard extends StatefulWidget {
  const _ArmCard({required this.state, required this.ref});
  final SecurityState state;
  final WidgetRef ref;

  @override
  State<_ArmCard> createState() => _ArmCardState();
}

class _ArmCardState extends State<_ArmCard> {
  late bool _armed = widget.state.armed;

  @override
  void didUpdateWidget(_ArmCard old) {
    super.didUpdateWidget(old);
    // When the backend confirms the new state, sync local value.
    if (old.state.armed != widget.state.armed) {
      setState(() => _armed = widget.state.armed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final armed = _armed;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: armed
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.accent, AppColors.accentDeep],
              )
            : null,
        color: armed ? null : AppColors.bgSurface,
        boxShadow: armed
            ? [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                  spreadRadius: -4,
                ),
                ...AppShadows.card,
              ]
            : AppShadows.card,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: armed
                  ? Colors.white.withValues(alpha: 0.18)
                  : AppColors.bgMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(
              armed ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: armed ? Colors.white : AppColors.textTertiary,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  armed ? 'System armed' : 'System disarmed',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: armed ? Colors.white : null,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  armed
                      ? 'Agent active — threats will trigger alerts.'
                      : 'Sensors streaming — no alerts will fire.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: armed
                            ? Colors.white.withValues(alpha: 0.75)
                            : null,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          PressScale(
            onTap: () {
              Haptics.confirm();
              setState(() => _armed = !_armed);
              widget.ref.read(dataSourceProvider).setArmed(_armed);
            },
            haptic: HapticLevel.none,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md + 4,
                vertical: AppSpacing.sm + 4,
              ),
              decoration: BoxDecoration(
                color: armed
                    ? Colors.white.withValues(alpha: 0.2)
                    : AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: armed
                    ? Border.all(color: Colors.white.withValues(alpha: 0.3))
                    : null,
              ),
              child: Text(
                armed ? 'Disarm' : 'Arm now',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Buzzer tile
// -----------------------------------------------------------------------------

class _BuzzerTile extends ConsumerStatefulWidget {
  const _BuzzerTile({required this.ref});
  final WidgetRef ref;

  @override
  ConsumerState<_BuzzerTile> createState() => _BuzzerTileState();
}

class _BuzzerTileState extends ConsumerState<_BuzzerTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _firing = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _trigger() async {
    if (_firing) return;
    Haptics.alert();
    setState(() => _firing = true);
    widget.ref.read(dataSourceProvider).triggerBuzzer();
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _firing = false);
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFFF6B00);
    const colorSoft = Color(0xFFFFF3E8);

    return PressScale(
      onTap: _trigger,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: _firing
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF6B00), Color(0xFFFF3D00)],
                )
              : null,
          color: _firing ? null : AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: _firing
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  )
                ]
              : AppShadows.card,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 4,
        ),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _firing
                      ? Colors.white.withValues(alpha: 0.18)
                      : colorSoft,
                  shape: BoxShape.circle,
                  boxShadow: _firing
                      ? [
                          BoxShadow(
                            color: color.withValues(
                                alpha: 0.15 + 0.12 * _pulse.value),
                            blurRadius: 14 + 8 * _pulse.value,
                          )
                        ]
                      : null,
                ),
                child: Icon(
                  Icons.volume_up_rounded,
                  size: 22,
                  color: _firing ? Colors.white : color,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Buzzer',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: _firing ? Colors.white : AppColors.textPrimary,
                        ),
                  ),
                  Text(
                    _firing ? 'Buzzing on Pi...' : 'Tap to trigger · alerts at 35°C',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _firing
                              ? Colors.white.withValues(alpha: 0.8)
                              : AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              _firing ? Icons.graphic_eq_rounded : Icons.chevron_right_rounded,
              color: _firing ? Colors.white : AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
