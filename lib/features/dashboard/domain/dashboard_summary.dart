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
    this.agentQueue = const <AgentWorkload>[],
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

  /// Open conversations per agent across the workspace.
  final List<AgentWorkload> agentQueue;

  static const DashboardSummary empty = DashboardSummary();
}

/// One bar of the weekly chart.
///
/// The API sends a day as `{date, inbound, outbound}` — **not** a single
/// `count`. Reading a `count` that is never sent parsed every day as zero, so
/// the chart reported a silent week over a week that had traffic. Both halves
/// are kept and [count] is their sum, so nothing is invented and the frame's
/// single-series bar still has a number to draw.
class DaySeriesPoint {
  const DaySeriesPoint({
    required this.date,
    this.inbound = 0,
    this.outbound = 0,
  });

  final DateTime date;
  final int inbound;
  final int outbound;

  int get count => inbound + outbound;
}

/// One agent's open workload.
///
/// Named for what it is. `agentQueue` returns `{uid, name, openConversations}`
/// — a per-agent count, not the signed-in agent's conversations. It was read as
/// a conversation list, so the rows showed agent names with a blank subtitle
/// and, worse, tapping one pushed `/chats/<agent-uid>`: a conversation route
/// carrying a uid no conversation has.
class AgentWorkload {
  const AgentWorkload({
    required this.agentUid,
    required this.name,
    this.openConversations = 0,
  });

  final String agentUid;
  final String name;
  final int openConversations;
}
