/// The four reports behind the dashboard, modelled on what the API actually
/// returns.
///
/// Shapes were read from the backend rather than inferred: `ReportApiController`
/// and the four engine helpers it wraps (`ReportEngine::conversationalReportData`
/// and `::pauseReasonReport`, `AgentQualityReviewEngine::qualityReport`,
/// `AgentTargetEngine::targetsReport`). That matters more here than usual,
/// because these four helpers do **not** share a shape — the controller's own
/// header warns about it — and every mismatch in this app so far has failed the
/// same silent way: a key that is never sent reads as null, the mapper takes its
/// "no data" branch, and the screen reports an empty week over real traffic.
///
/// The three traps in these particular payloads:
///
///  1. **Per-agent metrics are parallel arrays, not rows.** The conversational
///     report sends `{xData: [names], yData: [values]}` because the console
///     hands them straight to a chart library. Read as a list of objects they
///     yield nothing, with no error. [AgentSeries] zips them back into rows.
///  2. **`…Old` fields are already percentages, not previous values.** The
///     engine runs `percentageDifference()` before serialising, so `allReadOld`
///     is a signed percent delta. Rendering it as "last period: 40" would be a
///     plausible-looking lie.
///  3. **The date contract differs per report** — deliberately, so an app
///     figure always matches the console's. Conversational takes a window code
///     or a range string, pause-reasons and quality-reviews take from/to, and
///     agent-targets takes year/month. They are not unified here either.
library;

// ─────────────────────────────────────────── conversational

/// The window codes `resolveDateWindows()` understands. Anything else the
/// server rejects with 422, so the picker only ever offers these four and the
/// custom range.
enum ReportWindow { day, week, month, year }

extension ReportWindowCode on ReportWindow {
  /// The single letter the API expects. Sent verbatim as `?date=`.
  String get code => switch (this) {
    ReportWindow.day => 'D',
    ReportWindow.week => 'W',
    ReportWindow.month => 'M',
    ReportWindow.year => 'Y',
  };

  static ReportWindow fromCode(String? c) => switch (c) {
    'D' => ReportWindow.day,
    'W' => ReportWindow.week,
    'Y' => ReportWindow.year,
    _ => ReportWindow.month,
  };
}

/// A headline figure paired with its change against the previous period.
///
/// [changePercent] is a **signed percentage**, not the previous value — see the
/// library note. It is nullable because a report that omits the `…Old` key
/// should render the figure with no delta rather than a confident "0%", which
/// would claim the metric held steady when in truth nothing was compared.
class ReportMetric {
  const ReportMetric({required this.value, this.changePercent});

  final num value;
  final int? changePercent;

  bool get isUp => (changePercent ?? 0) > 0;
  bool get isDown => (changePercent ?? 0) < 0;
  bool get hasChange => changePercent != null && changePercent != 0;
}

/// One point of a trend line. The API labels days as "3 August" (MySQL
/// `%e %M`), already localised by neither side — it is a display string, not a
/// date, so it is kept as text rather than parsed and reformatted.
class TrendPoint {
  const TrendPoint({required this.label, required this.value});

  final String label;
  final num value;
}

/// A per-agent breakdown, rebuilt from the API's parallel `xData`/`yData`.
///
/// The two arrays are positionally paired. If they ever disagree in length the
/// shorter one wins, because inventing a zero for a missing agent would put a
/// name on the screen with a number that was never measured.
class AgentSeries {
  const AgentSeries(this.rows);

  final List<AgentSeriesRow> rows;

  static const AgentSeries empty = AgentSeries(<AgentSeriesRow>[]);

  bool get isEmpty => rows.isEmpty;

  /// Largest value, for scaling bars. Zero when empty so callers can divide
  /// defensively without a special case.
  num get max =>
      rows.isEmpty ? 0 : rows.map((AgentSeriesRow r) => r.value).reduce((num a, num b) => a > b ? a : b);
}

class AgentSeriesRow {
  const AgentSeriesRow({required this.name, required this.value});

  final String name;
  final num value;
}

/// `GET /reports/conversational`.
class ConversationalReport {
  const ConversationalReport({
    this.received = const ReportMetric(value: 0),
    this.avgWaitMinutes = const ReportMetric(value: 0),
    this.opened = const ReportMetric(value: 0),
    this.closed = const ReportMetric(value: 0),
    this.newCustomers = 0,
    this.returningCustomers = 0,
    this.totalConversations = 0,
    this.missed = 0,
    this.chatTransfers = 0,
    this.chatDurationSeconds = 0,
    this.receivedTrend = const <TrendPoint>[],
    this.openedTrend = const <TrendPoint>[],
    this.closedTrend = const <TrendPoint>[],
    this.waitTrend = const <TrendPoint>[],
    this.conversationsPerAgent = AgentSeries.empty,
    this.responseTimePerAgent = AgentSeries.empty,
    this.firstResponsePerAgent = AgentSeries.empty,
    this.messagesPerAgent = AgentSeries.empty,
    this.window = ReportWindow.month,
    this.agents = const <ReportAgent>[],
  });

  /// Inbound messages received. `allRead` in the payload — named for what it
  /// counts, not for the column it came from.
  final ReportMetric received;

  /// Mean customer wait, **in minutes** (`cntAvgWaitingTime` is minute-based,
  /// unlike the dashboard's `avgFirstResponseSeconds`). Mixing the two units up
  /// would be off by 60× and still look like a believable number.
  final ReportMetric avgWaitMinutes;

  final ReportMetric opened;
  final ReportMetric closed;

  final int newCustomers;
  final int returningCustomers;
  final int totalConversations;

  /// Conversations nobody answered.
  final int missed;

  /// Bot-to-agent handovers.
  final int chatTransfers;

  final int chatDurationSeconds;

  final List<TrendPoint> receivedTrend;
  final List<TrendPoint> openedTrend;
  final List<TrendPoint> closedTrend;
  final List<TrendPoint> waitTrend;

  final AgentSeries conversationsPerAgent;
  final AgentSeries responseTimePerAgent;
  final AgentSeries firstResponsePerAgent;
  final AgentSeries messagesPerAgent;

  /// Echoed by the server, so the chips show what was actually applied rather
  /// than what was asked for.
  final ReportWindow window;

  /// The agent filter's options, returned alongside the report so the screen
  /// needs one call rather than two.
  final List<ReportAgent> agents;
}

class ReportAgent {
  const ReportAgent({required this.uid, required this.name});

  final String uid;
  final String name;
}

// ─────────────────────────────────────────── pause reasons

/// `GET /reports/pause-reasons` — time each agent spent away or busy.
///
/// ⚠ These rows carry **no identifier at all** — not a uid, not even an id. The
/// backend aggregates by user but only serialises the display name, so an agent
/// here cannot be linked to their profile. That is inherited from the console
/// report and is a real limitation, not an omission in the mapper.
class PauseReasonReport {
  const PauseReasonReport({
    this.agents = const <PauseAgent>[],
    this.reasonTotals = const <PauseReasonTotal>[],
    this.grandSeconds = 0,
    this.grandSessions = 0,
    this.grandHuman = '0m',
  });

  final List<PauseAgent> agents;
  final List<PauseReasonTotal> reasonTotals;
  final int grandSeconds;
  final int grandSessions;

  /// The server's own "2h 5m" rendering. Preferred over reformatting locally so
  /// the app and console never disagree by a rounding rule.
  final String grandHuman;

  bool get isEmpty => agents.isEmpty && reasonTotals.isEmpty;
}

class PauseAgent {
  const PauseAgent({
    required this.name,
    this.rows = const <PauseRow>[],
    this.totalSeconds = 0,
    this.sessions = 0,
    this.totalHuman = '0m',
  });

  final String name;
  final List<PauseRow> rows;
  final int totalSeconds;
  final int sessions;
  final String totalHuman;
}

class PauseRow {
  const PauseRow({
    required this.label,
    this.status = '',
    this.sessions = 0,
    this.totalSeconds = 0,
    this.totalHuman = '0m',
  });

  /// Already capitalised by the server, and falls back to the status when the
  /// event carried no reason.
  final String label;
  final String status;
  final int sessions;
  final int totalSeconds;
  final String totalHuman;
}

class PauseReasonTotal {
  const PauseReasonTotal({
    required this.label,
    this.seconds = 0,
    this.human = '0m',
  });

  final String label;
  final int seconds;
  final String human;
}

// ─────────────────────────────────────────── quality reviews

/// `GET /reports/quality-reviews` — **internal manager reviews**, not customer
/// CSAT. The distinction is worth keeping in the UI copy: an agent seeing "3.5"
/// should know whether their manager or their customers said it.
class QualityReport {
  const QualityReport({
    this.agents = const <QualityAgent>[],
    this.recent = const <QualityReview>[],
    this.totalReviews = 0,
    this.averageScore,
  });

  final List<QualityAgent> agents;

  /// The 20 most recent reviews, newest first — the server's limit, not ours.
  final List<QualityReview> recent;

  final int totalReviews;

  /// Null when nothing was reviewed in the window. Deliberately nullable: a
  /// displayed 0.0 would read as "everyone scored zero" rather than "no reviews
  /// were written".
  final double? averageScore;

  bool get isEmpty => totalReviews == 0 && agents.isEmpty;
}

/// ⚠ Like [PauseAgent], these rows have no uid. The API strips the internal
/// `user_id` and this particular engine never selected a `_uid` to replace it,
/// so the agent cannot be linked to their profile from here.
class QualityAgent {
  const QualityAgent({
    required this.name,
    this.reviews = 0,
    this.averageScore = 0,
  });

  final String name;
  final int reviews;
  final double averageScore;
}

class QualityReview {
  const QualityReview({
    required this.agentName,
    this.reviewerName = '',
    this.score = 0,
    this.comment = '',
    this.createdAt,
  });

  final String agentName;
  final String reviewerName;
  final double score;
  final String comment;
  final DateTime? createdAt;
}

// ─────────────────────────────────────────── agent targets

/// `GET /reports/agent-targets` — targets vs actuals for one calendar month.
///
/// The only report here scoped to a month rather than a range, matching the
/// console. Every agent appears whether or not a target was set for them.
class AgentTargetsReport {
  const AgentTargetsReport({
    this.rows = const <AgentTargetRow>[],
    this.year = 0,
    this.month = 0,
    this.monthLabel = '',
  });

  final List<AgentTargetRow> rows;
  final int year;
  final int month;

  /// The server's "August 2026". Used as-is rather than rebuilt from
  /// year/month, so the report header cannot disagree with the data it heads.
  final String monthLabel;

  bool get isEmpty => rows.isEmpty;
}

/// One agent's month. This report **does** carry `user_uid`, so unlike the
/// other two its rows can link through to the agent.
class AgentTargetRow {
  const AgentTargetRow({
    required this.name,
    this.agentUid,
    this.targets = const TargetSet(),
    this.actuals = const TargetSet(),
  });

  final String name;
  final String? agentUid;
  final TargetSet targets;
  final TargetSet actuals;

  /// True when no target of any kind was set for this agent this month, so the
  /// row can be shown as "no target" instead of five "0 of —" lines.
  bool get hasNoTargets =>
      targets.leads == null &&
      targets.orders == null &&
      targets.revenue == null &&
      targets.responseTime == null &&
      targets.csat == null;
}

/// The five tracked measures. Every field is nullable on the target side
/// because an unset target is a real and common state — `AgentTargetModel`
/// returns null for each column that was never filled in, and a null target
/// must not be drawn as a zero one that the agent has already "met".
class TargetSet {
  const TargetSet({
    this.leads,
    this.orders,
    this.revenue,
    this.responseTime,
    this.csat,
  });

  final num? leads;
  final num? orders;
  final num? revenue;

  /// Minutes. Lower is better — the only measure here where progress runs
  /// downward, which the screen has to invert when it colours attainment.
  final num? responseTime;

  final num? csat;
}
