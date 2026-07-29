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
