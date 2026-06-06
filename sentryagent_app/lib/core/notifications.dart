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

Future<void> initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const settings = InitializationSettings(android: android);
  await _plugin.initialize(settings);

  await _plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_androidChannel);

  await _plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
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
