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

/// Tolerant mapper: every field falls back to a zero value so a partial
/// payload degrades to an honest-looking empty dashboard rather than throwing.
DashboardSummary dashboardFromJson(Map<String, dynamic> json) {
  int asInt(Object? v) => (v as num?)?.round() ?? 0;

  return DashboardSummary(
    open: asInt(json['open']),
    resolvedToday: asInt(json['resolvedToday'] ?? json['resolved_today']),
    avgResponseSeconds:
        asInt(json['avgResponseSecs'] ?? json['avg_response_secs']),
    csatPercent: asInt(json['csat']),
    week: ((json['week'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> e) => DayCount(
              weekday: asInt(e['weekday']),
              count: asInt(e['count']),
            ))
        .toList(),
    queue: ((json['queue'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> e) => QueueItem(
              contactUid: (e['contactUid'] ?? e['contact_uid'] ?? '').toString(),
              name: (e['name'] ?? '').toString(),
              waitingSeconds: asInt(e['waitingFor'] ?? e['waiting_for']),
            ))
        .toList(),
  );
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
