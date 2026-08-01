import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/envelope.dart';

/// A team, with its roster when the detail endpoint has been read.
class WorkTeam {
  const WorkTeam({
    required this.uid,
    required this.title,
    this.memberCount = 0,
    this.members = const <TeamMember>[],
  });

  final String uid;
  final String title;

  /// From the list, which sends a count rather than the roster.
  final int memberCount;

  /// Only populated by [TeamRepository.byUid].
  final List<TeamMember> members;

  /// The list has a count; the detail has the roster and no count.
  int get displayCount => members.isNotEmpty ? members.length : memberCount;

  static WorkTeam fromJson(Map<String, dynamic> j) {
    final List<dynamic> raw =
        (j['members'] ?? j['users']) as List<dynamic>? ?? const <dynamic>[];
    final Object? count = j['memberCount'] ?? j['members_count'];

    return WorkTeam(
      uid: '${j['uid'] ?? j['_uid'] ?? ''}',
      title: '${j['title'] ?? j['name'] ?? ''}',
      memberCount: count is num
          ? count.round()
          : int.tryParse('${count ?? ''}') ?? 0,
      members: raw
          .whereType<Map<String, dynamic>>()
          .map(TeamMember.fromJson)
          .whereType<TeamMember>()
          .toList(growable: false),
    );
  }
}

class TeamMember {
  const TeamMember({required this.uid, required this.name, this.role});

  final String uid;
  final String name;
  final String? role;

  static TeamMember? fromJson(Map<String, dynamic> j) {
    final String name =
        '${j['name'] ?? j['fullName'] ?? j['title'] ?? ''}'.trim();
    if (name.isEmpty) return null;
    return TeamMember(
      uid: '${j['uid'] ?? j['_uid'] ?? ''}',
      name: name,
      role: (j['role'] ?? j['roleTitle']) as String?,
    );
  }
}

/// Team CRUD.
///
/// `GET /teams` predates this — the transfer and assign screens have used it as
/// a picker all along. The rest arrived with the 31 Jul API pass.
///
/// **Membership is not editable here.** The console's own form posts `members`
/// as an array of integer `_id`s, which is a form detail an API almost
/// certainly translates to uids — but the API controller is not in this
/// checkout and its `routes/api.php` carries none of the `/api/v1` surface, so
/// the field name and id format cannot be confirmed. Sending a guessed key that
/// the server quietly ignores is precisely the silent failure this app keeps
/// finding, so the roster is shown and not edited.
abstract interface class TeamRepository {
  Future<List<WorkTeam>> list();
  Future<WorkTeam> byUid(String uid);
  Future<void> create(String title);
  Future<void> update(String uid, String title);
  Future<void> delete(String uid);
}

class TeamRepositoryImpl implements TeamRepository {
  const TeamRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<List<WorkTeam>> list() async => envelopeRows(
        await _api.get('/teams'),
        'teams',
      ).map(WorkTeam.fromJson).toList();

  @override
  Future<WorkTeam> byUid(String uid) async => WorkTeam.fromJson(
        envelopeRecord(await _api.get('/teams/$uid'), 'team'),
      );

  @override
  Future<void> create(String title) =>
      _api.post('/teams', body: <String, dynamic>{'title': title});

  @override
  Future<void> update(String uid, String title) =>
      _api.put('/teams/$uid', body: <String, dynamic>{'title': title});

  @override
  Future<void> delete(String uid) => _api.delete('/teams/$uid');
}

/// `title` is required, 2–255 characters.
abstract final class TeamLimits {
  static const int titleMin = 2;
  static const int titleMax = 255;
}

final teamRepositoryProvider = Provider<TeamRepository>(
  (Ref ref) => TeamRepositoryImpl(ref.watch(apiClientProvider)),
);

final teamListProvider = FutureProvider<List<WorkTeam>>(
  (Ref ref) => ref.watch(teamRepositoryProvider).list(),
);

final teamProvider = FutureProvider.autoDispose.family<WorkTeam, String>(
  (Ref ref, String uid) => ref.watch(teamRepositoryProvider).byUid(uid),
);
