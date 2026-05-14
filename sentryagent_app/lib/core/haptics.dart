import 'package:flutter/services.dart';

/// Centralised haptic feedback so the whole app speaks the same physical
/// language. Any new interaction should pick a level from here, never call
/// [HapticFeedback] directly.
///
/// Levels (lightest → heaviest):
///   tap     — secondary buttons, chip presses, tab switch
///   select  — primary buttons, sensor tile open, send chat
///   confirm — arm/disarm, decision opened
///   warning — threat level moves to WARNING
///   alert   — threat level moves to ALERT (or test-siren engaged)
class Haptics {
  Haptics._();

  static Future<void> tap() => HapticFeedback.selectionClick();
  static Future<void> select() => HapticFeedback.lightImpact();
  static Future<void> confirm() => HapticFeedback.mediumImpact();
  static Future<void> warning() => HapticFeedback.mediumImpact();
  static Future<void> alert() => HapticFeedback.heavyImpact();
}
