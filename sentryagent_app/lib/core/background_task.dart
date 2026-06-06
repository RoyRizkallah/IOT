import 'dart:async';
import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notifications.dart';

// Entry point for the background isolate — must be a top-level function.
@pragma('vm:entry-point')
void startBackgroundTask() {
  FlutterForegroundTask.setTaskHandler(_SentryTaskHandler());
}

class _SentryTaskHandler extends TaskHandler {
  MqttServerClient? _client;
  String _lastLevel = 'safe';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await initNotifications();

    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('sentry.broker.host') ?? '10.0.2.2';
    final port = prefs.getInt('sentry.broker.port') ?? 1883;

    await _connectMqtt(host, port);
  }

  Future<void> _connectMqtt(String host, int port) async {
    _client = MqttServerClient(host, 'sentry_bg_${DateTime.now().millisecondsSinceEpoch}')
      ..port = port
      ..keepAlivePeriod = 20
      ..autoReconnect = true
      ..logging(on: false);

    try {
      await _client!.connect();
      _client!.subscribe('sentry/state', MqttQos.atLeastOnce);
      _client!.updates?.listen(_onMessage);
    } catch (_) {
      // Retry handled by autoReconnect
    }
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final msg in messages) {
      final pub = msg.payload as MqttPublishMessage;
      final raw = MqttPublishPayload.bytesToStringAsString(pub.payload.message);
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final level = data['level'] as String? ?? 'safe';
        if (level == _lastLevel) continue;
        _lastLevel = level;

        if (level == 'alert') {
          showAlertNotification(
            title: '🚨 SentryAgent Alert',
            body: 'Security alert detected! Open the app now.',
          );
        } else if (level == 'warning') {
          showAlertNotification(
            title: '⚠️ SentryAgent Warning',
            body: 'Threat level elevated — check the dashboard.',
            highPriority: false,
          );
        }
      } catch (_) {}
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // Keep-alive ping — reconnect if dropped.
    if (_client?.connectionStatus?.state != MqttConnectionState.connected) {
      final prefs = await SharedPreferences.getInstance();
      final host = prefs.getString('sentry.broker.host') ?? '10.0.2.2';
      final port = prefs.getInt('sentry.broker.port') ?? 1883;
      await _connectMqtt(host, port);
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _client?.disconnect();
  }
}
