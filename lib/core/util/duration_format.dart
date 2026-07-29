/// Compact duration formatting for metrics and wait times.
///
/// Kept out of the widgets so the same seconds render identically on the
/// dashboard, in the queue and on agent detail.
abstract final class DurationFormat {
  /// "2m 14s", "45s", "1h 6m". Zero renders as "0s" rather than an empty
  /// string, so a stat card never looks like it failed to load.
  static String compact(int seconds) {
    if (seconds <= 0) return '0s';

    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int secs = seconds % 60;

    if (hours > 0) return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    if (minutes > 0) return secs > 0 ? '${minutes}m ${secs}s' : '${minutes}m';
    return '${secs}s';
  }

  /// Coarser form for "waiting 8m" style labels — never shows seconds once
  /// past a minute, because a queue row that ticks every second is noise.
  static String coarse(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final int minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m';
    final int hours = minutes ~/ 60;
    if (hours < 24) return '${hours}h';
    return '${hours ~/ 24}d';
  }
}
