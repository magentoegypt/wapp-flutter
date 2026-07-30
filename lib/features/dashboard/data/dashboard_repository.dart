import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/dashboard_summary.dart';

abstract interface class DashboardRepository {
  Future<DashboardSummary> fetch();
}

class DashboardRepositoryImpl implements DashboardRepository {
  const DashboardRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<DashboardSummary> fetch() async {
    final dynamic body = await _api.get('/dashboard');
    return dashboardFromJson(body as Map<String, dynamic>);
  }
}

/// Reads the `{success, stats: {...}}` envelope. Tolerates the metrics being
/// hoisted to the top level, so a later API tidy-up doesn't blank the screen.
DashboardSummary dashboardFromJson(Map<String, dynamic> json) {
  final Map<String, dynamic> s =
      (json['stats'] as Map<String, dynamic>?) ?? json;

  int asInt(Object? v) => v is num ? v.round() : int.tryParse('${v ?? ''}') ?? 0;

  return DashboardSummary(
    openConversations: asInt(s['openConversations']),
    unassigned: asInt(s['unassigned']),
    assigned: asInt(s['assigned']),
    totalContacts: asInt(s['totalContacts']),
    newContactsToday: asInt(s['newContactsToday']),
    inboundToday: asInt(s['inboundToday']),
    outboundToday: asInt(s['outboundToday']),
    queued: asInt(s['queued']),
    avgFirstResponseSeconds: asInt(
      s['avgFirstResponseSeconds'] ?? json['avgFirstResponseSeconds'],
    ),
    // series7d and agentQueue sit beside `stats` in some shapes and inside it
    // in others; both are read tolerantly and simply stay empty if neither
    // matches, so an unexpected shape hides a section rather than crashing it.
    series7d: _series(json['series7d'] ?? s['series7d']),
    agentQueue: _queue(json['agentQueue'] ?? s['agentQueue']),
  );
}

List<DaySeriesPoint> _series(Object? raw) {
  if (raw is! List) return const <DaySeriesPoint>[];
  final List<DaySeriesPoint> out = <DaySeriesPoint>[];
  for (final Object? e in raw) {
    if (e is! Map) continue;
    final DateTime? day =
        DateTime.tryParse('${e['date'] ?? e['day'] ?? ''}')?.toLocal();
    if (day == null) continue;
    final Object? v = e['count'] ?? e['total'] ?? e['conversations'] ?? e['value'];
    out.add(DaySeriesPoint(
      date: day,
      count: v is num ? v.round() : int.tryParse('${v ?? ''}') ?? 0,
    ));
  }
  out.sort((DaySeriesPoint a, DaySeriesPoint b) => a.date.compareTo(b.date));
  return out;
}

List<QueueEntry> _queue(Object? raw) {
  if (raw is! List) return const <QueueEntry>[];
  final List<QueueEntry> out = <QueueEntry>[];
  for (final Object? e in raw) {
    if (e is! Map) continue;
    final String uid = '${e['contactUid'] ?? e['uid'] ?? ''}';
    if (uid.isEmpty) continue;
    final Object? unread = e['unread'] ?? e['unreadCount'];
    out.add(QueueEntry(
      contactUid: uid,
      name: '${e['name'] ?? e['waId'] ?? ''}',
      lastMessage: (e['lastMessage'] ?? e['last_message']) as String?,
      unreadCount:
          unread is num ? unread.round() : int.tryParse('${unread ?? ''}') ?? 0,
    ));
  }
  return out;
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (Ref ref) => DashboardRepositoryImpl(ref.watch(apiClientProvider)),
);

/// Auto-disposing read — the dashboard refetches when the tab is revisited
/// rather than showing a stale snapshot.
final dashboardSummaryProvider =
    FutureProvider.autoDispose<DashboardSummary>((Ref ref) {
  return ref.watch(dashboardRepositoryProvider).fetch();
});
