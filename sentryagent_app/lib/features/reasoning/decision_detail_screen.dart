import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/severity_pill.dart';
import '../../data/models/security_state.dart';

/// Full-screen detail for a single agent decision. Renders the decision as a
/// vertical timeline so the reader can follow the reasoning step by step,
/// not as a stack of disconnected cards.
///
///   ┌──────────────────────────────────────────────┐
///   │  HERO  (severity-tinted gradient)            │
///   │   • severity pill, time, summary headline    │
///   ├──────────────────────────────────────────────┤
///   │  TIMELINE                                    │
///   │   ◯─ Trigger (context)                       │
///   │   │                                          │
///   │   ◯─ Reasoning (paragraph)                   │
///   │   │                                          │
///   │   ◯─ Tools called (each call = sub-card)     │
///   │   │                                          │
///   │   ◯─ Final action                            │
///   └──────────────────────────────────────────────┘
class DecisionDetailScreen extends StatelessWidget {
  const DecisionDetailScreen({super.key, required this.decision});
  final AgentDecision decision;

  @override
  Widget build(BuildContext context) {
    final color = switch (decision.severity) {
      ThreatLevel.safe => AppColors.threatSafe,
      ThreatLevel.warning => AppColors.threatWarning,
      ThreatLevel.alert => AppColors.threatAlert,
    };
    final colorSoft = switch (decision.severity) {
      ThreatLevel.safe => AppColors.threatSafeSoft,
      ThreatLevel.warning => AppColors.threatWarningSoft,
      ThreatLevel.alert => AppColors.threatAlertSoft,
    };

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.bgBase,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            pinned: true,
            leading: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.textPrimary,
              ),
            ),
            title: Text(
              'Decision',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            actions: [
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                    text: 'Decision ${decision.id}\n'
                        '${absoluteFull(decision.timestamp)}\n\n'
                        '${decision.summary}\n\n'
                        'Context: ${decision.context}\n\n'
                        'Reasoning: ${decision.reasoning}\n\n'
                        'Final action: ${decision.finalAction} — '
                        '${decision.finalActionReason}',
                  ));
                  Haptics.tap();
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(const SnackBar(
                      content: Text('Decision copied'),
                    ));
                },
                icon: const Icon(
                  Icons.ios_share_rounded,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: _Hero(
              decision: decision,
              color: color,
              colorSoft: colorSoft,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            sliver: SliverList.list(
              children: [
                _TimelineItem(
                  icon: Icons.bolt_rounded,
                  iconColor: AppColors.threatWarning,
                  title: 'Trigger',
                  body: decision.context,
                  isFirst: true,
                ),
                _TimelineItem(
                  icon: Icons.psychology_rounded,
                  iconColor: AppColors.accent,
                  title: 'Reasoning',
                  body: decision.reasoning,
                ),
                _TimelineToolGroup(
                  tools: decision.toolsCalled,
                ),
                _TimelineItem(
                  icon: Icons.task_alt_rounded,
                  iconColor: color,
                  title: 'Final action · ${decision.finalAction}',
                  body: decision.finalActionReason.isNotEmpty
                      ? decision.finalActionReason
                      : decision.finalAction,
                  emphasize: true,
                  isLast: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero
// ─────────────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({
    required this.decision,
    required this.color,
    required this.colorSoft,
  });

  final AgentDecision decision;
  final Color color;
  final Color colorSoft;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        0,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorSoft, AppColors.bgSurface],
        ),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
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
              Icon(
                Icons.schedule_rounded,
                size: 14,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                absoluteFull(decision.timestamp),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            decision.summary,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  letterSpacing: -0.3,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.card,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Decided by SentryAgent',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              Text(
                relativeTime(decision.timestamp),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timeline
// ─────────────────────────────────────────────────────────────────────────────

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    this.isFirst = false,
    this.isLast = false,
    this.emphasize = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final bool isFirst;
  final bool isLast;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Rail(
            icon: icon,
            iconColor: iconColor,
            isFirst: isFirst,
            isLast: isLast,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isLast ? 0 : AppSpacing.md,
              ),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: emphasize
                      ? iconColor.withValues(alpha: 0.06)
                      : AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: AppShadows.card,
                  border: emphasize
                      ? Border.all(
                          color: iconColor.withValues(alpha: 0.2))
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: iconColor,
                            letterSpacing: 1.3,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      body,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.textPrimary,
                            height: 1.55,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineToolGroup extends StatelessWidget {
  const _TimelineToolGroup({required this.tools});
  final List<AgentToolCall> tools;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Rail(
            icon: Icons.build_rounded,
            iconColor: AppColors.sensorSound,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 4,
                      bottom: 6,
                      top: 4,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'TOOLS CALLED',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: AppColors.sensorSound,
                                letterSpacing: 1.3,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.sensorSoundSoft,
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            '${tools.length}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: AppColors.sensorSound,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (var i = 0; i < tools.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i == tools.length - 1 ? 0 : 8,
                      ),
                      child: _ToolCard(call: tools[i]),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.icon,
    required this.iconColor,
    this.isFirst = false,
    this.isLast = false,
  });

  final IconData icon;
  final Color iconColor;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      child: Column(
        children: [
          // Top connector
          Container(
            width: 2,
            height: isFirst ? 0 : 6,
            color: AppColors.divider,
          ),
          // Node
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              shape: BoxShape.circle,
              border: Border.all(
                color: iconColor.withValues(alpha: 0.25),
                width: 2,
              ),
              boxShadow: AppShadows.card,
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          // Bottom connector
          Expanded(
            child: Container(
              width: 2,
              color: isLast ? Colors.transparent : AppColors.divider,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tool sub-card
// ─────────────────────────────────────────────────────────────────────────────

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.call});
  final AgentToolCall call;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.sensorSoundSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  call.name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: AppColors.sensorSound,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.check_circle_rounded,
                size: 14,
                color: AppColors.threatSafe,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _KV(label: 'args', value: call.argsSummary),
          const SizedBox(height: 4),
          _KV(label: 'result', value: call.resultSummary),
        ],
      ),
    );
  }
}

class _KV extends StatelessWidget {
  const _KV({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
          ),
        ),
      ],
    );
  }
}
