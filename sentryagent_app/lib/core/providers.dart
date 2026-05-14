import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/broker_config.dart';
import '../data/models/security_state.dart';
import '../data/sources/mqtt_data_source.dart';
import '../data/sources/security_data_source.dart';

/// The active broker configuration. Persisted on every change.
///
/// `main.dart` overrides this provider with the value loaded from
/// SharedPreferences before mounting the app, so first frame already has
/// the user's last-saved host/port.
final brokerConfigProvider =
    StateNotifierProvider<BrokerConfigNotifier, BrokerConfig>((ref) {
  return BrokerConfigNotifier(BrokerConfig.defaults);
});

class BrokerConfigNotifier extends StateNotifier<BrokerConfig> {
  BrokerConfigNotifier(super.state);

  /// Update the in-memory + persisted config. Listeners on
  /// `brokerConfigProvider` see the change immediately; the
  /// `dataSourceProvider` disposes its old MqttDataSource and creates a
  /// fresh one because it `watch`es this provider.
  Future<void> update(BrokerConfig cfg) async {
    if (cfg == state) return;
    state = cfg;
    await cfg.save();
  }
}

/// The active data source. Recreated whenever broker config changes —
/// Riverpod auto-disposes the previous instance via `ref.onDispose`.
final dataSourceProvider = Provider<SecurityDataSource>((ref) {
  final cfg = ref.watch(brokerConfigProvider);
  final source = MqttDataSource(config: cfg);
  ref.onDispose(source.dispose);
  return source;
});

/// Convenience: cast the data source to its concrete type when we need
/// behaviours that aren't in the abstract interface (e.g. `reconfigure`
/// without a full provider rebuild). Use sparingly.
final mqttDataSourceProvider = Provider<MqttDataSource>((ref) {
  final src = ref.watch(dataSourceProvider);
  if (src is MqttDataSource) return src;
  throw StateError('Active data source is not MqttDataSource');
});

/// Live security state (used by Dashboard + global header).
final securityStateProvider = StreamProvider<SecurityState>((ref) {
  return ref.watch(dataSourceProvider).stream;
});

/// Append-only event log (used by Alert History).
final eventsProvider = StreamProvider<List<SecurityEvent>>((ref) {
  return ref.watch(dataSourceProvider).events;
});

/// Agent decisions (used by Reasoning Log).
final decisionsProvider = StreamProvider<List<AgentDecision>>((ref) {
  return ref.watch(dataSourceProvider).decisions;
});

/// Conversation with the agent (used by Agent Console).
final chatProvider = StreamProvider<List<ChatMessage>>((ref) {
  return ref.watch(dataSourceProvider).chat;
});

/// MQTT connection status (used by the AppBar pill + Settings).
final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  return ref.watch(dataSourceProvider).connectionStatus;
});

/// Which tab is currently selected in the [MainShell].
final mainTabIndexProvider = StateProvider<int>((_) => 0);
