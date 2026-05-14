import 'package:intl/intl.dart';

/// Lightweight relative-time helper. We avoid pulling timeago_flutter to keep
/// the dependency tree small and predictable.
String relativeTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(t);
  if (diff.inSeconds < 5) return 'just now';
  if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('MMM d').format(t);
}

String absoluteTime(DateTime t) => DateFormat('HH:mm').format(t);
String absoluteDate(DateTime t) => DateFormat('EEE, MMM d').format(t);
String absoluteFull(DateTime t) => DateFormat('MMM d, HH:mm').format(t);
