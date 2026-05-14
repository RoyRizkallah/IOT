import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'data/broker_config.dart';
import 'features/shell/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(AppTheme.systemUiOverlay);

  // Load the user's last-saved broker config before the first frame so the
  // dashboard mounts with the right host already wired up.
  final brokerCfg = await BrokerConfig.load();

  runApp(
    ProviderScope(
      overrides: [
        brokerConfigProvider.overrideWith((ref) => BrokerConfigNotifier(brokerCfg)),
      ],
      child: const SentryAgentApp(),
    ),
  );
}

class SentryAgentApp extends StatelessWidget {
  const SentryAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SentryAgent',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const MainShell(),
    );
  }
}
