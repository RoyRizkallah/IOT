import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/background_task.dart';
import 'core/notifications.dart';
import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'data/broker_config.dart';
import 'data/camera_config.dart';
import 'features/shell/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(AppTheme.systemUiOverlay);

  await initNotifications();
  _initForegroundTask();

  // Load the user's last-saved broker + camera config before the first frame
  // so the dashboard mounts with the right hosts already wired up.
  final brokerCfg = await BrokerConfig.load();
  final cameraCfg = await CameraConfig.load();

  runApp(
    ProviderScope(
      overrides: [
        brokerConfigProvider.overrideWith((ref) => BrokerConfigNotifier(brokerCfg)),
        cameraConfigProvider.overrideWith((ref) => CameraConfigNotifier(cameraCfg)),
      ],
      child: const SentryAgentApp(),
    ),
  );
}

void _initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'sentry_monitor',
      channelName: 'SentryAgent Monitor',
      channelDescription: 'Keeps SentryAgent monitoring in the background.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(30000),
      autoRunOnBoot: false,
    ),
  );
}

Future<void> startForegroundMonitor() async {
  if (await FlutterForegroundTask.isRunningService) return;

  await FlutterForegroundTask.startService(
    serviceId: 1001,
    notificationTitle: 'SentryAgent',
    notificationText: 'Monitoring for security alerts…',
    callback: startBackgroundTask,
  );
}

class SentryAgentApp extends StatefulWidget {
  const SentryAgentApp({super.key});

  @override
  State<SentryAgentApp> createState() => _SentryAgentAppState();
}

class _SentryAgentAppState extends State<SentryAgentApp> {
  @override
  void initState() {
    super.initState();
    // Start the foreground monitor after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => startForegroundMonitor());
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: 'SentryAgent',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const MainShell(),
      ),
    );
  }
}
