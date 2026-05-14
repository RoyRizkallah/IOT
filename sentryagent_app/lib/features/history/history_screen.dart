import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/haptics.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/sensor_meta.dart';
import '../../core/widgets/severity_pill.dart';
import '../../data/models/security_state.dart';
import 'widgets/event_detail_sheet.dart';

enum _Window { all, today, week, critical }

extension on _Window {
  String get label => switch (this) {
        _Window.all => 'All',
        _Window.today => 'Today',
        _Window.week => 'Week',
        _Window.critical => 'Critical',
      };

  IconData get icon => switch (this) {
        _Window.all => Icons.all_inclusive_rounded,
        _Window.today => Icons.today_rounded,
        _Window.week => Icons.calendar_view_week_rounded,
        _Window.critical => Icons.priority_high_rounded,
      };

  bool match(SecurityEvent e, DateTime now) {
    switch (this) {
      case _Window.all:
        return true;
      case _Window.today:
        return e.timestamp.year == now.year &&
            e.timestamp.month == now.month &&
            e.timestamp.day == now.day;
      case _Window.week:
        return now.difference(e.timestamp).inDays < 7;
      case _Window.critical:
        return e.severity == ThreatLevel.alert;
    }
  }
}

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  _Window _window = _Window.all;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(eventsProvider);
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        bottom: false,
        child: eventsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (events) {
            final q = _query.trim().toLowerCase();
            final filtered = events
                .where((e) => _window.match(e, now))
                .where((e) => q.isEmpty
                    ? true
                    : e.message.toLowerCase().contains(q) ||
                        e.sensor.displayName.toLowerCase().contains(q))
                .toList()
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

            // Stats for the header card
            final critical = events
                .where((e) => e.severity == ThreatLevel.alert)
                .length;
            final today = events
                .where((e) =>
                    e.timestamp.year == now.year &&
                    e.timestamp.month == now.month &&
                    e.timestamp.day == now.day)
                .length;

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _HeroHeader(
                    total: events.length,
                    today: today,
                    critical: critical,
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyToolbar(
                    child: Container(
                      color: AppColors.bgBase,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.xs,
                        AppSpacing.lg,
                        AppSpacing.sm,
                      ),
                      child: Column(
                        children: [
                          _SearchField(
                            controller: _searchCtrl,
                            onChanged: (v) => setState(() => _query = v),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _Filters(
                            current: _window,
                            counts: {
                              _Window.all: events.length,
                              _Window.today: today,
                              _Window.week: events
                                  .where((e) =>
                                      now.difference(e.timestamp).inDays < 7)
                                  .length,
                              _Window.critical: critical,
                            },
                            onChange: (w) {
                              Haptics.tap();
                              setState(() => _window = w);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (filtered.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Empty(),
                  )
                else
                  ..._buildGroupedSlivers(filtered, now),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 110 + MediaQuery.of(context).padding.bottom,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildGroupedSlivers(List<SecurityEvent> events, DateTime now) {
    final groups = <String, List<SecurityEvent>>{};
    for (final e in events) {
      final key = _bucketKey(e.timestamp, now);
      groups.putIfAbsent(key, () => []).add(e);
    }

    final ordered = ['Today', 'Yesterday', 'This week', 'Earlier']
        .where((k) => groups.containsKey(k))
        .toList();

    final slivers = <Widget>[];
    for (final key in ordered) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Text(
                  key.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 1,
                    color: AppColors.divider,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${groups[key]!.length}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          sliver: SliverList.separated(
            itemCount: groups[key]!.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _EventRow(event: groups[key]![i]),
          ),
        ),
      );
    }
    return slivers;
  }

  String _bucketKey(DateTime t, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tDay = DateTime(t.year, t.month, t.day);
    if (tDay == today) return 'Today';
    if (tDay == yesterday) return 'Yesterday';
    if (now.difference(t).inDays < 7) return 'This week';
    return 'Earlier';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero header
// ─────────────────────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.total,
    required this.today,
    required this.critical,
  });

  final int total;
  final int today;
  final int critical;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'History',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {},
                icon: const Icon(
                  Icons.tune_rounded,
                  color: AppColors.textSecondary,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.bgSurface,
                  shape: const CircleBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'A timeline of every event SentryAgent has logged.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _StatChip(
                icon: Icons.today_rounded,
                label: 'Today',
                value: '$today',
                color: AppColors.accent,
              ),
              const SizedBox(width: AppSpacing.xs),
              _StatChip(
                icon: Icons.priority_high_rounded,
                label: 'Critical',
                value: '$critical',
                color: AppColors.threatAlert,
              ),
              const SizedBox(width: AppSpacing.xs),
              _StatChip(
                icon: Icons.event_note_rounded,
                label: 'Total',
                value: '$total',
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
                          letterSpacing: 1.1,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          height: 1.1,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sticky toolbar (search + filters)
// ─────────────────────────────────────────────────────────────────────────────

class _StickyToolbar extends SliverPersistentHeaderDelegate {
  _StickyToolbar({required this.child});
  final Widget child;

  @override
  double get minExtent => 116;
  @override
  double get maxExtent => 116;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(_StickyToolbar oldDelegate) => true;
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          const Icon(Icons.search_rounded,
              color: AppColors.textTertiary, size: 20),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              cursorColor: AppColors.accent,
              decoration: const InputDecoration(
                hintText: 'Search events',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                onChanged('');
                Haptics.tap();
              },
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: AppColors.bgMuted,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.current,
    required this.counts,
    required this.onChange,
  });

  final _Window current;
  final Map<_Window, int> counts;
  final ValueChanged<_Window> onChange;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _Window.values.map((w) {
          final selected = w == current;
          final count = counts[w] ?? 0;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChange(w),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm + 2,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected ? AppColors.accent : AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: selected
                      ? null
                      : AppShadows.card,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      w.icon,
                      size: 14,
                      color: selected
                          ? AppColors.textOnAccent
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      w.label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: selected
                                ? AppColors.textOnAccent
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white.withValues(alpha: 0.18)
                              : AppColors.bgMuted,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          '$count',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: selected
                                    ? AppColors.textOnAccent
                                    : AppColors.textTertiary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Event row
// ─────────────────────────────────────────────────────────────────────────────

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final SecurityEvent event;

  @override
  Widget build(BuildContext context) {
    final severityColor = switch (event.severity) {
      ThreatLevel.safe => AppColors.threatSafe,
      ThreatLevel.warning => AppColors.threatWarning,
      ThreatLevel.alert => AppColors.threatAlert,
    };

    return PressScale(
      onTap: () {
        Haptics.tap();
        showEventDetailSheet(context, event);
      },
      haptic: HapticLevel.none,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadows.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Left severity stripe
              Container(width: 4, color: severityColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm + 2,
                    vertical: AppSpacing.sm + 2,
                  ),
                  child: Row(
                    children: [
                      SensorIconChip(type: event.sensor, size: 40),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.message,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(height: 1.3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                SeverityPill(
                                    level: event.severity, dense: true),
                                const SizedBox(width: 8),
                                Container(
                                  width: 3,
                                  height: 3,
                                  decoration: const BoxDecoration(
                                    color: AppColors.textTertiary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('HH:mm').format(event.timestamp),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.bgMuted,
                    AppColors.bgSurface,
                  ],
                ),
                shape: BoxShape.circle,
                boxShadow: AppShadows.card,
              ),
              child: const Icon(
                Icons.event_busy_rounded,
                size: 38,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Nothing to show',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 240,
              child: Text(
                'No events match this filter. Try widening your search or '
                'switching back to All.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
