import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../calls/domain/call.dart';
import '../domain/action_models.dart';

/// Every write the ⋮ sheet can perform, plus the reads those screens need.
///
/// One repository rather than a dozen: they all hang off `/conversations/{uid}`
/// and share the same envelope handling, and splitting them would spread that
/// across files that each had one method.
abstract interface class ConversationActionRepository {
  // ── snooze ────────────────────────────────────────────────────────────────
  /// [until] is an absolute local time, not a duration. [timezone] is the IANA
  /// name it should be read in.
  Future<void> snooze({
    required String contactUid,
    required DateTime until,
    required String timezone,
    String? reason,
  });

  Future<void> unsnooze(String contactUid);

  // ── routing ───────────────────────────────────────────────────────────────
  /// A transfer *request*, subject to approval policy — not the same as
  /// assigning. Exactly one of [toTeamUid] / [toUserUid] must be set.
  Future<void> transfer({
    required String contactUid,
    String? toTeamUid,
    String? toUserUid,
    String? reason,
  });

  /// Sets the owner directly. A null [userUid] unassigns.
  Future<void> assignUser({required String contactUid, String? userUid});

  /// Note the plural: there is no `/assign-team`. An empty list clears.
  Future<void> assignTeams({
    required String contactUid,
    required List<String> teamUids,
  });

  Future<List<Team>> teams();

  // ── review ────────────────────────────────────────────────────────────────
  /// An internal manager review, **not** CSAT. [agentUid] defaults server-side
  /// to the conversation's assigned agent.
  Future<void> qualityReview({
    required String contactUid,
    required int score,
    String? agentUid,
    String? comment,
    List<String> criteria,
  });

  // ── labels ────────────────────────────────────────────────────────────────
  Future<List<ConversationLabel>> labels();

  /// Replaces the set — send an empty list to clear.
  Future<void> setLabels({
    required String contactUid,
    required List<String> labelUids,
  });

  // ── templates ─────────────────────────────────────────────────────────────
  Future<List<MessageTemplate>> templates();

  /// Detail carries the derived field keys the send form has to render.
  Future<MessageTemplate> template(String templateUid);

  Future<void> sendTemplate({
    required String contactUid,
    required String templateUid,
    Map<String, String> fields,
  });

  // ── calls ─────────────────────────────────────────────────────────────────
  Future<CallHistoryPage> callHistory(String contactUid, {int page});

  Future<void> requestCallPermission(String contactUid);

  // ── history access ────────────────────────────────────────────────────────
  Future<HistoryAccessSnapshot> historyAccess(String contactUid);
  Future<void> requestHistoryAccess(String contactUid);
  Future<void> decideHistoryAccess({required String requestUid, required bool approve});
  Future<void> revokeHistoryAccess(String requestUid);

  /// Workspace-wide per-contact visibility. Admin only.
  Future<void> revealFullHistory({required String contactUid, required bool reveal});

  // ── destructive ───────────────────────────────────────────────────────────
  /// Deletes the stored message log **workspace-wide**. Irreversible.
  Future<void> clearHistory(String contactUid);

  // ── reminders ─────────────────────────────────────────────────────────────
  Future<List<Reminder>> reminders(String contactUid);

  Future<void> createReminder({
    required String contactUid,
    required String templateUid,
    required DateTime scheduleAt,
    Map<String, String> fields,
  });

  Future<void> updateReminder({
    required String reminderUid,
    DateTime? scheduleAt,
    Map<String, String>? fields,
  });

  Future<void> deleteReminder(String reminderUid);

  // ── favourite ─────────────────────────────────────────────────────────────
  /// Under `/conversations/`, not `/contacts/`. Toggle; returns the new state.
  Future<bool> toggleFavourite(String contactUid);
}

/// One page of call history.
///
/// The endpoint answers `{calls, page, hasMore}` — its own envelope, not the
/// standard one — so it gets its own return type rather than being forced
/// through the shared list shim.
class CallHistoryPage {
  const CallHistoryPage({
    required this.calls,
    required this.page,
    required this.hasMore,
  });

  final List<CallRecord> calls;
  final int page;
  final bool hasMore;
}

class ConversationActionRepositoryImpl implements ConversationActionRepository {
  const ConversationActionRepositoryImpl(this._api);

  final ApiClient _api;

  String _base(String contactUid) => '/conversations/$contactUid';

  @override
  Future<void> snooze({
    required String contactUid,
    required DateTime until,
    required String timezone,
    String? reason,
  }) async {
    await _api.post('${_base(contactUid)}/snooze', body: <String, dynamic>{
      // `Y-m-d\TH:i` local wall clock — the server reads it in `timezone`.
      // Sending an ISO instant here would be silently reinterpreted.
      'until': _localStamp(until),
      'timezone': timezone,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  @override
  Future<void> unsnooze(String contactUid) =>
      _api.delete('${_base(contactUid)}/snooze');

  @override
  Future<void> transfer({
    required String contactUid,
    String? toTeamUid,
    String? toUserUid,
    String? reason,
  }) async {
    await _api.post('${_base(contactUid)}/transfer', body: <String, dynamic>{
      if (toTeamUid != null) 'toTeamUid': toTeamUid,
      if (toUserUid != null) 'toUserUid': toUserUid,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  @override
  Future<void> assignUser({required String contactUid, String? userUid}) async {
    await _api.post('${_base(contactUid)}/assign-user',
        body: <String, dynamic>{'userUid': userUid});
  }

  @override
  Future<void> assignTeams({
    required String contactUid,
    required List<String> teamUids,
  }) async {
    await _api.post('${_base(contactUid)}/assign-teams',
        body: <String, dynamic>{'teamUids': teamUids});
  }

  @override
  Future<List<Team>> teams() async {
    final dynamic body = await _api.get('/teams');
    return _rows(body, 'teams')
        .map((Map<String, dynamic> j) => Team(
              uid: '${j['uid'] ?? j['_uid'] ?? ''}',
              name: '${j['name'] ?? j['title'] ?? ''}',
            ))
        .toList();
  }

  @override
  Future<void> qualityReview({
    required String contactUid,
    required int score,
    String? agentUid,
    String? comment,
    List<String> criteria = const <String>[],
  }) async {
    await _api.post('${_base(contactUid)}/quality-review',
        body: <String, dynamic>{
          'score': score,
          if (agentUid != null) 'agentUid': agentUid,
          if (comment != null && comment.trim().isNotEmpty)
            'comment': comment.trim(),
          if (criteria.isNotEmpty) 'criteria': criteria,
        });
  }

  @override
  Future<List<ConversationLabel>> labels() async {
    final dynamic body = await _api.get('/labels');
    return _rows(body, 'labels')
        .map((Map<String, dynamic> j) => ConversationLabel(
              uid: '${j['uid'] ?? j['_uid'] ?? ''}',
              name: '${j['name'] ?? j['title'] ?? ''}',
              color: j['color'] as String?,
            ))
        .toList();
  }

  @override
  Future<void> setLabels({
    required String contactUid,
    required List<String> labelUids,
  }) async {
    await _api.post('${_base(contactUid)}/labels',
        body: <String, dynamic>{'labelUids': labelUids});
  }

  @override
  Future<List<MessageTemplate>> templates() async {
    final dynamic body = await _api.get('/templates');
    return _rows(body, 'templates').map(_templateFromJson).toList();
  }

  @override
  Future<MessageTemplate> template(String templateUid) async {
    final dynamic body = await _api.get('/templates/$templateUid');
    final Map<String, dynamic> m = (body as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    return _templateFromJson(
      (m['template'] as Map<String, dynamic>?) ?? m,
    );
  }

  @override
  Future<void> sendTemplate({
    required String contactUid,
    required String templateUid,
    Map<String, String> fields = const <String, String>{},
  }) async {
    await _api.post('${_base(contactUid)}/messages/template',
        body: <String, dynamic>{
          'templateUid': templateUid,
          'fields': fields,
        });
  }

  @override
  Future<CallHistoryPage> callHistory(String contactUid, {int page = 1}) async {
    final dynamic body = await _api
        .get('${_base(contactUid)}/calls', query: <String, dynamic>{'page': page});
    final Map<String, dynamic> m =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return CallHistoryPage(
      calls: _rows(m, 'calls').map(callRecordFromJson).toList(),
      page: _int(m['page'], fallback: page),
      hasMore: (m['hasMore'] as bool?) ?? false,
    );
  }

  @override
  Future<void> requestCallPermission(String contactUid) =>
      _api.post('${_base(contactUid)}/call-permission');

  @override
  Future<HistoryAccessSnapshot> historyAccess(String contactUid) async {
    final dynamic body = await _api.get('${_base(contactUid)}/history-access');
    final Map<String, dynamic> m =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final Map<String, dynamic> me =
        (m['currentUser'] as Map<String, dynamic>?) ?? const <String, dynamic>{};

    return HistoryAccessSnapshot(
      currentUserStatus: _accessStatus(me['status']),
      pending: _rows(m, 'pending').map(_accessRequestFromJson).toList(),
      approved: _rows(m, 'approved').map(_accessRequestFromJson).toList(),
      isVendorAdmin: (m['isVendorAdmin'] as bool?) ?? false,
      revealFullHistory: (m['revealFullHistory'] as bool?) ?? false,
    );
  }

  @override
  Future<void> requestHistoryAccess(String contactUid) =>
      _api.post('${_base(contactUid)}/history-access/request');

  @override
  Future<void> decideHistoryAccess({
    required String requestUid,
    required bool approve,
  }) async {
    await _api.post('/history-access/$requestUid',
        body: <String, dynamic>{'approve': approve});
  }

  @override
  Future<void> revokeHistoryAccess(String requestUid) =>
      _api.delete('/history-access/$requestUid');

  @override
  Future<void> revealFullHistory({
    required String contactUid,
    required bool reveal,
  }) async {
    await _api.post('${_base(contactUid)}/reveal-history',
        body: <String, dynamic>{'reveal': reveal});
  }

  @override
  Future<void> clearHistory(String contactUid) {
    // The confirm flag is the API's own safety catch, and the reason
    // ApiClient.delete had to learn to carry a body.
    return _api.delete('${_base(contactUid)}/messages',
        body: <String, dynamic>{'confirm': true});
  }

  @override
  Future<List<Reminder>> reminders(String contactUid) async {
    final dynamic body = await _api.get('${_base(contactUid)}/reminders');
    return _rows(body, 'reminders').map(_reminderFromJson).toList();
  }

  @override
  Future<void> createReminder({
    required String contactUid,
    required String templateUid,
    required DateTime scheduleAt,
    Map<String, String> fields = const <String, String>{},
  }) async {
    await _api.post('${_base(contactUid)}/reminders', body: <String, dynamic>{
      'templateUid': templateUid,
      'scheduleAt': _localStamp(scheduleAt),
      'fields': fields,
    });
  }

  @override
  Future<void> updateReminder({
    required String reminderUid,
    DateTime? scheduleAt,
    Map<String, String>? fields,
  }) async {
    await _api.put('/reminders/$reminderUid', body: <String, dynamic>{
      if (scheduleAt != null) 'scheduleAt': _localStamp(scheduleAt),
      if (fields != null) 'fields': fields,
    });
  }

  @override
  Future<void> deleteReminder(String reminderUid) =>
      _api.delete('/reminders/$reminderUid');

  @override
  Future<bool> toggleFavourite(String contactUid) async {
    final dynamic body = await _api.post('${_base(contactUid)}/favorite');
    final Map<String, dynamic> m =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return (m['favorite'] as bool?) ?? false;
  }
}

/// `Y-m-d\TH:i` — a local wall clock with no zone marker.
///
/// Both `snooze.until` and `reminder.scheduleAt` are parsed server-side in the
/// workspace's own timezone. Sending `toIso8601String()` would append a `Z` or
/// an offset and be reinterpreted, shifting every scheduled item by the offset
/// — which surfaces as reminders firing at the wrong hour rather than as an
/// error.
String _localStamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:${two(t.minute)}';
}

List<Map<String, dynamic>> _rows(dynamic body, String key) {
  if (body is List) return body.whereType<Map<String, dynamic>>().toList();
  final Map<String, dynamic> m =
      (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
  final List<dynamic> raw =
      (m[key] ?? m['data']) as List<dynamic>? ?? const <dynamic>[];
  return raw.whereType<Map<String, dynamic>>().toList();
}

int _int(Object? v, {int fallback = 0}) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? fallback;
}

DateTime? _date(Object? v) {
  final String s = '${v ?? ''}';
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

HistoryAccessStatus _accessStatus(Object? raw) {
  switch ('${raw ?? ''}'.trim().toLowerCase()) {
    case 'pending':
      return HistoryAccessStatus.pending;
    case 'approved':
      return HistoryAccessStatus.approved;
    case 'denied':
      return HistoryAccessStatus.denied;
    default:
      return HistoryAccessStatus.none;
  }
}

HistoryAccessRequest _accessRequestFromJson(Map<String, dynamic> j) {
  return HistoryAccessRequest(
    uid: '${j['uid'] ?? j['requestUid'] ?? ''}',
    agentName: '${j['agentName'] ?? j['userName'] ?? j['name'] ?? ''}',
    requestedAt: _date(j['requestedAt'] ?? j['createdAt']),
    status: _accessStatus(j['status']),
  );
}

MessageTemplate _templateFromJson(Map<String, dynamic> j) {
  final List<dynamic> raw =
      (j['fields'] ?? j['placeholders']) as List<dynamic>? ?? const <dynamic>[];

  return MessageTemplate(
    uid: '${j['uid'] ?? j['_uid'] ?? ''}',
    name: '${j['name'] ?? j['title'] ?? ''}',
    language: j['language'] as String?,
    category: j['category'] as String?,
    body: (j['body'] ?? j['text']) as String?,
    fields: raw.map((dynamic f) {
      // A field arrives either as a bare key or as an object describing one.
      if (f is String) return TemplateField(key: f);
      final Map<String, dynamic> m =
          (f as Map<String, dynamic>?) ?? const <String, dynamic>{};
      return TemplateField(
        key: '${m['key'] ?? m['name'] ?? ''}',
        label: m['label'] as String?,
        example: (m['example'] ?? m['sample']) as String?,
      );
    }).where((TemplateField f) => f.key.isNotEmpty).toList(),
  );
}

Reminder _reminderFromJson(Map<String, dynamic> j) {
  final Map<String, dynamic> f =
      (j['fields'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
  return Reminder(
    uid: '${j['uid'] ?? j['_uid'] ?? ''}',
    templateUid: j['templateUid'] as String?,
    templateName: (j['templateName'] ?? j['template']) as String?,
    scheduleAt: _date(j['scheduleAt'] ?? j['messagedAt']),
    fields: f.map((String k, dynamic v) => MapEntry<String, String>(k, '$v')),
  );
}

CallRecord callRecordFromJson(Map<String, dynamic> j) {
  return CallRecord(
    uid: '${j['uid'] ?? ''}',
    callId: j['callId'] as String?,
    isIncoming: (j['isIncoming'] as bool?) ?? true,
    status: CallStatusX.fromApi(j['status']),
    initiatedAt: _date(j['initiatedAt']),
    connectedAt: _date(j['connectedAt']),
    endedAt: _date(j['endedAt']),
    durationSeconds: _int(j['durationSeconds']),
    durationText: j['durationText'] as String?,
    initiatedAtText: j['initiatedAtText'] as String?,
    initiatedAgoText: j['initiatedAgoText'] as String?,
    receivedOn: j['receivedOn'] as String?,
    outsideBusinessHours: (j['outsideBusinessHours'] as bool?) ?? false,
    callbackConsentGiven: (j['callbackConsentGiven'] as bool?) ?? false,
    recordingEnabled: (j['recordingEnabled'] as bool?) ?? false,
    hasRecording: (j['hasRecording'] as bool?) ?? false,
    recordingUrl: j['recordingUrl'] as String?,
  );
}

final conversationActionRepositoryProvider =
    Provider<ConversationActionRepository>(
  (Ref ref) => ConversationActionRepositoryImpl(ref.watch(apiClientProvider)),
);

final teamsProvider = FutureProvider.autoDispose<List<Team>>((Ref ref) {
  return ref.watch(conversationActionRepositoryProvider).teams();
});

final conversationLabelsProvider =
    FutureProvider.autoDispose<List<ConversationLabel>>((Ref ref) {
  return ref.watch(conversationActionRepositoryProvider).labels();
});

final templatesProvider =
    FutureProvider.autoDispose<List<MessageTemplate>>((Ref ref) {
  return ref.watch(conversationActionRepositoryProvider).templates();
});

final templateDetailProvider = FutureProvider.autoDispose
    .family<MessageTemplate, String>((Ref ref, String uid) {
  return ref.watch(conversationActionRepositoryProvider).template(uid);
});

final historyAccessProvider = FutureProvider.autoDispose
    .family<HistoryAccessSnapshot, String>((Ref ref, String contactUid) {
  return ref.watch(conversationActionRepositoryProvider).historyAccess(contactUid);
});

final remindersProvider = FutureProvider.autoDispose
    .family<List<Reminder>, String>((Ref ref, String contactUid) {
  return ref.watch(conversationActionRepositoryProvider).reminders(contactUid);
});

final callHistoryProvider = FutureProvider.autoDispose
    .family<CallHistoryPage, String>((Ref ref, String contactUid) {
  return ref.watch(conversationActionRepositoryProvider).callHistory(contactUid);
});
