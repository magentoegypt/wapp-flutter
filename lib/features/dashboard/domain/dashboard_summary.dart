/// Dashboard metrics, as the API actually provides them under `stats`.
///
/// This deliberately does **not** match the Figma frame (38:1032), which asked
/// for Resolved today / Avg. response / CSAT plus a seven-day chart and an
/// agent queue. None of those are exposed by `GET /dashboard` — the backend
/// computes CSAT and response time per agent in `AgentTargetEngine` but does
/// not surface them here, and there is no weekly series or queue endpoint.
///
/// Rather than render four cards that are permanently zero, the screen is
/// built around the eight metrics that do exist. Restore the designed layout
/// if and when the API grows those fields.
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

  static const DashboardSummary empty = DashboardSummary();
}
