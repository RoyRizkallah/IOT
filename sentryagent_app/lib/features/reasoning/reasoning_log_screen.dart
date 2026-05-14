import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/haptics.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/transitions.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/severity_pill.dart';
import '../../core/widgets/soft_card.dart';
import '../../data/models/security_state.dart';
import 'decision_detail_screen.dart';

class ReasoningLogScreen extends ConsumerWidget {
  const ReasoningLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decisions = ref.watch(decisionsProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        bottom: false,
        child: decisions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (list) => CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _Header(count: list.length)),
              if (list.isEmpty)
                const SliverFillRemaining(
                  child: _EmptyState(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    96,
                  ),
                  sliver: SliverList.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) => _DecisionCard(decision: list[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.psychology_rounded,
                color: AppColors.accent,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Reasoning log',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            count == 0
                ? 'The agent\'s decisions will appear here.'
                : '$count decision${count == 1 ? '' : 's'} — every reaction explained.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({required this.decision});
  final AgentDecision decision;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () {
        Haptics.select();
        Navigator.of(context).push(
          FadeUpRoute(
            page: DecisionDetailScreen(decision: decision),
          ),
        );
      },
      haptic: HapticLevel.none,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SoftCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Hero(
                  tag: 'decision-pill-${decision.id}',
                  child: Material(
                    type: MaterialType.transparency,
                    child: SeverityPill(level: decision.severity),
                  ),
                ),
                const Spacer(),
                Text(
                  relativeTime(decision.timestamp),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              decision.summary,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              decision.context,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: decision.toolsCalled
                  .map((t) => _ToolChip(name: t.name))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs + 2,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        name,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontFamily: 'monospace',
            ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            size: 32,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No decisions yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'The agent reasons here when sensors fire.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
