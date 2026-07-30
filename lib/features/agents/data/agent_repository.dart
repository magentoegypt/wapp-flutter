import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/network/api_client.dart';

/// A teammate in the workspace, plus the performance figures the backend
/// already computes in AgentTargetEngine (csatPerAgent / responseTimePerAgent).
class Agent {
  const Agent({
    required this.uid,
    required this.name,
    required this.email,
    this.role = 'agent',
    this.teams = const <String>[],
    this.openConversations = 0,
    this.resolvedToday = 0,
    this.avgResponseSeconds = 0,
    this.csatPercent,
    this.online = false,
  });

  final String uid;
  final String name;
  final String email;
  final String role;
  final List<String> teams;
  final int openConversations;
  final int resolvedToday;
  final int avgResponseSeconds;

  /// Null when this agent has no quality reviews yet — render "—" rather than
  /// a misleading 0%.
  final int? csatPercent;
  final bool online;
}

abstract interface class AgentRepository {
  Future<List<Agent>> list();
  Future<Agent> byUid(String uid);
}

class AgentRepositoryImpl implements AgentRepository {
  const AgentRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<List<Agent>> list() async {
    final dynamic body = await _api.get('/agents');
    if (body is List) {
      return body.whereType<Map<String, dynamic>>().map(agentFromJson).toList();
    }
    final Map<String, dynamic> m =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final List<dynamic> rows =
        (m['agents'] ?? m['data']) as List<dynamic>? ?? const <dynamic>[];
    return rows.whereType<Map<String, dynamic>>().map(agentFromJson).toList();
  }

  /// `GET /agents/{uid}` exists as of the 30 Jul API pass and is vendor-scoped
  /// through the `vendor_users` pivot — a foreign or unknown uid 404s
  /// identically. This used to filter the whole list client-side because the
  /// endpoint returned 404 for everything.
  @override
  Future<Agent> byUid(String uid) async {
    final dynamic body = await _api.get('/agents/$uid');
    final Map<String, dynamic> m =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    // Singular key, matching the rest of the API's detail endpoints, with a
    // bare-body fallback.
    final Map<String, dynamic> row =
        (m['agent'] as Map<String, dynamic>?) ?? m;
    if (row.isEmpty) {
      throw const NotFoundFailure('That teammate no longer exists.');
    }
    return agentFromJson(row);
  }
}

int _int(Object? v) => v is num ? v.round() : int.tryParse('${v ?? ''}') ?? 0;

Agent agentFromJson(Map<String, dynamic> j) {
  final Object? csat = j['csat'];
  return Agent(
    uid: (j['uid'] ?? j['_uid'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    email: (j['email'] ?? '').toString(),
    role: (j['role'] ?? 'agent').toString(),
    // The API returns a single `team` string, not a list.
    teams: (j['teams'] is List)
        ? (j['teams'] as List<dynamic>)
            .map((dynamic e) =>
                e is Map ? (e['title'] ?? e['name'] ?? '').toString() : e.toString())
            .where((String s) => s.isNotEmpty)
            .toList()
        : <String>[
            if ((j['team'] as String?)?.isNotEmpty ?? false) j['team'] as String,
          ],
    openConversations: _int(j['activeChats'] ?? j['openConversations']),
    // Not exposed by /agents today — AgentTargetEngine computes CSAT and
    // response time server-side but the mobile endpoint does not surface them.
    resolvedToday: _int(j['resolvedToday']),
    avgResponseSeconds: _int(j['avgResponseSecs']),
    csatPercent: csat == null ? null : _int(csat),
    // `active` is the account-enabled flag, the closest thing to presence.
    online: (j['active'] as bool?) ?? false,
  );
}

final agentRepositoryProvider = Provider<AgentRepository>(
  (Ref ref) => AgentRepositoryImpl(ref.watch(apiClientProvider)),
);

final agentListProvider = FutureProvider.autoDispose<List<Agent>>((Ref ref) {
  return ref.watch(agentRepositoryProvider).list();
});

final agentDetailProvider =
    FutureProvider.autoDispose.family<Agent, String>((Ref ref, String uid) {
  return ref.watch(agentRepositoryProvider).byUid(uid);
});
