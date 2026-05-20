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

  static const _hostKey = 'sentry.broker.host';
  static const _portKey = 'sentry.broker.port';

  /// Default for the Android emulator. Real devices set this in Settings.
  static const defaults = BrokerConfig(host: '10.0.2.2', port: 1883);

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
