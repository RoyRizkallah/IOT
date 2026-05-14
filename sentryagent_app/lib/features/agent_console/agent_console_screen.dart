import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/haptics.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/security_state.dart';
import '../../data/sources/security_data_source.dart';

/// Agent Console — natural-language chat with SentryAgent.
class AgentConsoleScreen extends ConsumerStatefulWidget {
  const AgentConsoleScreen({super.key});

  @override
  ConsumerState<AgentConsoleScreen> createState() => _AgentConsoleScreenState();
}

class _AgentConsoleScreenState extends ConsumerState<AgentConsoleScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _sending = false;
  bool _hasInput = false;
  bool _isFocused = false;

  static const _suggestions = <_Suggestion>[
    _Suggestion(
      icon: Icons.nightlight_round,
      text: 'What happened last night?',
    ),
    _Suggestion(
      icon: Icons.sensor_door_outlined,
      text: 'Is the back door closed?',
    ),
    _Suggestion(
      icon: Icons.today_rounded,
      text: 'Show me today\'s alerts',
    ),
    _Suggestion(
      icon: Icons.help_outline_rounded,
      text: 'Why did you trigger the siren?',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final v = _ctrl.text.trim().isNotEmpty;
      if (v != _hasInput) setState(() => _hasInput = v);
    });
    _focus.addListener(() {
      if (_focus.hasFocus != _isFocused) {
        setState(() => _isFocused = _focus.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send([String? overrideText]) async {
    final text = (overrideText ?? _ctrl.text).trim();
    if (text.isEmpty || _sending) return;
    Haptics.select();
    setState(() => _sending = true);
    _ctrl.clear();
    _scrollToBottom();
    await ref.read(dataSourceProvider).sendChat(text);
    // Keep `_sending = true`; the chatProvider listener flips it to false
    // once the agent's reply arrives. As a safety net, time out after 45s.
    Future<void>.delayed(const Duration(seconds: 45), () {
      if (mounted && _sending) setState(() => _sending = false);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatAsync = ref.watch(chatProvider);
    final connStatus = ref.watch(connectionStatusProvider).valueOrNull ??
        ConnectionStatus.connecting;

    ref.listen<AsyncValue<List<ChatMessage>>>(chatProvider, (prev, next) {
      _scrollToBottom();
      final list = next.valueOrNull;
      if (list == null || list.isEmpty) return;
      // Drop the typing indicator once the agent has replied.
      if (_sending && list.last.role == ChatRole.agent) {
        setState(() => _sending = false);
      }
    });

    final hasUserMessage = chatAsync.value
            ?.any((m) => m.role == ChatRole.user) ??
        false;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(connStatus: connStatus),
            Expanded(
              child: chatAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (messages) => _buildMessages(messages),
              ),
            ),
            if (!hasUserMessage && !_sending)
              _Suggestions(
                items: _suggestions,
                onTap: (q) => _send(q),
              ),
            _Composer(
              controller: _ctrl,
              focusNode: _focus,
              onSend: _send,
              sending: _sending,
              hasInput: _hasInput,
              focused: _isFocused,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages(List<ChatMessage> messages) {
    return ListView.builder(
      controller: _scroll,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      itemCount: messages.length + (_sending ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == messages.length) return const _TypingBubble();
        final msg = messages[i];
        final showTs = i == 0 ||
            messages[i - 1]
                    .timestamp
                    .difference(msg.timestamp)
                    .abs()
                    .inMinutes >
                6;
        // Group consecutive same-role messages → only show avatar on the
        // last one of a group, for a cleaner look.
        final next = i + 1 < messages.length ? messages[i + 1] : null;
        final isLastOfRun = next == null || next.role != msg.role;
        return Column(
          children: [
            if (showTs) _TimestampDivider(t: msg.timestamp),
            _MessageBubble(
              message: msg,
              showAvatar: isLastOfRun && msg.role == ChatRole.agent,
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.connStatus});
  final ConnectionStatus connStatus;

  ({Color color, String label}) get _spec {
    switch (connStatus) {
      case ConnectionStatus.connected:
        return (color: AppColors.threatSafe, label: 'Online · ready to answer');
      case ConnectionStatus.connecting:
        return (color: AppColors.threatWarning, label: 'Connecting to broker…');
      case ConnectionStatus.disconnected:
        return (color: AppColors.textTertiary, label: 'Offline');
      case ConnectionStatus.failed:
        return (color: AppColors.threatAlert, label: 'No broker — check Settings');
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      decoration: const BoxDecoration(color: AppColors.bgBase),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 46,
                height: 46,
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
                  Icons.psychology_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: spec.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.bgBase, width: 2.5),
                  ),
                ),
              ),
            ],
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
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: spec.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        spec.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: spec.color,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.more_horiz_rounded,
              color: AppColors.textSecondary,
            ),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.bgSurface,
              shape: const CircleBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bubble + meta
// ─────────────────────────────────────────────────────────────────────────────

class _TimestampDivider extends StatelessWidget {
  const _TimestampDivider({required this.t});
  final DateTime t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.bgMuted,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            relativeTime(t),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.showAvatar,
  });

  final ChatMessage message;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser)
            SizedBox(
              width: 32,
              child: showAvatar ? const _AgentAvatar() : null,
            ),
          if (!isUser) const SizedBox(width: 6),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.74,
              ),
              child: isUser
                  ? _UserBubble(message: message)
                  : _AgentBubble(message: message, withTail: showAvatar),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentAvatar extends StatelessWidget {
  const _AgentAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.heroGradientSafe,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: AppShadows.card,
      ),
      child: const Icon(
        Icons.shield_rounded,
        color: Colors.white,
        size: 14,
      ),
    );
  }
}

class _AgentBubble extends StatelessWidget {
  const _AgentBubble({required this.message, required this.withTail});
  final ChatMessage message;
  final bool withTail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppRadius.lg),
          topRight: const Radius.circular(AppRadius.lg),
          bottomLeft: Radius.circular(withTail ? 6 : AppRadius.lg),
          bottomRight: const Radius.circular(AppRadius.lg),
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            absoluteTime(message.timestamp),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accent, AppColors.accentDeep],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadius.lg),
          topRight: Radius.circular(AppRadius.lg),
          bottomLeft: Radius.circular(AppRadius.lg),
          bottomRight: Radius.circular(6),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            message.text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                absoluteTime(message.timestamp),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.check_rounded,
                size: 12,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SizedBox(width: 32, child: _AgentAvatar()),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.lg),
                topRight: Radius.circular(AppRadius.lg),
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(AppRadius.lg),
              ),
              boxShadow: AppShadows.card,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) {
                    final phase = (_ctrl.value + i / 3) % 1;
                    final t = (phase < 0.5) ? phase * 2 : (1 - phase) * 2;
                    return Container(
                      margin: EdgeInsets.only(right: i == 2 ? 0 : 4),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: AppColors.accent
                            .withValues(alpha: 0.3 + 0.6 * t),
                        shape: BoxShape.circle,
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Suggestions
// ─────────────────────────────────────────────────────────────────────────────

class _Suggestion {
  const _Suggestion({required this.icon, required this.text});
  final IconData icon;
  final String text;
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.items, required this.onTap});
  final List<_Suggestion> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: items.map((q) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onTap(q.text),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm + 2,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: AppShadows.card,
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(q.icon, size: 14, color: AppColors.accent),
                    const SizedBox(width: 6),
                    Text(
                      q.text,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
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
// Composer
// ─────────────────────────────────────────────────────────────────────────────

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.sending,
    required this.hasInput,
    required this.focused,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final bool sending;
  final bool hasInput;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final canSend = hasInput && !sending;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.sm + MediaQuery.of(context).viewInsets.bottom > 0
              ? AppSpacing.sm
              : AppSpacing.md,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: AppShadows.card,
            border: Border.all(
              color: focused
                  ? AppColors.accent.withValues(alpha: 0.4)
                  : AppColors.border,
              width: focused ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
          child: Row(
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(
                  Icons.add_circle_outline_rounded,
                  color: AppColors.textTertiary,
                  size: 22,
                ),
                tooltip: 'Attach',
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  cursorColor: AppColors.accent,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  minLines: 1,
                  maxLines: 5,
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: const InputDecoration(
                    hintText: 'Ask anything about your home',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: canSend ? onSend : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: canSend
                        ? const LinearGradient(
                            colors: [AppColors.accent, AppColors.accentDeep],
                          )
                        : null,
                    color: canSend ? null : AppColors.bgMuted,
                    shape: BoxShape.circle,
                    boxShadow: canSend
                        ? [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(
                                AppColors.textTertiary),
                          ),
                        )
                      : Icon(
                          Icons.arrow_upward_rounded,
                          color: canSend
                              ? Colors.white
                              : AppColors.textTertiary,
                          size: 20,
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
