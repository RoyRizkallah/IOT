import 'dart:async';

import '../models/security_state.dart';

/// Whether the underlying data source is connected to the broker.
///
/// The `MqttDataSource` updates this whenever its underlying client connects
/// or drops; the UI subscribes via `connectionStatusProvider` to render an
/// indicator and disable arm/disarm controls while disconnected.
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  failed;

  bool get isLive => this == ConnectionStatus.connected;
}

/// The contract every data source must satisfy.
///
/// Implementations:
///   - `MqttDataSource` — talks to the live broker (production / dev).
abstract class SecurityDataSource {
  /// Live stream of security state updates.
  Stream<SecurityState> get stream;

  /// Live, append-only event log (newest first).
  Stream<List<SecurityEvent>> get events;

  /// Live agent decision log (newest first).
  Stream<List<AgentDecision>> get decisions;

  /// Conversation with the agent (Agent Console).
  Stream<List<ChatMessage>> get chat;

  /// Connection status. Emits the current value on subscribe.
  Stream<ConnectionStatus> get connectionStatus;

  /// Send a user chat message; the agent will reply asynchronously.
  Future<void> sendChat(String text);

  /// Send an arm/disarm command.
  Future<void> setArmed(bool armed);

  /// Manual siren trigger (used by control panel, future use).
  Future<void> triggerSiren();

  /// Re-issue a state replay request to the agent — used after the user
  /// changes broker config and we reconnect.
  Future<void> requestReplay();

  /// Cleanup.
  void dispose();
}
