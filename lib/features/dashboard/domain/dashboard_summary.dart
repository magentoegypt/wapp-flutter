/// Dashboard payload — the shape is pinned by the Figma frame (38:1032):
/// four stat cards, a seven-day bar chart, and the agent's queue.
class DashboardSummary {
  const DashboardSummary({
    required this.open,
    required this.resolvedToday,
    required this.avgResponseSeconds,
    required this.csatPercent,
    required this.week,
    required this.queue,
  });

  final int open;
  final int resolvedToday;

  /// Seconds; the UI formats to "2m 14s".
  final int avgResponseSeconds;

  /// Already a percentage, 0–100.
  ///
  /// The backend stores `agent_quality_reviews.score` on a 1–5 scale, so
  /// whoever builds `GET /dashboard` must convert (`avg / 5 * 100`) rather than
  /// passing the raw average through — a 4.7 rendered into a "%" slot is a
  /// silent, plausible-looking bug.
  final int csatPercent;

  final List<DayCount> week;
  final List<QueueItem> queue;

  static const DashboardSummary empty = DashboardSummary(
    open: 0,
    resolvedToday: 0,
    avgResponseSeconds: 0,
    csatPercent: 0,
    week: <DayCount>[],
    queue: <QueueItem>[],
  );
}

class DayCount {
  const DayCount({required this.weekday, required this.count});

  /// 1 = Monday … 7 = Sunday, matching DateTime.
  final int weekday;
  final int count;
}

class QueueItem {
  const QueueItem({
    required this.contactUid,
    required this.name,
    required this.waitingSeconds,
  });

  final String contactUid;
  final String name;
  final int waitingSeconds;
}
