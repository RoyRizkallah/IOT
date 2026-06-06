import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/haptics.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/camera_config.dart';

/// Live camera feed.
///
/// Connects to the camera relay (`ws://host:port/ws/camera/view`) and renders
/// the binary JPEG frames the Raspberry Pi pushes through it. The relay sends a
/// placeholder frame immediately on connect, so the viewport is never empty.
enum _CamStatus { connecting, waiting, live, offline }

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  final _frame = ValueNotifier<Uint8List?>(null);
  final _status = ValueNotifier<_CamStatus>(_CamStatus.connecting);
  final _fps = ValueNotifier<int>(0);
  final _now = ValueNotifier<DateTime>(DateTime.now());
  final _resolution = ValueNotifier<String?>(null);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  Timer? _tick;
  String? _url;
  int _framesThisSecond = 0;
  int _totalFrames = 0;
  DateTime? _lastFrameAt;
  bool _disposed = false;
  bool _decodingDims = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _tick?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _frame.dispose();
    _status.dispose();
    _fps.dispose();
    _now.dispose();
    _resolution.dispose();
    super.dispose();
  }

  void _onTick() {
    _now.value = DateTime.now();
    _fps.value = _framesThisSecond;
    _framesThisSecond = 0;
    // Recompute "live" — connected but no frame for >2s means the relay is up
    // but the Pi isn't streaming yet.
    final last = _lastFrameAt;
    final flowing = last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 2) &&
        _totalFrames > 1;
    if (_status.value == _CamStatus.live && !flowing) {
      _status.value = _CamStatus.waiting;
    } else if (_status.value == _CamStatus.waiting && flowing) {
      _status.value = _CamStatus.live;
    }
  }

  void _connect(String url) {
    _url = url;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _status.value = _CamStatus.connecting;

    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      _sub = channel.stream.listen(
        _onData,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
      // Keepalive so the relay's viewer loop stays responsive.
      _status.value = _CamStatus.waiting;
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onData(dynamic event) {
    Uint8List? bytes;
    if (event is Uint8List) {
      bytes = event;
    } else if (event is List<int>) {
      bytes = Uint8List.fromList(event);
    }
    if (bytes == null || bytes.length < 4) return;

    _frame.value = bytes;
    _framesThisSecond++;
    _totalFrames++;
    _lastFrameAt = DateTime.now();
    if (_totalFrames > 1) _status.value = _CamStatus.live;
    _maybeReadDimensions(bytes);
  }

  // Decode the true frame size once so the details panel can show a real
  // resolution instead of a hardcoded guess. Cheap: runs only until we know it.
  void _maybeReadDimensions(Uint8List bytes) {
    if (_resolution.value != null || _decodingDims) return;
    _decodingDims = true;
    ui.decodeImageFromList(bytes, (image) {
      if (!_disposed) {
        _resolution.value = '${image.width}×${image.height}';
      }
      image.dispose();
      _decodingDims = false;
    });
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _status.value = _CamStatus.offline;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (_disposed || _url == null) return;
      _connect(_url!);
    });
  }

  void _manualReconnect() {
    Haptics.tap();
    _totalFrames = 0;
    _resolution.value = null;
    if (_url != null) _connect(_url!);
  }

  @override
  Widget build(BuildContext context) {
    // (Re)connect whenever the resolved relay URL changes.
    final url = ref.watch(cameraViewUrlProvider);
    if (url != _url) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) _connect(url);
      });
    }

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
            _header(context),
            const SizedBox(height: AppSpacing.md),
            _viewport(context),
            const SizedBox(height: AppSpacing.md),
            _detailsCard(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Live Camera',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
              ),
              Text(
                'Raspberry Pi camera stream',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        ValueListenableBuilder<_CamStatus>(
          valueListenable: _status,
          builder: (_, s, __) => _StatusPill(status: s),
        ),
      ],
    );
  }

  Widget _viewport(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Haptics.tap();
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _FullscreenView(frame: _frame, status: _status),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadows.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ValueListenableBuilder<Uint8List?>(
                valueListenable: _frame,
                builder: (_, bytes, __) {
                  if (bytes == null) {
                    return const _CameraPlaceholder();
                  }
                  return Image.memory(
                    bytes,
                    gaplessPlayback: true,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const _CameraPlaceholder(),
                  );
                },
              ),
              // Subtle top gradient so overlays stay legible over bright frames.
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 64,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                ),
              ),
              // Top-left LIVE badge.
              Positioned(
                top: 10,
                left: 10,
                child: ValueListenableBuilder<_CamStatus>(
                  valueListenable: _status,
                  builder: (_, s, __) => _LiveBadge(status: s),
                ),
              ),
              // Top-right CCTV-style live timestamp.
              Positioned(
                top: 10,
                right: 10,
                child: ValueListenableBuilder<DateTime>(
                  valueListenable: _now,
                  builder: (_, t, __) => Text(
                    DateFormat('yyyy-MM-dd  HH:mm:ss').format(t),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      letterSpacing: 0.4,
                      shadows: [
                        Shadow(blurRadius: 4, color: Colors.black87),
                      ],
                    ),
                  ),
                ),
              ),
              // Bottom strip: fps + tap-to-expand hint.
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Row(
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: _fps,
                      builder: (_, fps, __) => _GlassChip(
                        icon: Icons.speed_rounded,
                        text: '$fps fps',
                      ),
                    ),
                    const Spacer(),
                    const _GlassChip(
                      icon: Icons.fullscreen_rounded,
                      text: 'Tap to expand',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailsCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.sensorMotionSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(Icons.videocam_rounded,
                    size: 20, color: AppColors.sensorMotion),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Entrance Camera',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      'Indoor · Raspberry Pi',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _RoundIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Reconnect',
                onTap: _manualReconnect,
              ),
              const SizedBox(width: AppSpacing.xs),
              _RoundIconButton(
                icon: Icons.settings_outlined,
                tooltip: 'Camera settings',
                onTap: () => _editCamera(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: ValueListenableBuilder<_CamStatus>(
                  valueListenable: _status,
                  builder: (_, s, __) {
                    final live = s == _CamStatus.live;
                    return _StatTile(
                      icon: live
                          ? Icons.sensors_rounded
                          : Icons.sensors_off_rounded,
                      label: 'Status',
                      value: switch (s) {
                        _CamStatus.live => 'Streaming',
                        _CamStatus.connecting => 'Connecting',
                        _CamStatus.waiting => 'Standby',
                        _CamStatus.offline => 'Offline',
                      },
                      color: live
                          ? AppColors.threatSafe
                          : (s == _CamStatus.offline
                              ? AppColors.threatAlert
                              : AppColors.threatWarning),
                    );
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: _fps,
                  builder: (_, fps, __) => _StatTile(
                    icon: Icons.speed_rounded,
                    label: 'Frame rate',
                    value: '$fps fps',
                    color: AppColors.sensorMotion,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ValueListenableBuilder<String?>(
                  valueListenable: _resolution,
                  builder: (_, res, __) => _StatTile(
                    icon: Icons.hd_rounded,
                    label: 'Resolution',
                    value: res ?? '—',
                    color: AppColors.sensorSound,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.lock_rounded,
                  size: 13, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Text(
                'Private stream · stays on your local network',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editCamera(BuildContext context) async {
    Haptics.tap();
    final current = ref.read(cameraConfigProvider);
    final updated = await showModalBottomSheet<CameraConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CameraEditSheet(initial: current),
    );
    if (updated != null && updated != current) {
      await ref.read(cameraConfigProvider.notifier).update(updated);
      Haptics.confirm();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fullscreen
// ─────────────────────────────────────────────────────────────────────────────

class _FullscreenView extends StatelessWidget {
  const _FullscreenView({required this.frame, required this.status});
  final ValueNotifier<Uint8List?> frame;
  final ValueNotifier<_CamStatus> status;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              maxScale: 4,
              child: ValueListenableBuilder<Uint8List?>(
                valueListenable: frame,
                builder: (_, bytes, __) {
                  if (bytes == null) return const _CameraPlaceholder();
                  return Image.memory(
                    bytes,
                    gaplessPlayback: true,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const _CameraPlaceholder(),
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: ValueListenableBuilder<_CamStatus>(
              valueListenable: status,
              builder: (_, s, __) => _LiveBadge(status: s),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            right: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small pieces
// ─────────────────────────────────────────────────────────────────────────────

class _CameraPlaceholder extends StatelessWidget {
  const _CameraPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B0F17),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off_rounded,
              size: 44, color: Colors.white24),
          const SizedBox(height: 10),
          Text(
            'Waiting for camera…',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white38),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.status});
  final _CamStatus status;

  @override
  Widget build(BuildContext context) {
    final live = status == _CamStatus.live;
    final color = live ? AppColors.threatAlert : Colors.white54;
    final label = switch (status) {
      _CamStatus.live => 'LIVE',
      _CamStatus.connecting => 'CONNECTING',
      _CamStatus.waiting => 'NO SIGNAL',
      _CamStatus.offline => 'OFFLINE',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white70),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
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
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
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
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.bgMuted,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, size: 18, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final _CamStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      _CamStatus.live => (AppColors.threatSafe, 'LIVE'),
      _CamStatus.connecting => (AppColors.threatWarning, 'CONNECTING'),
      _CamStatus.waiting => (AppColors.threatWarning, 'NO SIGNAL'),
      _CamStatus.offline => (AppColors.threatAlert, 'OFFLINE'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Config edit sheet
// ─────────────────────────────────────────────────────────────────────────────

class _CameraEditSheet extends StatefulWidget {
  const _CameraEditSheet({required this.initial});
  final CameraConfig initial;

  @override
  State<_CameraEditSheet> createState() => _CameraEditSheetState();
}

class _CameraEditSheetState extends State<_CameraEditSheet> {
  late final _hostCtrl = TextEditingController(text: widget.initial.hostOverride);
  late final _portCtrl =
      TextEditingController(text: widget.initial.port.toString());
  String? _portErr;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final port = int.tryParse(_portCtrl.text.trim());
    if (port == null || port <= 0 || port > 65535) {
      setState(() => _portErr = '1 – 65535');
      Haptics.alert();
      return;
    }
    Navigator.of(context).pop(
      CameraConfig(hostOverride: _hostCtrl.text.trim(), port: port),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
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
              'Camera settings',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Leave host empty to use your hub automatically.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _hostCtrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Host (optional)',
                hintText: 'same as broker, or 192.168.x.x',
                prefixIcon: Icon(Icons.dns_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _portCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Port',
                hintText: '8000',
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
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.sm + 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
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
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.sm + 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
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
