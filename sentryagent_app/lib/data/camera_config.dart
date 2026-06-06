import 'package:shared_preferences/shared_preferences.dart';

import 'broker_config.dart';

/// Camera relay connection settings, persisted via SharedPreferences.
///
/// The relay normally runs on the same machine as the MQTT broker (the dev
/// laptop), so by default we reuse the broker host and only need a port. Set
/// [hostOverride] if the camera relay lives somewhere else.
class CameraConfig {
  const CameraConfig({this.hostOverride = '', this.port = 8000});

  /// Empty → fall back to the broker host. Otherwise an explicit host/IP.
  final String hostOverride;
  final int port;

  static const _hostKey = 'sentry.camera.host';
  static const _portKey = 'sentry.camera.port';

  static const defaults = CameraConfig();

  static Future<CameraConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return CameraConfig(
      hostOverride: prefs.getString(_hostKey) ?? defaults.hostOverride,
      port: prefs.getInt(_portKey) ?? defaults.port,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, hostOverride);
    await prefs.setInt(_portKey, port);
  }

  /// The host actually used: the override if present, else the broker host.
  String resolveHost(BrokerConfig broker) =>
      hostOverride.trim().isEmpty ? broker.host : hostOverride.trim();

  /// `ws://<host>:<port>/ws/camera/view`
  String viewUrl(BrokerConfig broker) =>
      'ws://${resolveHost(broker)}:$port/ws/camera/view';

  CameraConfig copyWith({String? hostOverride, int? port}) => CameraConfig(
        hostOverride: hostOverride ?? this.hostOverride,
        port: port ?? this.port,
      );

  @override
  bool operator ==(Object other) =>
      other is CameraConfig &&
      other.hostOverride == hostOverride &&
      other.port == port;

  @override
  int get hashCode => Object.hash(hostOverride, port);

  @override
  String toString() => '${hostOverride.isEmpty ? "(broker host)" : hostOverride}:$port';
}
