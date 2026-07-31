import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/util/enum_from_json.dart';
import '../../contacts/domain/contact.dart' show NamedRef;

/// Record lifecycle — the `status` field, `campaigns.status`.
///
/// Says whether the campaign record is live, held or filed away. It says
/// nothing about whether anything was sent, which is why it is not what a badge
/// should show.
enum CampaignLifecycle { active, paused, archived }

/// Send progress — the `executionStatus` field.
///
/// The stable machine value, and the one to branch on. The client used to parse
/// `statusText`, which is a translated display label; anything unrecognised fell
/// back to a `draft` state that **does not exist anywhere in the campaign
/// domain**, so every campaign was mislabelled. There is no draft.
enum CampaignExecution { upcoming, awaiting, processing, executed, paused, na }

class Campaign {
  const Campaign({
    required this.uid,
    required this.title,
    required this.lifecycle,
    required this.execution,
    this.templateName,
    this.scheduledAt,
    this.totalContacts = 0,
    this.sent = 0,
    this.delivered = 0,
    this.read = 0,
    this.failed = 0,
  });

  final String uid;
  final String title;
  final CampaignLifecycle lifecycle;
  final CampaignExecution execution;

  /// Filed away rather than live. Drives the Active/Archive split; paused
  /// campaigns stay under Active because they are still someone's open work.
  bool get isArchived => lifecycle == CampaignLifecycle.archived;
  final String? templateName;
  final DateTime? scheduledAt;
  final int totalContacts;
  final int sent;
  final int delivered;
  final int read;
  final int failed;
}

/// Dropdown data for Create campaign, fetched in one call.
class CampaignMeta {
  const CampaignMeta({
    this.templates = const <NamedRef>[],
    this.groups = const <NamedRef>[],
  });

  final List<NamedRef> templates;
  final List<NamedRef> groups;

  static const CampaignMeta empty = CampaignMeta();
}

abstract interface class CampaignRepository {
  Future<List<Campaign>> list({String? query});
  Future<Campaign> byUid(String uid);
  Future<CampaignMeta> meta();
  Future<void> create({
    required String title,
    required String templateName,
    List<String> groupIds,
    DateTime? scheduledAt,
  });
}

class CampaignRepositoryImpl implements CampaignRepository {
  const CampaignRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<List<Campaign>> list({String? query}) async {
    // `?q=` is served by the API as of the 30 Jul pass; the screen used to
    // filter the loaded page itself, which only ever searched what had already
    // been fetched.
    final dynamic body = await _api.get(
      '/campaigns',
      query: <String, dynamic>{
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
    if (body is List) {
      return body.whereType<Map<String, dynamic>>().map(campaignFromJson).toList();
    }
    final Map<String, dynamic> m =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final List<dynamic> rows =
        (m['campaigns'] ?? m['data']) as List<dynamic>? ?? const <dynamic>[];
    return rows.whereType<Map<String, dynamic>>().map(campaignFromJson).toList();
  }

  @override
  Future<Campaign> byUid(String uid) async {
    final dynamic body = await _api.get('/campaigns/$uid');
    final Map<String, dynamic> m =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    // Singular domain key, not `data`.
    return campaignFromJson((m['campaign'] as Map<String, dynamic>?) ??
        (m['data'] as Map<String, dynamic>?) ??
        m);
  }

  @override
  Future<CampaignMeta> meta() async {
    final dynamic body = await _api.get('/campaigns/meta');
    final Map<String, dynamic> j = (body as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    List<NamedRef> refs(Object? raw) => raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map((Map<String, dynamic> e) => NamedRef(
                  id: (e['uid'] ?? e['id'] ?? e['name'] ?? '').toString(),
                  name: (e['title'] ?? e['name'] ?? '').toString(),
                ))
            .toList()
        : const <NamedRef>[];
    return CampaignMeta(
      templates: refs(j['templates']),
      groups: refs(j['groups']),
    );
  }

  @override
  Future<void> create({
    required String title,
    required String templateName,
    List<String> groupIds = const <String>[],
    DateTime? scheduledAt,
  }) {
    return _api.post('/campaigns', body: <String, dynamic>{
      'title': title,
      'template_name': templateName,
      if (groupIds.isNotEmpty) 'groups': groupIds,
      if (scheduledAt != null) 'scheduled_at': scheduledAt.toUtc().toIso8601String(),
    });
  }
}

int _int(Object? v) => v is num ? v.round() : int.tryParse('${v ?? ''}') ?? 0;


Campaign campaignFromJson(Map<String, dynamic> j) {
  // Detail is now a strict superset of a list row, but the stats still nest:
  // detail puts them under `stats` and renames two — `opened` for read receipts
  // and `unreached` for failures. Reading only the list's names made the detail
  // screen show Read 0 when the real figure was 2.
  //
  // `statusText` is deliberately not read. It is a translated display label, so
  // branching on it is locale-dependent by construction; the client renders its
  // own localized label from `executionStatus` instead.
  final Map<String, dynamic> stats =
      (j['stats'] as Map<String, dynamic>?) ?? const <String, dynamic>{};

  return Campaign(
    uid: (j['uid'] ?? j['_uid'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    lifecycle: enumByName(
      j['status'],
      CampaignLifecycle.values,
      CampaignLifecycle.active,
    ),
    execution: enumByName(
      j['executionStatus'] ?? j['execution_status'],
      CampaignExecution.values,
      CampaignExecution.na,
    ),

    templateName: (j['templateName'] ?? j['template_name']) as String?,
    scheduledAt: DateTime.tryParse('${j['scheduledAt'] ?? ''}')?.toLocal(),
    // `targeted` is the audience size; `allContacts` means the whole book.
    totalContacts: _int(j['targeted'] ?? stats['targeted'] ?? j['totalContacts']),
    sent: _int(stats['sent'] ?? j['sent']),
    delivered: _int(stats['delivered'] ?? j['delivered']),
    read: _int(stats['opened'] ?? stats['read'] ?? j['read']),
    failed: _int(stats['unreached'] ?? stats['failed'] ?? j['failed']),
  );
}

final campaignRepositoryProvider = Provider<CampaignRepository>(
  (Ref ref) => CampaignRepositoryImpl(ref.watch(apiClientProvider)),
);

/// Free-text filter, sent to the API rather than applied to the loaded page.
final campaignSearchProvider = StateProvider<String>((Ref ref) => '');

final campaignListProvider = FutureProvider.autoDispose<List<Campaign>>((Ref ref) {
  final String q = ref.watch(campaignSearchProvider);
  return ref.watch(campaignRepositoryProvider).list(query: q);
});

final campaignDetailProvider =
    FutureProvider.autoDispose.family<Campaign, String>((Ref ref, String uid) {
  return ref.watch(campaignRepositoryProvider).byUid(uid);
});

final campaignMetaProvider = FutureProvider.autoDispose<CampaignMeta>((Ref ref) {
  return ref.watch(campaignRepositoryProvider).meta();
});
