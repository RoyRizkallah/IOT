// Domain models for SentryAgent.
//
// These define the contract between data sources (MQTT) and the UI.
// fromJson factories are tolerant of the Python-side wire format (snake_case
// fields, ISO-8601 timestamps, optional fields).

import 'dart:convert';

/// The four sensors we monitor.
enum SensorType {
  motion,
  sound,
  door,
  temperature;

  static SensorType fromWire(String wire) => switch (wire) {
        'motion' => SensorType.motion,
        'sound' => SensorType.sound,
        'door' => SensorType.door,
        'temperature' => SensorType.temperature,
        _ => throw ArgumentError('Unknown sensor type: $wire'),
      };

  String get wire => name;

  String get displayName => switch (this) {
        SensorType.motion => 'Motion',
        SensorType.sound => 'Sound',
        SensorType.door => 'Door',
        SensorType.temperature => 'Temperature',
      };

  String get unit => switch (this) {
        SensorType.motion => '',
        SensorType.sound => 'dB',
        SensorType.door => '',
        SensorType.temperature => '°C',
      };
}

/// Threat severity bands derived from the score.
enum ThreatLevel {
  safe, // score 0-3
  warning, // score 4-6
  alert; // score 7-10

  static ThreatLevel fromScore(int score) {
    if (score >= 7) return ThreatLevel.alert;
    if (score >= 4) return ThreatLevel.warning;
    return ThreatLevel.safe;
  }

  static ThreatLevel fromWire(String wire) => switch (wire) {
        'safe' => ThreatLevel.safe,
        'warning' => ThreatLevel.warning,
        'alert' => ThreatLevel.alert,
        _ => ThreatLevel.safe,
      };

  String get wire => name;

  String get label => switch (this) {
        ThreatLevel.safe => 'SECURE',
        ThreatLevel.warning => 'WARNING',
        ThreatLevel.alert => 'ALERT',
      };
}

/// A single sensor reading at a point in time.
class SensorReading {
  const SensorReading({
    required this.type,
    required this.value,
    required this.active,
    required this.timestamp,
  });

  final SensorType type;
  final double value;
  final bool active;
  final DateTime timestamp;

  factory SensorReading.fromJson(Map<String, dynamic> j) => SensorReading(
        type: SensorType.fromWire(j['type'] as String),
        value: (j['value'] as num).toDouble(),
        active: (j['active'] as bool?) ?? false,
        timestamp: DateTime.parse(j['timestamp'] as String).toLocal(),
      );
}

/// A discrete security event.
class SecurityEvent {
  const SecurityEvent({
    required this.id,
    required this.sensor,
    required this.severity,
    required this.message,
    required this.timestamp,
    this.rawValue,
  });

  final String id;
  final SensorType sensor;
  final ThreatLevel severity;
  final String message;
  final DateTime timestamp;
  final double? rawValue;

  factory SecurityEvent.fromJson(Map<String, dynamic> j) => SecurityEvent(
        id: j['id'] as String,
        sensor: SensorType.fromWire(j['sensor'] as String),
        severity: ThreatLevel.fromWire(j['severity'] as String),
        message: j['message'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String).toLocal(),
        rawValue: (j['raw_value'] as num?)?.toDouble(),
      );
}

/// One agent decision — what context it saw, how it reasoned, what it did.
class AgentDecision {
  const AgentDecision({
    required this.id,
    required this.timestamp,
    required this.severity,
    required this.summary,
    required this.context,
    required this.reasoning,
    required this.toolsCalled,
    required this.finalAction,
    required this.finalActionReason,
  });

  final String id;
  final DateTime timestamp;
  final ThreatLevel severity;
  final String summary;
  final String context;
  final String reasoning;
  final List<AgentToolCall> toolsCalled;

  /// Machine-level action: one of `ignore`, `log`, `notify_user`,
  /// `request_confirmation`, `trigger_siren`, `auto_resolve`.
  final String finalAction;

  /// Human-readable one-liner explaining the chosen action.
  final String finalActionReason;

  factory AgentDecision.fromJson(Map<String, dynamic> j) => AgentDecision(
        id: j['id'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String).toLocal(),
        severity: ThreatLevel.fromWire(j['severity'] as String),
        summary: (j['summary'] as String?) ?? '',
        context: (j['context'] as String?) ?? '',
        reasoning: (j['reasoning'] as String?) ?? '',
        toolsCalled: ((j['tools_called'] as List?) ?? const [])
            .map((e) => AgentToolCall.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        finalAction: (j['final_action'] as String?) ?? 'log',
        finalActionReason: (j['final_action_reason'] as String?) ?? '',
      );
}

class AgentToolCall {
  const AgentToolCall({
    required this.name,
    required this.argsSummary,
    required this.resultSummary,
  });

  final String name;
  final String argsSummary;
  final String resultSummary;

  factory AgentToolCall.fromJson(Map<String, dynamic> j) => AgentToolCall(
        name: (j['name'] as String?) ?? '',
        argsSummary: (j['args_summary'] as String?) ?? '',
        resultSummary: (j['result_summary'] as String?) ?? '',
      );
}

/// One message in the Agent Console chat.
enum ChatRole {
  user,
  agent;

  static ChatRole fromWire(String wire) =>
      wire == 'user' ? ChatRole.user : ChatRole.agent;

  String get wire => name;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
    this.inReplyTo,
  });

  final String id;
  final ChatRole role;
  final String text;
  final DateTime timestamp;
  final String? inReplyTo;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        role: ChatRole.fromWire(j['role'] as String),
        text: (j['text'] as String?) ?? '',
        timestamp: DateTime.parse(j['timestamp'] as String).toLocal(),
        inReplyTo: j['in_reply_to'] as String?,
      );

  /// Outgoing payload for `home/control/chat/in`.
  Map<String, dynamic> toOutboundJson() => {
        'id': id,
        'role': role.wire,
        'text': text,
        'timestamp': timestamp.toUtc().toIso8601String(),
      };

  String toOutboundJsonString() => jsonEncode(toOutboundJson());
}

/// The overall security state at a moment in time.
class SecurityState {
  const SecurityState({
    required this.armed,
    required this.threatScore,
    required this.readings,
    required this.lastUpdate,
  });

  final bool armed;
  final int threatScore;
  final List<SensorReading> readings;
  final DateTime lastUpdate;

  ThreatLevel get level => ThreatLevel.fromScore(threatScore);

  /// Returns `null` if the broker hasn't reported this sensor yet — used
  /// while we wait for the first state heartbeat to arrive.
  SensorReading? maybeReading(SensorType type) {
    for (final r in readings) {
      if (r.type == type) return r;
    }
    return null;
  }

  /// Returns a "zero" sensor reading if the broker hasn't reported one yet.
  /// Useful for UI components that always need a value to show.
  SensorReading reading(SensorType type) =>
      maybeReading(type) ??
      SensorReading(type: type, value: 0, active: false, timestamp: lastUpdate);

  SecurityState copyWith({
    bool? armed,
    int? threatScore,
    List<SensorReading>? readings,
    DateTime? lastUpdate,
  }) {
    return SecurityState(
      armed: armed ?? this.armed,
      threatScore: threatScore ?? this.threatScore,
      readings: readings ?? this.readings,
      lastUpdate: lastUpdate ?? this.lastUpdate,
    );
  }

  factory SecurityState.fromJson(Map<String, dynamic> j) => SecurityState(
        armed: (j['armed'] as bool?) ?? false,
        threatScore: (j['threat_score'] as num?)?.toInt() ?? 0,
        readings: ((j['readings'] as List?) ?? const [])
            .map((e) => SensorReading.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        lastUpdate: DateTime.parse(
          j['last_update'] as String,
        ).toLocal(),
      );

  /// Initial "all quiet" state used before the first reading arrives.
  factory SecurityState.initial() {
    final now = DateTime.now();
    return SecurityState(
      armed: false,
      threatScore: 0,
      readings: [
        SensorReading(type: SensorType.motion, value: 0, active: false, timestamp: now),
        SensorReading(type: SensorType.sound, value: 32, active: false, timestamp: now),
        SensorReading(type: SensorType.door, value: 0, active: false, timestamp: now),
        SensorReading(type: SensorType.temperature, value: 22.4, active: false, timestamp: now),
      ],
      lastUpdate: now,
    );
  }
}
