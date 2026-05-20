import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../broker_config.dart';
import '../models/security_state.dart';
import 'security_data_source.dart';

/// Topics — must match `sentry/mqtt/topics.py` on the backend.
class _Topics {
  static const events = 'home/events';
  static const state = 'home/agent/state';
  static const decision = 'home/agent/decision';
  static const chatOut = 'home/agent/chat/out';
  static const replay = 'home/agent/replay';

  static const arm = 'home/control/arm';
  static const siren = 'home/control/siren';
  static const chatIn = 'home/control/chat/in';
  static const replayReq = 'home/control/replay';
}

/// Live data source backed by an MQTT broker.
///
/// Subscribes to the agent's output topics, accumulates state in-memory, and
/// fans the updates out through the streams the rest of the app already
/// consumes via `SecurityDataSource`. Publishes to the control topics on
/// `setArmed`, `sendChat`, `triggerSiren`.
///
/// On every (re)connect, immediately requests a `home/control/replay` so the
/// app's history is backfilled from the agent's in-memory log.
class MqttDataSource implements SecurityDataSource {
  MqttDataSource({required BrokerConfig config}) : _config = config {
    unawaited(connect());
  }

  BrokerConfig _config;

  // ─── Streams ────────────────────────────────────────────────────────────

  final _stateCtrl = StreamController<SecurityState>.broadcast();
  final _eventsCtrl = StreamController<List<SecurityEvent>>.broadcast();
  final _decisionsCtrl = StreamController<List<AgentDecision>>.broadcast();
  final _chatCtrl = StreamController<List<ChatMessage>>.broadcast();
  final _connCtrl = StreamController<ConnectionStatus>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStatus get statusNow => _status;

  // ─── Accumulators (replay populates these on connect) ───────────────────

  SecurityState _lastState = SecurityState.initial();
  final List<SecurityEvent> _events = [];
  final List<AgentDecision> _decisions = [];
  final List<ChatMessage> _chat = [];

  MqttServerClient? _client;
  StreamSubscription? _msgSub;
  bool _disposed = false;

  // ─── SecurityDataSource impl ────────────────────────────────────────────

  @override
  Stream<SecurityState> get stream {
    // Replay the last seen state to new subscribers immediately.
    return _replayingStream(_stateCtrl.stream, _lastState);
  }

  @override
  Stream<List<SecurityEvent>> get events =>
      _replayingStream(_eventsCtrl.stream, List<SecurityEvent>.unmodifiable(_events));

  @override
  Stream<List<AgentDecision>> get decisions => _replayingStream(
        _decisionsCtrl.stream,
        List<AgentDecision>.unmodifiable(_decisions),
      );

  @override
  Stream<List<ChatMessage>> get chat =>
      _replayingStream(_chatCtrl.stream, List<ChatMessage>.unmodifiable(_chat));

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      _replayingStream(_connCtrl.stream, _status);

  @override
  Future<void> setArmed(bool armed) =>
      _publish(_Topics.arm, jsonEncode({'armed': armed}), retain: true);

  @override
  Future<void> triggerSiren() => _publish(
        _Topics.siren,
        jsonEncode({'action': 'trigger', 'reason': 'manual'}),
      );

  @override
  Future<void> sendChat(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final msg = ChatMessage(
      id: 'msg_${_randomId()}',
      role: ChatRole.user,
      text: trimmed,
      timestamp: DateTime.now(),
    );
    _chat.add(msg);
    _emitChat();
    await _publish(_Topics.chatIn, msg.toOutboundJsonString());
  }

  @override
  Future<void> requestReplay() async {
    await _publish(_Topics.replayReq, '{}');
  }

  @override
  void dispose() {
    _disposed = true;
    _msgSub?.cancel();
    _client?.disconnect();
    _stateCtrl.close();
    _eventsCtrl.close();
    _decisionsCtrl.close();
    _chatCtrl.close();
    _connCtrl.close();
  }

  // ─── Public extras ──────────────────────────────────────────────────────

  /// Apply new broker config. Disconnects any existing client and starts a
  /// fresh connection. Safe to call repeatedly.
  Future<void> reconfigure(BrokerConfig config) async {
    _config = config;
    _msgSub?.cancel();
    try {
      _client?.disconnect();
    } catch (_) {/* tolerate broken state */}
    _client = null;
    await connect();
  }

  /// Establishes the MQTT connection and subscribes to the agent's output
  /// topics. Called automatically by the constructor and by `reconfigure`.
  Future<void> connect() async {
    if (_disposed) return;
    _setStatus(ConnectionStatus.connecting);

    final client = MqttServerClient.withPort(
      _config.host,
      _clientId(),
      _config.port,
    )
      ..keepAlivePeriod = 20
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..logging(on: false)
      ..onConnected = _onConnected
      ..onDisconnected = _onDisconnected
      ..onAutoReconnect = () {
        _setStatus(ConnectionStatus.connecting);
      }
      ..onAutoReconnected = _onConnected
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier(_clientId())
          .startClean()
          .withWillQos(MqttQos.atMostOnce);

    _client = client;

    try {
      await client.connect();
    } catch (e, stack) {
      developer.log('MQTT connect failed: $e', error: e, stackTrace: stack);
      _setStatus(ConnectionStatus.failed);
      return;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      _setStatus(ConnectionStatus.failed);
      return;
    }

    _msgSub = client.updates?.listen(_onMessages);
    _subscribeAll();
    await requestReplay();
  }

  // ─── Connection lifecycle ───────────────────────────────────────────────

  void _onConnected() {
    _setStatus(ConnectionStatus.connected);
    // After a reconnect, resubscribe explicitly even though autoreconnect
    // claims to do it — some brokers behave better with the explicit call.
    _subscribeAll();
    unawaited(requestReplay());
  }

  void _onDisconnected() {
    if (_disposed) return;
    _setStatus(ConnectionStatus.disconnected);
  }

  void _subscribeAll() {
    final c = _client;
    if (c == null) return;
    for (final t in [
      _Topics.state,
      _Topics.events,
      _Topics.decision,
      _Topics.chatOut,
      _Topics.replay,
    ]) {
      c.subscribe(t, MqttQos.atMostOnce);
    }
  }

  // ─── Message dispatch ───────────────────────────────────────────────────

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> batch) {
    for (final received in batch) {
      try {
        _onOneMessage(received);
      } catch (e, stack) {
        developer.log(
          'Bad MQTT message on ${received.topic}: $e',
          error: e,
          stackTrace: stack,
        );
      }
    }
  }

  void _onOneMessage(MqttReceivedMessage<MqttMessage> received) {
    final msg = received.payload as MqttPublishMessage;
    final raw = MqttPublishPayload.bytesToStringAsString(msg.payload.message);
    if (raw.isEmpty) return;
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) return;

    switch (received.topic) {
      case _Topics.state:
        _handleState(json);
      case _Topics.events:
        _handleEvent(json);
      case _Topics.decision:
        _handleDecision(json);
      case _Topics.chatOut:
        _handleChat(json);
      case _Topics.replay:
        _handleReplay(json);
    }
  }

  void _handleState(Map<String, dynamic> j) {
    _lastState = SecurityState.fromJson(j);
    _stateCtrl.add(_lastState);
  }

  void _handleEvent(Map<String, dynamic> j) {
    final ev = SecurityEvent.fromJson(j);
    if (_events.any((e) => e.id == ev.id)) return;
    _events.insert(0, ev);
    if (_events.length > 200) _events.removeRange(200, _events.length);
    _emitEvents();
  }

  void _handleDecision(Map<String, dynamic> j) {
    final d = AgentDecision.fromJson(j);
    if (_decisions.any((x) => x.id == d.id)) return;
    _decisions.insert(0, d);
    if (_decisions.length > 100) _decisions.removeRange(100, _decisions.length);
    _emitDecisions();
  }

  void _handleChat(Map<String, dynamic> j) {
    final m = ChatMessage.fromJson(j);
    if (_chat.any((x) => x.id == m.id)) return;
    _chat.add(m);
    if (_chat.length > 200) _chat.removeRange(0, _chat.length - 200);
    _emitChat();
  }

  void _handleReplay(Map<String, dynamic> j) {
    if (j['state'] is Map<String, dynamic>) {
      _lastState = SecurityState.fromJson(j['state'] as Map<String, dynamic>);
      _stateCtrl.add(_lastState);
    }

    final eventsJson = (j['events'] as List?) ?? const [];
    _events
      ..clear()
      ..addAll(
        eventsJson
            .map((e) => SecurityEvent.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
    _emitEvents();

    final decisionsJson = (j['decisions'] as List?) ?? const [];
    _decisions
      ..clear()
      ..addAll(
        decisionsJson
            .map((e) => AgentDecision.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
    _emitDecisions();

    final chatJson = (j['chat'] as List?) ?? const [];
    _chat
      ..clear()
      ..addAll(
        chatJson
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
    _emitChat();
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  void _emitEvents() => _eventsCtrl.add(List.unmodifiable(_events));

  void _emitDecisions() => _decisionsCtrl.add(List.unmodifiable(_decisions));

  void _emitChat() => _chatCtrl.add(List.unmodifiable(_chat));

  void _setStatus(ConnectionStatus s) {
    if (_status == s) return;
    _status = s;
    _connCtrl.add(s);
  }

  Future<void> _publish(
    String topic,
    String payload, {
    bool retain = false,
  }) async {
    final c = _client;
    if (c == null || c.connectionStatus?.state != MqttConnectionState.connected) {
      developer.log('MQTT publish skipped (not connected): $topic');
      return;
    }
    final builder = MqttClientPayloadBuilder()..addString(payload);
    c.publishMessage(topic, MqttQos.atMostOnce, builder.payload!, retain: retain);
  }

  String _clientId() => 'sentry-app-${_randomId()}';

  static String _randomId() {
    final r = Random();
    final bytes = List<int>.generate(4, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Wraps a broadcast stream so new subscribers immediately receive the
  /// latest cached value. The Riverpod StreamProvider expects this; without
  /// it, subscribers that join after the first event sit empty until the
  /// next broker message.
  Stream<T> _replayingStream<T>(Stream<T> upstream, T initial) async* {
    yield initial;
    yield* upstream;
  }
}
