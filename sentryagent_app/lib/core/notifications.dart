import 'dart:developer' as developer;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final _plugin = FlutterLocalNotificationsPlugin();

const _androidChannel = AndroidNotificationChannel(
  'sentry_alerts',
  'SentryAgent Alerts',
  description: 'Threat-level alerts from SentryAgent.',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

/// Best-effort notification setup. MUST NOT throw — a plugin failure here
/// (e.g. requestNotificationsPermission can NPE on some Android builds) was
/// aborting `main()` before runApp(), which left the broker unconnected.
/// Notifications are non-essential, so we swallow and log any failure.
Future<void> initNotifications() async {
  try {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(_androidChannel);

    // Wrapped separately: the permission request is the call that NPEs.
    try {
      await androidImpl?.requestNotificationsPermission();
    } catch (e) {
      developer.log('requestNotificationsPermission failed (non-fatal): $e');
    }
  } catch (e, st) {
    developer.log('initNotifications failed (non-fatal): $e',
        error: e, stackTrace: st);
  }
}

Future<void> showAlertNotification({
  required String title,
  required String body,
  bool highPriority = true,
}) async {
  final androidDetails = AndroidNotificationDetails(
    _androidChannel.id,
    _androidChannel.name,
    channelDescription: _androidChannel.description,
    importance: highPriority ? Importance.max : Importance.high,
    priority: highPriority ? Priority.max : Priority.high,
    ticker: title,
    icon: '@mipmap/ic_launcher',
  );

  await _plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    NotificationDetails(android: androidDetails),
  );
}
