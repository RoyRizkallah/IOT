import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../agent_console/agent_console_screen.dart';
import '../camera/camera_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../history/history_screen.dart';
import '../reasoning/reasoning_log_screen.dart';
import '../settings/settings_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  static const _tabs = <_TabItem>[
    _TabItem(icon: Icons.shield_rounded, label: 'Home'),
    _TabItem(icon: Icons.videocam_rounded, label: 'Camera'),
    _TabItem(icon: Icons.psychology_rounded, label: 'AI'),
    _TabItem(icon: Icons.bar_chart_rounded, label: 'History'),
    _TabItem(icon: Icons.chat_bubble_rounded, label: 'Agent'),
    _TabItem(icon: Icons.tune_rounded, label: 'Settings'),
  ];

  static const _screens = <Widget>[
    DashboardScreen(),
    CameraScreen(),
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
      height: 70,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: AppShadows.floating,
      ),
      padding: const EdgeInsets.all(5),
      child: Row(
        children: List.generate(items.length, (i) {
          final selected = i == current;
          final item = items[i];
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.accent, AppColors.accentDeep],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.30),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      width: selected ? 26 : 22,
                      height: selected ? 26 : 22,
                      child: Icon(
                        item.icon,
                        size: selected ? 24 : 21,
                        color: selected
                            ? Colors.white
                            : AppColors.textTertiary,
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: SizedBox(
                        height: selected ? 3 : 0,
                      ),
                    ),
                    if (selected)
                      Text(
                        item.label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                          height: 1,
                          fontFamily: 'PlusJakartaSans',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
