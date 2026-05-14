import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/broker_config.dart';
import '../../data/models/security_state.dart';
import '../../data/sources/security_data_source.dart';

/// Settings — iOS-style grouped cards with a hero identity card on top.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notif = true;
  bool _autoArmNight = true;
  bool _confirmYellow = true;
  bool _hapticsOn = true;
  double _timeout = 60; // seconds

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(securityStateProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            110 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
            _Header(),
            const SizedBox(height: AppSpacing.md),
            _IdentityCard(state: state),
            const SizedBox(height: AppSpacing.lg),

            const _BrokerSection(),

            _Section(
              label: 'Notifications',
              children: [
                _SwitchTile(
                  icon: Icons.notifications_active_rounded,
                  iconColor: AppColors.accent,
                  label: 'Push notifications',
                  sub: 'Alerts on Red, confirmations on Yellow',
                  value: _notif,
                  onChanged: (v) => setState(() => _notif = v),
                ),
                const _SoftDivider(),
                _SwitchTile(
                  icon: Icons.help_outline_rounded,
                  iconColor: AppColors.threatWarning,
                  label: 'Confirm Yellow events',
                  sub: 'Ask before reacting on score 4–6',
                  value: _confirmYellow,
                  onChanged: (v) => setState(() => _confirmYellow = v),
                ),
                const _SoftDivider(),
                _SwitchTile(
                  icon: Icons.vibration_rounded,
                  iconColor: AppColors.sensorSound,
                  label: 'Haptic feedback',
                  sub: 'Tactile response on actions',
                  value: _hapticsOn,
                  onChanged: (v) => setState(() => _hapticsOn = v),
                ),
              ],
            ),

            _Section(
              label: 'Arming',
              children: [
                _SwitchTile(
                  icon: Icons.bedtime_rounded,
                  iconColor: AppColors.sensorSound,
                  label: 'Auto-arm at night',
                  sub: '23:00 → 06:00',
                  value: _autoArmNight,
                  onChanged: (v) => setState(() => _autoArmNight = v),
                ),
                const _SoftDivider(),
                _SliderTile(
                  icon: Icons.timer_rounded,
                  iconColor: AppColors.sensorMotion,
                  label: 'Confirmation timeout',
                  sub: 'How long the agent waits before escalating',
                  value: _timeout,
                  min: 30,
                  max: 120,
                  divisions: 6,
                  suffix: '${_timeout.round()}s',
                  onChanged: (v) => setState(() => _timeout = v),
                ),
              ],
            ),

            _Section(
              label: 'Privacy',
              children: [
                _PrivacyTile(),
              ],
            ),

            _Section(
              label: 'About',
              children: [
                _RowTile(
                  icon: Icons.info_outline_rounded,
                  iconColor: AppColors.textSecondary,
                  label: 'Version',
                  trailing: const _ValueText('0.1.0'),
                ),
                const _SoftDivider(),
                _RowTile(
                  icon: Icons.tag_rounded,
                  iconColor: AppColors.textSecondary,
                  label: 'Build',
                  trailing: const _ValueText('debug · 2026.05'),
                ),
                const _SoftDivider(),
                _RowTile(
                  icon: Icons.book_outlined,
                  iconColor: AppColors.textSecondary,
                  label: 'Documentation',
                  showChevron: true,
                  onTap: () => _showComingSoon(context),
                ),
                const _SoftDivider(),
                _RowTile(
                  icon: Icons.code_rounded,
                  iconColor: AppColors.textSecondary,
                  label: 'Open source licenses',
                  showChevron: true,
                  onTap: () {
                    showLicensePage(
                      context: context,
                      applicationName: 'SentryAgent',
                      applicationVersion: '0.1.0',
                    );
                  },
                ),
              ],
            ),

            _Section(
              label: 'Danger zone',
              children: [
                _RowTile(
                  icon: Icons.refresh_rounded,
                  iconColor: AppColors.threatWarning,
                  label: 'Reset all settings',
                  sub: 'Restore defaults; preserves history',
                  showChevron: true,
                  onTap: () => _confirmReset(context),
                ),
                const _SoftDivider(),
                _RowTile(
                  icon: Icons.delete_outline_rounded,
                  iconColor: AppColors.threatAlert,
                  label: 'Clear local history',
                  sub: 'Permanently delete all logged events',
                  showChevron: true,
                  destructive: true,
                  onTap: () => _confirmClearHistory(context),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),
            _Footer(),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    Haptics.tap();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Available once the Raspberry Pi is connected'),
      ));
  }

  Future<void> _confirmReset(BuildContext context) async {
    Haptics.tap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset all settings?'),
        content: const Text(
          'Restores notifications, arming and AI defaults. '
          'Your event history will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() {
        _notif = true;
        _autoArmNight = true;
        _confirmYellow = true;
        _hapticsOn = true;
        _timeout = 60;
      });
      Haptics.confirm();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Settings reset')));
      }
    }
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    Haptics.tap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear local history?'),
        content: const Text(
          'This permanently removes every logged event and decision. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Clear',
              style: TextStyle(color: AppColors.threatAlert),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      Haptics.alert();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('History cleared (mock)'),
        ));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Broker (live MQTT connection)
// ─────────────────────────────────────────────────────────────────────────────

class _BrokerSection extends ConsumerWidget {
  const _BrokerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(brokerConfigProvider);
    final status = ref.watch(connectionStatusProvider).valueOrNull ??
        ConnectionStatus.connecting;
    final spec = _StatusSpec.forStatus(status);

    return _Section(
      label: 'Connection',
      children: [
        _RowTile(
          icon: Icons.bolt_rounded,
          iconColor: spec.color,
          label: 'Status',
          sub: spec.subtitle,
          trailing: _PillBadge(
            text: spec.label,
            color: spec.color,
            bg: spec.color.withValues(alpha: 0.12),
          ),
        ),
        const _SoftDivider(),
        _RowTile(
          icon: Icons.dns_rounded,
          iconColor: AppColors.sensorMotion,
          label: 'MQTT broker',
          sub: '${cfg.host}:${cfg.port}',
          showChevron: true,
          onTap: () => _editBroker(context, ref, cfg),
        ),
        const _SoftDivider(),
        _RowTile(
          icon: Icons.refresh_rounded,
          iconColor: AppColors.accent,
          label: 'Reconnect',
          sub: status.isLive
              ? 'Drop the connection and rejoin'
              : 'Try connecting again',
          showChevron: true,
          onTap: () async {
            Haptics.tap();
            try {
              await ref.read(mqttDataSourceProvider).reconfigure(cfg);
            } catch (_) {
              // Provider might not be ready yet on a fresh boot; ignore.
            }
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(
                  content: Text('Reconnecting to broker...'),
                ));
            }
          },
        ),
        const _SoftDivider(),
        _RowTile(
          icon: Icons.memory_rounded,
          iconColor: AppColors.sensorTemp,
          label: 'Raspberry Pi sensors',
          sub: 'Mock publisher today; physical Pi pending',
        ),
      ],
    );
  }

  Future<void> _editBroker(
    BuildContext context,
    WidgetRef ref,
    BrokerConfig current,
  ) async {
    Haptics.tap();
    final updated = await showModalBottomSheet<BrokerConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BrokerEditSheet(initial: current),
    );
    if (updated != null && updated != current) {
      await ref.read(brokerConfigProvider.notifier).update(updated);
      Haptics.confirm();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('Broker set to $updated'),
          ));
      }
    }
  }
}

class _StatusSpec {
  const _StatusSpec({
    required this.label,
    required this.subtitle,
    required this.color,
  });
  final String label;
  final String subtitle;
  final Color color;

  static _StatusSpec forStatus(ConnectionStatus s) {
    switch (s) {
      case ConnectionStatus.connected:
        return const _StatusSpec(
          label: 'LIVE',
          subtitle: 'Connected to the broker',
          color: AppColors.threatSafe,
        );
      case ConnectionStatus.connecting:
        return const _StatusSpec(
          label: 'CONNECTING',
          subtitle: 'Reaching the broker',
          color: AppColors.threatWarning,
        );
      case ConnectionStatus.disconnected:
        return const _StatusSpec(
          label: 'OFFLINE',
          subtitle: 'No live data — pull to retry',
          color: AppColors.textSecondary,
        );
      case ConnectionStatus.failed:
        return const _StatusSpec(
          label: 'NO BROKER',
          subtitle: 'Check the host and port below',
          color: AppColors.threatAlert,
        );
    }
  }
}

class _BrokerEditSheet extends StatefulWidget {
  const _BrokerEditSheet({required this.initial});
  final BrokerConfig initial;

  @override
  State<_BrokerEditSheet> createState() => _BrokerEditSheetState();
}

class _BrokerEditSheetState extends State<_BrokerEditSheet> {
  late final _hostCtrl = TextEditingController(text: widget.initial.host);
  late final _portCtrl =
      TextEditingController(text: widget.initial.port.toString());
  String? _hostErr;
  String? _portErr;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final host = _hostCtrl.text.trim();
    final portStr = _portCtrl.text.trim();
    String? hostErr;
    String? portErr;
    if (host.isEmpty) hostErr = 'Required';
    final port = int.tryParse(portStr);
    if (port == null || port <= 0 || port > 65535) {
      portErr = '1 – 65535';
    }
    setState(() {
      _hostErr = hostErr;
      _portErr = portErr;
    });
    if (hostErr != null || portErr != null) {
      Haptics.alert();
      return;
    }
    Navigator.of(context).pop(BrokerConfig(host: host, port: port!));
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.bgMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'MQTT broker',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Where the SentryAgent backend is publishing.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _hostCtrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Host',
                hintText: '10.0.2.2 (emulator) or 192.168.x.x (LAN)',
                errorText: _hostErr,
                prefixIcon: const Icon(Icons.dns_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _portCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Port',
                hintText: '1883',
                errorText: _portErr,
                prefixIcon: const Icon(Icons.tag_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm + 4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm + 4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Settings',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
        ),
        const Spacer(),
        IconButton(
          onPressed: () {},
          icon: const Icon(
            Icons.search_rounded,
            color: AppColors.textSecondary,
          ),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.bgSurface,
            shape: const CircleBorder(),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Identity card (hero at top)
// ─────────────────────────────────────────────────────────────────────────────

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.state});
  final SecurityState? state;

  @override
  Widget build(BuildContext context) {
    final armed = state?.armed ?? false;
    final levelLabel = state?.level.label.toLowerCase() ?? '...';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF0F4FF),
            Color(0xFFEFE9FF),
            Color(0xFFE0F7FB),
          ],
        ),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: AppColors.heroGradientSafe,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: AppShadows.card,
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SentryAgent',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                    ),
                    Text(
                      'Home security · personal AI',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _IdentityStat(
                  icon: armed
                      ? Icons.lock_rounded
                      : Icons.lock_open_rounded,
                  label: armed ? 'Armed' : 'Standby',
                  value: armed ? levelLabel : 'disarmed',
                  color: armed ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _IdentityStat(
                  icon: Icons.sensors_rounded,
                  label: 'Sensors',
                  value: '${state?.readings.length ?? 0} online',
                  color: AppColors.threatSafe,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IdentityStat extends StatelessWidget {
  const _IdentityStat({
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
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgSurface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                        letterSpacing: 1.2,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
// Sections
// ─────────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              0,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: AppShadows.card,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings rows
// ─────────────────────────────────────────────────────────────────────────────

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.sub,
    this.trailing,
    this.showChevron = false,
    this.destructive = false,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String? sub;
  final Widget? trailing;
  final bool showChevron;
  final bool destructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      child: Row(
        children: [
          _IconChip(icon: icon, color: iconColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: destructive
                            ? AppColors.threatAlert
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
          if (showChevron) ...[
            if (trailing == null) const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.accentSoft,
        highlightColor: AppColors.accentSoft.withValues(alpha: 0.5),
        child: content,
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          _IconChip(icon: icon, color: iconColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(sub, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: (v) {
              Haptics.tap();
              onChanged(v);
            },
            activeThumbColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.sub,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String sub;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _IconChip(icon: icon, color: iconColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(sub, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  suffix,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                      ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.bgMuted,
              thumbColor: AppColors.accent,
              overlayColor: AppColors.accent.withValues(alpha: 0.12),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: (v) {
                Haptics.tap();
                onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
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
                  color: AppColors.threatSafeSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  size: 18,
                  color: AppColors.threatSafe,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'What leaves your home',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Sensor data stays on your Pi. The agent only sends a compact, '
            'anonymised summary to the LLM when reasoning about a Yellow-zone '
            'event. No video, no audio, no personally-identifying details.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.55,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const _PrivacyBadge(
                icon: Icons.videocam_off_rounded,
                text: 'No video',
              ),
              const SizedBox(width: 6),
              const _PrivacyBadge(
                icon: Icons.mic_off_rounded,
                text: 'No audio',
              ),
              const SizedBox(width: 6),
              const _PrivacyBadge(
                icon: Icons.fingerprint_rounded,
                text: 'Anonymised',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrivacyBadge extends StatelessWidget {
  const _PrivacyBadge({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.threatSafeSoft,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppColors.threatSafe),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.threatSafe,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Building blocks
// ─────────────────────────────────────────────────────────────────────────────

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

class _SoftDivider extends StatelessWidget {
  const _SoftDivider();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 64),
      child: Divider(
        height: 1,
        thickness: 1,
        color: AppColors.divider,
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({
    required this.text,
    required this.color,
    required this.bg,
  });
  final String text;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _ValueText extends StatelessWidget {
  const _ValueText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textTertiary,
            fontFamily: 'monospace',
          ),
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              shape: BoxShape.circle,
              boxShadow: AppShadows.card,
            ),
            child: const Icon(
              Icons.shield_rounded,
              size: 18,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'SentryAgent · Made for the Pi',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
