/// Dashboard metrics, as the API actually provides them under `stats`.
///
/// Built around what `GET /dashboard` actually returns.
///
/// The 30 Jul API pass added `avgFirstResponseSeconds`, `series7d` and
/// `agentQueue`, so the frame's weekly chart and "My queue" list are now real
/// and are rendered. `resolvedToday` and CSAT are still absent and deliberately
/// so — nothing records *when* a conversation was resolved, and CSAT is not
/// collected, so a card for either would be permanently zero.
class DashboardSummary {
  const DashboardSummary({
    this.openConversations = 0,
    this.unassigned = 0,
    this.assigned = 0,
    this.totalContacts = 0,
    this.newContactsToday = 0,
    this.inboundToday = 0,
    this.outboundToday = 0,
    this.queued = 0,
    this.avgFirstResponseSeconds = 0,
    this.series7d = const <DaySeriesPoint>[],
    this.agentQueue = const <QueueEntry>[],
  });

  /// Threads currently open across the workspace.
  final int openConversations;

  /// Open threads with no agent — the most actionable number on the screen.
  final int unassigned;

  final int assigned;
  final int totalContacts;
  final int newContactsToday;
  final int inboundToday;
  final int outboundToday;

  /// Messages waiting in the send queue.
  final int queued;

  /// Mean first response across the window, in seconds.
  final int avgFirstResponseSeconds;

  /// Seven days of conversation volume, oldest first. Empty when the API sends
  /// nothing recognisable, in which case the chart is not drawn at all — an
  /// all-zero chart would read as "a quiet week" rather than "no data".
  final List<DaySeriesPoint> series7d;

  /// Conversations assigned to the signed-in agent.
  final List<QueueEntry> agentQueue;

  static const DashboardSummary empty = DashboardSummary();
}

/// One bar of the weekly chart.
class DaySeriesPoint {
  const DaySeriesPoint({required this.date, required this.count});

  final DateTime date;
  final int count;
}

/// One row of "My queue".
class QueueEntry {
  const QueueEntry({
    required this.contactUid,
    required this.name,
    this.lastMessage,
    this.unreadCount = 0,
  });

  final String contactUid;
  final String name;
  final String? lastMessage;
  final int unreadCount;
}
