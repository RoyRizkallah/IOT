import 'package:shared_preferences/shared_preferences.dart';

/// Broker connection settings, persisted via SharedPreferences.
///
/// First launch defaults to `10.0.2.2:1883` — the Android emulator's loopback
/// to the dev laptop. Real devices need to be pointed at the laptop's LAN IP
/// from the Settings screen.
class BrokerConfig {
  const BrokerConfig({required this.host, required this.port});

  final String host;
  final int port;

  // v4 keys — bumped so previously saved (broken) hosts/ports are ignored and
  // the new default is picked up on first launch of this build.
  static const _hostKey = 'sentry.broker.host.v4';
  static const _portKey = 'sentry.broker.port.v4';

  /// Default points at the PC-hosted Mosquitto broker over WebSocket port 8083.
  /// For a USB-tethered phone we use `adb reverse` so 127.0.0.1:8083 on the
  /// phone tunnels to the PC broker. For the WiFi/hotspot demo, change the host
  /// in Settings to the PC's hotspot IP (192.168.137.1), same port 8083.
  static const defaults = BrokerConfig(host: '127.0.0.1', port: 8083);

  static Future<BrokerConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return BrokerConfig(
      host: prefs.getString(_hostKey) ?? defaults.host,
      port: prefs.getInt(_portKey) ?? defaults.port,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, host);
    await prefs.setInt(_portKey, port);
  }

  BrokerConfig copyWith({String? host, int? port}) =>
      BrokerConfig(host: host ?? this.host, port: port ?? this.port);

  @override
  bool operator ==(Object other) =>
      other is BrokerConfig && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => '$host:$port';
}
