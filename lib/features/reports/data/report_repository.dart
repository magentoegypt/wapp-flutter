import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/reports.dart';

/// The four reporting endpoints.
///
/// All reads. Nothing here writes, which makes this the one module that can be
/// verified end-to-end against production without touching a customer.
///
/// Every mapper is deliberately total: an unrecognised payload yields an empty
/// report, never an exception. The screens then say "no data for this window",
/// which is honest — but it is also exactly how a key-name mistake hides, so
/// each mapper below states which key it reads and `report_shape_test.dart`
/// pins it against a fixture captured from the real API.
abstract interface class ReportRepository {
  Future<ConversationalReport> conversational({
    ReportWindow? window,
    String? range,
    String? agentUid,
  });

  Future<PauseReasonReport> pauseReasons({DateTime? from, DateTime? to});

  Future<QualityReport> qualityReviews({DateTime? from, DateTime? to});

  Future<AgentTargetsReport> agentTargets({int? year, int? month});
}

class ReportRepositoryImpl implements ReportRepository {
  const ReportRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<ConversationalReport> conversational({
    ReportWindow? window,
    String? range,
    String? agentUid,
  }) async {
    // `date` accepts either a window code or "YYYY-MM-DD to YYYY-MM-DD", and
    // the server 422s on anything else. A custom range wins when both are set,
    // because the user picked specific dates and a code would silently widen
    // them back out.
    final Map<String, dynamic> q = <String, dynamic>{};
    if (range != null && range.isNotEmpty) {
      q['date'] = range;
    } else if (window != null) {
      q['date'] = window.code;
    }
    if (agentUid != null && agentUid.isNotEmpty) q['agent'] = agentUid;

    final dynamic body = await _api.get('/reports/conversational', query: q);
    return conversationalFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<PauseReasonReport> pauseReasons({DateTime? from, DateTime? to}) async {
    final dynamic body = await _api.get(
      '/reports/pause-reasons',
      query: _window(from, to),
    );
    return pauseReasonsFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<QualityReport> qualityReviews({DateTime? from, DateTime? to}) async {
    final dynamic body = await _api.get(
      '/reports/quality-reviews',
      query: _window(from, to),
    );
    return qualityFromJson(body as Map<String, dynamic>);
  }

  @override
  Future<AgentTargetsReport> agentTargets({int? year, int? month}) async {
    final dynamic body = await _api.get(
      '/reports/agent-targets',
      query: <String, dynamic>{
        if (year != null) 'year': year,
        if (month != null) 'month': month,
      },
    );
    return agentTargetsFromJson(body as Map<String, dynamic>);
  }

  /// `from`/`to` are date-only. Sending an ISO timestamp fails the server's
  /// `^\d{4}-\d{2}-\d{2}$` check with a 422 that names the field, so the date
  /// is truncated here rather than discovered at runtime.
  Map<String, dynamic> _window(DateTime? from, DateTime? to) =>
      <String, dynamic>{
        if (from != null) 'from': _ymd(from),
        if (to != null) 'to': _ymd(to),
      };
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

// ─────────────────────────────────────────── shared coercion

num _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;

int _int(Object? v) => v is num ? v.round() : int.tryParse('${v ?? ''}') ?? 0;

/// Null-preserving. Used for target columns, where "not set" and "set to zero"
/// are different facts and collapsing them would show an unset target as one
/// the agent has already met.
num? _numOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v;
  final String s = '$v'.trim();
  if (s.isEmpty) return null;
  return num.tryParse(s);
}

/// The report body, wherever it sits.
///
/// All four endpoints answer `{success: true, report: {...}}` — a flat envelope,
/// not the domain-key one used elsewhere in this API. The fallback to the root
/// exists so a later tidy-up that hoists the fields cannot blank every screen
/// in this module at once.
Map<String, dynamic> _body(Map<String, dynamic> json) =>
    (json['report'] as Map<String, dynamic>?) ?? json;

// ─────────────────────────────────────────── conversational

ConversationalReport conversationalFromJson(Map<String, dynamic> json) {
  final Map<String, dynamic> r = _body(json);

  return ConversationalReport(
    received: _metric(r, 'allRead'),
    avgWaitMinutes: _metric(r, 'avWaitTime'),
    opened: _metric(r, 'opConvs'),
    closed: _metric(r, 'clsConvs'),
    newCustomers: _int(r['newCustomers']),
    returningCustomers: _int(r['returningCustomers']),
    totalConversations: _int(r['allConv']),
    missed: _int(r['missed']),
    chatTransfers: _int(r['chatTransfer']),
    chatDurationSeconds: _int(r['chatDuration']),
    receivedTrend: _trend(r['allReadList']),
    openedTrend: _trend(r['opConvsList']),
    closedTrend: _trend(r['clsConvsList']),
    waitTrend: _trend(r['avWaitTimeList']),
    conversationsPerAgent: _series(r['convPerAgent']),
    responseTimePerAgent: _series(r['resTimePerAgent']),
    firstResponsePerAgent: _series(r['firstTimePerAgent']),
    messagesPerAgent: _series(r['noMsgPerAgent']),
    window: ReportWindowCode.fromCode(json['window'] as String?),
    agents: _agents(json['agents']),
  );
}

/// A figure and its `…Old` twin.
///
/// The suffix is a misnomer inherited from the console: the engine already ran
/// `percentageDifference(previous, current)` before serialising, so `allReadOld`
/// is a **signed percent change**, not the previous period's value. Treating it
/// as the latter would render "40" beside a current 55 and imply a comparison
/// that was never made.
ReportMetric _metric(Map<String, dynamic> r, String key) {
  final Object? delta = r['${key}Old'];
  return ReportMetric(
    value: _num(r[key]),
    changePercent: delta == null ? null : _int(delta),
  );
}

/// The trend lists share the chart shape `{xData: [...], yData: [...]}`.
List<TrendPoint> _trend(Object? raw) {
  final AgentSeries s = _series(raw);
  return s.rows
      .map((AgentSeriesRow r) => TrendPoint(label: r.name, value: r.value))
      .toList(growable: false);
}

/// Zips the API's two parallel arrays back into rows.
///
/// This is the shape that silently yields nothing if read as a list: the
/// console feeds `xData`/`yData` straight to a chart library, so the payload
/// never had rows to begin with. A list is still accepted as a fallback in case
/// a later revision normalises it, but that is not what arrives today.
///
/// Lengths are clamped to the shorter array rather than padded — a name with a
/// fabricated zero beside it is worse than an absent row, because it reads as a
/// measured result.
AgentSeries _series(Object? raw) {
  if (raw is List) {
    final List<AgentSeriesRow> rows = <AgentSeriesRow>[];
    for (final Object? e in raw) {
      if (e is! Map) continue;
      final String name = '${e['name'] ?? e['label'] ?? e['x'] ?? ''}';
      if (name.isEmpty) continue;
      rows.add(AgentSeriesRow(
        name: name,
        value: _num(e['value'] ?? e['y'] ?? e['count']),
      ));
    }
    return AgentSeries(rows);
  }

  if (raw is! Map) return AgentSeries.empty;

  final Object? xs = raw['xData'];
  final Object? ys = raw['yData'];
  if (xs is! List || ys is! List) return AgentSeries.empty;

  final int n = xs.length < ys.length ? xs.length : ys.length;
  final List<AgentSeriesRow> rows = <AgentSeriesRow>[];
  for (int i = 0; i < n; i++) {
    final String name = '${xs[i] ?? ''}';
    if (name.isEmpty) continue;
    rows.add(AgentSeriesRow(name: name, value: _num(ys[i])));
  }
  return AgentSeries(rows);
}

List<ReportAgent> _agents(Object? raw) {
  if (raw is! List) return const <ReportAgent>[];
  final List<ReportAgent> out = <ReportAgent>[];
  for (final Object? e in raw) {
    if (e is! Map) continue;
    final String uid = '${e['uid'] ?? ''}';
    if (uid.isEmpty) continue;
    out.add(ReportAgent(uid: uid, name: '${e['name'] ?? ''}'));
  }
  return out;
}

// ─────────────────────────────────────────── pause reasons

PauseReasonReport pauseReasonsFromJson(Map<String, dynamic> json) {
  final Map<String, dynamic> r = _body(json);
  final Map<String, dynamic> grand =
      (r['grand'] as Map<String, dynamic>?) ?? const <String, dynamic>{};

  return PauseReasonReport(
    agents: _list(r['agents'], _pauseAgent),
    reasonTotals: _list(r['reasonTotals'], _reasonTotal),
    grandSeconds: _int(grand['seconds']),
    grandSessions: _int(grand['sessions']),
    grandHuman: '${grand['human'] ?? '0m'}',
  );
}

PauseAgent _pauseAgent(Map<Object?, Object?> e) => PauseAgent(
      name: '${e['name'] ?? ''}',
      rows: _list(e['rows'], _pauseRow),
      totalSeconds: _int(e['total_seconds']),
      sessions: _int(e['sessions']),
      totalHuman: '${e['total_human'] ?? '0m'}',
    );

PauseRow _pauseRow(Map<Object?, Object?> e) => PauseRow(
      // `label` is the reason, already capitalised, falling back to the status
      // server-side. Reading `reason` instead would be blank on every row that
      // came from a plain away/busy toggle with no reason attached.
      label: '${e['label'] ?? ''}',
      status: '${e['status'] ?? ''}',
      sessions: _int(e['sessions']),
      totalSeconds: _int(e['total_seconds']),
      totalHuman: '${e['total_human'] ?? '0m'}',
    );

PauseReasonTotal _reasonTotal(Map<Object?, Object?> e) => PauseReasonTotal(
      label: '${e['label'] ?? ''}',
      seconds: _int(e['seconds']),
      human: '${e['human'] ?? '0m'}',
    );

// ─────────────────────────────────────────── quality reviews

QualityReport qualityFromJson(Map<String, dynamic> json) {
  final Map<String, dynamic> r = _body(json);
  final Object? avg = r['avgScore'];

  return QualityReport(
    agents: _list(r['agents'], _qualityAgent),
    recent: _list(r['recent'], _qualityReview),
    totalReviews: _int(r['totalReviews']),
    // Null when the window held no reviews. Coercing to 0.0 would put "0.0" on
    // the screen as though every agent had been reviewed and scored nothing.
    averageScore: avg == null ? null : _num(avg).toDouble(),
  );
}

QualityAgent _qualityAgent(Map<Object?, Object?> e) => QualityAgent(
      name: '${e['name'] ?? ''}',
      reviews: _int(e['reviews']),
      averageScore: _num(e['avg_score']).toDouble(),
    );

QualityReview _qualityReview(Map<Object?, Object?> e) {
  // Both name pairs fall back to the username, exactly as the server does when
  // an account has no first/last name — otherwise a review shows a blank author.
  String person(String nameKey, String userKey) {
    final String n = '${e[nameKey] ?? ''}'.trim();
    return n.isNotEmpty ? n : '${e[userKey] ?? ''}'.trim();
  }

  return QualityReview(
    agentName: person('agent_name', 'agent_username'),
    reviewerName: person('reviewer_name', 'reviewer_username'),
    score: _num(e['score']).toDouble(),
    comment: '${e['comment'] ?? ''}',
    createdAt: DateTime.tryParse('${e['created_at'] ?? ''}')?.toLocal(),
  );
}

// ─────────────────────────────────────────── agent targets

AgentTargetsReport agentTargetsFromJson(Map<String, dynamic> json) {
  final Map<String, dynamic> r = _body(json);

  return AgentTargetsReport(
    rows: _list(r['rows'], _targetRow),
    year: _int(r['year']),
    month: _int(r['month']),
    monthLabel: '${r['monthLabel'] ?? ''}',
  );
}

AgentTargetRow _targetRow(Map<Object?, Object?> e) {
  final String uid = '${e['user_uid'] ?? ''}';
  return AgentTargetRow(
    name: '${e['name'] ?? ''}',
    agentUid: uid.isEmpty ? null : uid,
    targets: _targetSet(e['targets']),
    actuals: _targetSet(e['actuals']),
  );
}

/// Targets keep their nulls; actuals are counted values and a missing one
/// genuinely is zero. The asymmetry is intentional and is the whole reason
/// [_numOrNull] exists.
TargetSet _targetSet(Object? raw) {
  if (raw is! Map) return const TargetSet();
  return TargetSet(
    leads: _numOrNull(raw['leads']),
    orders: _numOrNull(raw['orders']),
    revenue: _numOrNull(raw['revenue']),
    responseTime: _numOrNull(raw['response_time']),
    csat: _numOrNull(raw['csat']),
  );
}

// ─────────────────────────────────────────── list helper

List<T> _list<T>(Object? raw, T Function(Map<Object?, Object?>) map) {
  if (raw is! List) return <T>[];
  final List<T> out = <T>[];
  for (final Object? e in raw) {
    if (e is Map) out.add(map(e));
  }
  return out;
}

// ─────────────────────────────────────────── providers

final reportRepositoryProvider = Provider<ReportRepository>(
  (Ref ref) => ReportRepositoryImpl(ref.watch(apiClientProvider)),
);

/// The conversational report's filter state, held outside the future so
/// changing a chip refetches without rebuilding the whole screen's identity.
class ConversationalQuery {
  const ConversationalQuery({this.window = ReportWindow.month, this.agentUid});

  final ReportWindow window;
  final String? agentUid;

  ConversationalQuery copyWith({ReportWindow? window, Object? agentUid = _keep}) =>
      ConversationalQuery(
        window: window ?? this.window,
        agentUid: agentUid == _keep ? this.agentUid : agentUid as String?,
      );

  /// Sentinel so `agentUid: null` can mean "clear the filter" rather than
  /// "leave it alone" — the usual copyWith ambiguity, and here the two
  /// readings differ by a whole workspace of data.
  static const Object _keep = Object();

  @override
  bool operator ==(Object other) =>
      other is ConversationalQuery &&
      other.window == window &&
      other.agentUid == agentUid;

  @override
  int get hashCode => Object.hash(window, agentUid);
}

final conversationalQueryProvider =
    StateProvider<ConversationalQuery>((Ref ref) => const ConversationalQuery());

final conversationalReportProvider =
    FutureProvider.autoDispose<ConversationalReport>((Ref ref) {
  final ConversationalQuery q = ref.watch(conversationalQueryProvider);
  return ref.watch(reportRepositoryProvider).conversational(
        window: q.window,
        agentUid: q.agentUid,
      );
});

/// A from/to window shared by the two range-scoped reports. Defaults to the
/// last 30 days to match what the server would pick anyway, so the chips on
/// screen always describe the data being shown.
class DateWindow {
  const DateWindow({required this.from, required this.to});

  factory DateWindow.lastDays(int days, {DateTime? now}) {
    final DateTime end = now ?? DateTime.now();
    return DateWindow(
      from: DateTime(end.year, end.month, end.day).subtract(Duration(days: days)),
      to: end,
    );
  }

  final DateTime from;
  final DateTime to;

  int get days => to.difference(from).inDays;

  @override
  bool operator ==(Object other) =>
      other is DateWindow && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

final pauseWindowProvider =
    StateProvider<DateWindow>((Ref ref) => DateWindow.lastDays(30));

final pauseReasonsProvider =
    FutureProvider.autoDispose<PauseReasonReport>((Ref ref) {
  final DateWindow w = ref.watch(pauseWindowProvider);
  return ref
      .watch(reportRepositoryProvider)
      .pauseReasons(from: w.from, to: w.to);
});

final qualityWindowProvider =
    StateProvider<DateWindow>((Ref ref) => DateWindow.lastDays(30));

final qualityReviewsProvider =
    FutureProvider.autoDispose<QualityReport>((Ref ref) {
  final DateWindow w = ref.watch(qualityWindowProvider);
  return ref
      .watch(reportRepositoryProvider)
      .qualityReviews(from: w.from, to: w.to);
});

/// Year and month, as a single value so one change triggers one fetch.
class TargetMonth {
  const TargetMonth(this.year, this.month);

  factory TargetMonth.current({DateTime? now}) {
    final DateTime d = now ?? DateTime.now();
    return TargetMonth(d.year, d.month);
  }

  final int year;
  final int month;

  /// Steps by whole months, carrying the year. Clamped nowhere — the server
  /// validates 2000–2100 and answers 422 outside it.
  TargetMonth shift(int months) {
    final int zero = year * 12 + (month - 1) + months;
    return TargetMonth(zero ~/ 12, zero % 12 + 1);
  }

  @override
  bool operator ==(Object other) =>
      other is TargetMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

final targetMonthProvider =
    StateProvider<TargetMonth>((Ref ref) => TargetMonth.current());

final agentTargetsProvider =
    FutureProvider.autoDispose<AgentTargetsReport>((Ref ref) {
  final TargetMonth m = ref.watch(targetMonthProvider);
  return ref
      .watch(reportRepositoryProvider)
      .agentTargets(year: m.year, month: m.month);
});
