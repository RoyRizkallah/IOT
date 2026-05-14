import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../agent_console/agent_console_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../history/history_screen.dart';
import '../reasoning/reasoning_log_screen.dart';
import '../settings/settings_screen.dart';

/// Top-level shell with a custom floating bottom navigation bar.
///
/// We avoid Material's [BottomNavigationBar] / [NavigationBar] because they
/// don't get us the floating-pill look we want. The custom bar is small but
/// it is what makes the app feel premium at first glance.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  static const _tabs = <_TabItem>[
    _TabItem(icon: Icons.shield_rounded, label: 'Home'),
    _TabItem(icon: Icons.psychology_rounded, label: 'Reasoning'),
    _TabItem(icon: Icons.bar_chart_rounded, label: 'History'),
    _TabItem(icon: Icons.chat_bubble_rounded, label: 'Agent'),
    _TabItem(icon: Icons.tune_rounded, label: 'Settings'),
  ];

  static const _screens = <Widget>[
    DashboardScreen(),
    ReasoningLogScreen(),
    HistoryScreen(),
    AgentConsoleScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(mainTabIndexProvider);

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: index, children: _screens),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: _FloatingNavBar(
            items: _tabs,
            current: index,
            onTap: (i) {
              if (i == index) return;
              Haptics.tap();
              ref.read(mainTabIndexProvider.notifier).state = i;
            },
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  const _TabItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.items,
    required this.current,
    required this.onTap,
  });

  final List<_TabItem> items;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: AppShadows.floating,
      ),
      child: Row(
        children: List.generate(items.length, (i) {
          final selected = i == current;
          final item = items[i];
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.all(AppSpacing.xxs),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.accentSoft
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        size: 22,
                        color: selected
                            ? AppColors.accent
                            : AppColors.textTertiary,
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        child: SizedBox(width: selected ? 6 : 0),
                      ),
                      if (selected)
                        Text(
                          item.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
